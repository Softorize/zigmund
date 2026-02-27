const std = @import("std");
const types = @import("types.zig");
const params = @import("../params/mod.zig");
const security = @import("../security/mod.zig");
const BackgroundTasks = @import("background.zig").BackgroundTasks;
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const c = @cImport({
    @cInclude("regex.h");
});

pub const HttpHandler = *const fn (*Request, std.mem.Allocator) anyerror!Response;

const ResolveContext = struct {
    allocator: std.mem.Allocator,
    stack: std.ArrayListUnmanaged([]const u8) = .empty,
    request_cache: std.StringHashMapUnmanaged([]u8) = .empty,

    fn init(allocator: std.mem.Allocator) ResolveContext {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *ResolveContext) void {
        var it = self.request_cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.request_cache.deinit(self.allocator);
        self.stack.deinit(self.allocator);
    }

    fn push(self: *ResolveContext, key: []const u8) !void {
        try self.stack.append(self.allocator, key);
    }

    fn pop(self: *ResolveContext) void {
        if (self.stack.items.len == 0) return;
        self.stack.items.len -= 1;
    }

    fn contains(self: *const ResolveContext, key: []const u8) bool {
        for (self.stack.items) |current| {
            if (std.mem.eql(u8, current, key)) return true;
        }
        return false;
    }

    fn getCached(self: *const ResolveContext, key: []const u8) ?[]const u8 {
        return self.request_cache.get(key);
    }

    fn setCached(self: *ResolveContext, key: []const u8, value: []const u8) !void {
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        if (self.request_cache.fetchRemove(key)) |removed| {
            self.allocator.free(removed.value);
        }
        try self.request_cache.put(self.allocator, key, owned_value);
    }
};

pub fn bindHttpHandler(comptime handler: anytype) HttpHandler {
    const Handler = struct {
        fn run(req: *Request, allocator: std.mem.Allocator) anyerror!Response {
            return invokeInjected(handler, req, allocator);
        }
    };
    return Handler.run;
}

pub fn deriveOpenApiDependencies(comptime handler: anytype) []const types.DependencySpec {
    const HandlerType = @TypeOf(handler);
    if (@typeInfo(HandlerType) != .@"fn") return &.{};

    const count = comptime countProviderMarkers(HandlerType);
    if (count == 0) return &.{};

    const Derived = struct {
        const specs = buildProviderSpecs(HandlerType);
    };
    return &Derived.specs;
}

pub fn deriveOpenApiParameters(comptime handler: anytype) []const types.InjectedParameter {
    const HandlerType = @TypeOf(handler);
    if (@typeInfo(HandlerType) != .@"fn") return &.{};

    const count = comptime countParameterMarkers(HandlerType);
    if (count == 0) return &.{};

    const Derived = struct {
        const specs = buildParameterSpecs(HandlerType);
    };
    return &Derived.specs;
}

pub fn deriveOpenApiRequestBodies(comptime handler: anytype) []const types.InjectedRequestBody {
    const HandlerType = @TypeOf(handler);
    if (@typeInfo(HandlerType) != .@"fn") return &.{};

    const count = comptime countRequestBodyMarkers(HandlerType);
    if (count == 0) return &.{};

    const Derived = struct {
        const specs = buildRequestBodySpecs(HandlerType);
    };
    return &Derived.specs;
}

fn invokeInjected(comptime handler: anytype, req: *Request, allocator: std.mem.Allocator) anyerror!Response {
    const HandlerType = @TypeOf(handler);
    if (@typeInfo(HandlerType) != .@"fn") {
        @compileError("Injected handler must be a function");
    }

    const fn_info = @typeInfo(HandlerType).@"fn";
    const ArgsTuple = std.meta.ArgsTuple(HandlerType);
    var context = ResolveContext.init(allocator);
    defer context.deinit();

    var args: ArgsTuple = undefined;
    inline for (fn_info.params, 0..) |param, idx| {
        const ParamType = param.type orelse @compileError("Handler parameters must have concrete types");
        @field(args, std.fmt.comptimePrint("{d}", .{idx})) = try resolveArg(ParamType, req, allocator, &context);
    }

    const result = @call(.auto, handler, args);
    return adaptReturn(HandlerType, result);
}

fn resolveArg(
    comptime ParamType: type,
    req: *Request,
    allocator: std.mem.Allocator,
    context: *ResolveContext,
) anyerror!ParamType {
    if (ParamType == *Request) return req;
    if (ParamType == *BackgroundTasks) return req.backgroundTasks();
    if (ParamType == std.mem.Allocator) return allocator;

    if (comptime isParamMarkerType(ParamType)) {
        return try resolveParamMarker(ParamType, req);
    }

    if (comptime isProviderMarkerType(ParamType)) {
        return try resolveProviderMarker(ParamType, req, allocator, context);
    }

    @compileError(
        "Unsupported handler parameter type `" ++ @typeName(ParamType) ++
            "`. Use *Request, *BackgroundTasks, std.mem.Allocator, Query/Path/Header/Cookie/Body/Form/File, Depends, or Security.",
    );
}

fn isParamMarkerType(comptime T: type) bool {
    if (!isContainerType(T)) return false;
    return @hasDecl(T, "Location") and @hasDecl(T, "ValueType") and @hasDecl(T, "options") and @hasField(T, "value");
}

fn resolveParamMarker(comptime Marker: type, req: *Request) anyerror!Marker {
    const location = Marker.Location;
    const ValueType = Marker.ValueType;
    const strict_mode = isStrictModeEnabled(Marker, req);

    var out: Marker = .{};

    switch (location) {
        .query => {
            const key = Marker.options.alias orelse @compileError("Query marker requires `alias` for automatic injection");
            const raw_value = req.queryParam(key);
            if (raw_value == null) {
                if (Marker.options.required) {
                    try req.addValidationIssue(.{
                        .location = .query,
                        .field = key,
                        .message = "Field required",
                        .issue_type = "missing",
                    });
                    return error.ValidationFailed;
                }
                out.value = null;
                return out;
            }
            const parsed = try req.queryAs(ValueType, key);
            try validateMarkerInput(Marker, req, .query, key, raw_value, parsed, strict_mode);
            out.value = parsed;
        },
        .path => {
            const key = Marker.options.alias orelse @compileError("Path marker requires `alias` for automatic injection");
            const raw_value = req.param(key);
            const parsed = try req.paramAs(ValueType, key);
            try validateMarkerInput(Marker, req, .path, key, raw_value, parsed, strict_mode);
            out.value = parsed;
        },
        .header => {
            const key = Marker.options.alias orelse @compileError("Header marker requires `alias` for automatic injection");
            const raw_value = req.header(key);
            const parsed = try req.headerAs(ValueType, key);
            try validateMarkerInput(Marker, req, .header, key, raw_value, parsed, strict_mode);
            out.value = parsed;
        },
        .cookie => {
            const key = Marker.options.alias orelse @compileError("Cookie marker requires `alias` for automatic injection");
            const raw_value = req.cookie(key);
            const parsed = try req.cookieAs(ValueType, key);
            try validateMarkerInput(Marker, req, .cookie, key, raw_value, parsed, strict_mode);
            out.value = parsed;
        },
        .body => {
            try ensureBodyContentType(req, Marker.options.media_type);
            if (Marker.options.embed) {
                const Wrapper = EmbeddedBodyWrapper(ValueType);
                const wrapped = try req.bodyJsonLeaky(Wrapper);
                const parsed = wrapped.body;
                try validateMarkerInput(Marker, req, .body, "body", null, parsed, strict_mode);
                out.value = parsed;
            } else {
                const parsed = try req.bodyJsonLeaky(ValueType);
                try validateMarkerInput(Marker, req, .body, "body", null, parsed, strict_mode);
                out.value = parsed;
            }
        },
        .form => {
            try ensureFormContentType(req, Marker.options.media_type);
            const parsed = try req.formAsLeaky(ValueType);
            try validateMarkerInput(Marker, req, .body, "form", null, parsed, strict_mode);
            out.value = parsed;
        },
        .file => {
            try ensureFileRequestContentType(req);
            const parsed = try req.fileAsWithMediaType(ValueType, Marker.options.media_type);
            try validateMarkerInput(Marker, req, .body, "file", null, parsed, strict_mode);
            out.value = parsed;
        },
    }

    return out;
}

fn isStrictModeEnabled(comptime Marker: type, req: *const Request) bool {
    if (Marker.options.strict) return true;
    const raw = req.dependency("zigmund.validation.strict") orelse return false;
    return std.ascii.eqlIgnoreCase(raw, "true");
}

fn validateMarkerInput(
    comptime Marker: type,
    req: *Request,
    location: Request.ValidationLocation,
    field: []const u8,
    raw_value: ?[]const u8,
    parsed_value: Marker.ValueType,
    strict_mode: bool,
) !void {
    if (strict_mode) {
        try validateStrictMode(Marker.ValueType, req, location, field, raw_value);
    }
    try validateEnumConstraint(Marker, req, location, field, raw_value, parsed_value);
    try validateLengthAndPatternConstraints(Marker, req, location, field, raw_value, parsed_value);
    try validateNumericConstraints(Marker, req, location, field, raw_value, parsed_value);
}

fn validateStrictMode(
    comptime T: type,
    req: *Request,
    location: Request.ValidationLocation,
    field: []const u8,
    raw_value: ?[]const u8,
) !void {
    const input = raw_value orelse return;
    const Base = stripOptionalType(T);
    switch (@typeInfo(Base)) {
        .bool => {
            if (!std.ascii.eqlIgnoreCase(input, "true") and !std.ascii.eqlIgnoreCase(input, "false")) {
                try req.addValidationIssue(.{
                    .location = location,
                    .field = field,
                    .message = "Strict mode requires true/false for boolean values",
                    .issue_type = "strict_bool",
                    .input = input,
                });
                return error.ValidationFailed;
            }
        },
        else => {},
    }
}

fn validateEnumConstraint(
    comptime Marker: type,
    req: *Request,
    location: Request.ValidationLocation,
    field: []const u8,
    raw_value: ?[]const u8,
    parsed_value: Marker.ValueType,
) !void {
    if (Marker.options.enum_values.len == 0) return;

    if (raw_value) |raw| {
        if (stringInList(Marker.options.enum_values, raw)) return;
    }

    var value_buf: [128]u8 = undefined;
    if (scalarValueToString(Marker.ValueType, parsed_value, &value_buf)) |serialized| {
        if (stringInList(Marker.options.enum_values, serialized)) return;
    }

    try req.addValidationIssue(.{
        .location = location,
        .field = field,
        .message = "Value is not one of the allowed enum values",
        .issue_type = "enum",
        .input = raw_value,
    });
    return error.ValidationFailed;
}

fn validateLengthAndPatternConstraints(
    comptime Marker: type,
    req: *Request,
    location: Request.ValidationLocation,
    field: []const u8,
    raw_value: ?[]const u8,
    parsed_value: Marker.ValueType,
) !void {
    const candidate = stringConstraintValue(Marker.ValueType, raw_value, parsed_value) orelse return;

    if (Marker.options.min_length) |min_len| {
        if (candidate.len < min_len) {
            try req.addValidationIssue(.{
                .location = location,
                .field = field,
                .message = "String is shorter than min_length",
                .issue_type = "min_length",
                .input = candidate,
            });
            return error.ValidationFailed;
        }
    }

    if (Marker.options.max_length) |max_len| {
        if (candidate.len > max_len) {
            try req.addValidationIssue(.{
                .location = location,
                .field = field,
                .message = "String is longer than max_length",
                .issue_type = "max_length",
                .input = candidate,
            });
            return error.ValidationFailed;
        }
    }

    if (Marker.options.pattern) |pattern| {
        if (!patternMatches(candidate, pattern)) {
            try req.addValidationIssue(.{
                .location = location,
                .field = field,
                .message = "String does not match required pattern",
                .issue_type = "pattern",
                .input = candidate,
            });
            return error.ValidationFailed;
        }
    }
}

fn validateNumericConstraints(
    comptime Marker: type,
    req: *Request,
    location: Request.ValidationLocation,
    field: []const u8,
    raw_value: ?[]const u8,
    parsed_value: Marker.ValueType,
) !void {
    const numeric = numericAsF64(Marker.ValueType, parsed_value) orelse return;

    if (Marker.options.gt) |threshold| {
        if (!(numeric > threshold)) {
            try req.addValidationIssue(.{
                .location = location,
                .field = field,
                .message = "Value must be greater than gt",
                .issue_type = "gt",
                .input = raw_value,
            });
            return error.ValidationFailed;
        }
    }

    if (Marker.options.ge) |threshold| {
        if (!(numeric >= threshold)) {
            try req.addValidationIssue(.{
                .location = location,
                .field = field,
                .message = "Value must be greater than or equal to ge",
                .issue_type = "ge",
                .input = raw_value,
            });
            return error.ValidationFailed;
        }
    }

    if (Marker.options.lt) |threshold| {
        if (!(numeric < threshold)) {
            try req.addValidationIssue(.{
                .location = location,
                .field = field,
                .message = "Value must be less than lt",
                .issue_type = "lt",
                .input = raw_value,
            });
            return error.ValidationFailed;
        }
    }

    if (Marker.options.le) |threshold| {
        if (!(numeric <= threshold)) {
            try req.addValidationIssue(.{
                .location = location,
                .field = field,
                .message = "Value must be less than or equal to le",
                .issue_type = "le",
                .input = raw_value,
            });
            return error.ValidationFailed;
        }
    }
}

fn numericAsF64(comptime T: type, value: T) ?f64 {
    if (@typeInfo(T) == .optional) {
        if (value == null) return null;
        const Child = @typeInfo(T).optional.child;
        return numericAsF64(Child, value.?);
    }

    return switch (@typeInfo(T)) {
        .int, .comptime_int => @as(f64, @floatFromInt(value)),
        .float, .comptime_float => @as(f64, @floatCast(value)),
        else => null,
    };
}

fn stringConstraintValue(comptime T: type, raw_value: ?[]const u8, parsed_value: T) ?[]const u8 {
    if (raw_value) |raw| return raw;

    if (@typeInfo(T) == .optional) {
        if (parsed_value == null) return null;
        const Child = @typeInfo(T).optional.child;
        return stringConstraintValue(Child, null, parsed_value.?);
    }

    if (@typeInfo(T) == .pointer) {
        const ptr = @typeInfo(T).pointer;
        if (ptr.size == .slice and ptr.child == u8) return parsed_value;
    }
    return null;
}

fn scalarValueToString(comptime T: type, value: T, out_buf: []u8) ?[]const u8 {
    if (@typeInfo(T) == .optional) {
        if (value == null) return null;
        const Child = @typeInfo(T).optional.child;
        return scalarValueToString(Child, value.?, out_buf);
    }

    return switch (@typeInfo(T)) {
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child == u8) break :blk value;
            break :blk null;
        },
        .bool => std.fmt.bufPrint(out_buf, "{}", .{value}) catch null,
        .int, .comptime_int => std.fmt.bufPrint(out_buf, "{}", .{value}) catch null,
        .float, .comptime_float => std.fmt.bufPrint(out_buf, "{d}", .{value}) catch null,
        else => null,
    };
}

fn stringInList(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

fn patternMatches(value: []const u8, pattern: []const u8) bool {
    if (patternMatchesPosix(value, pattern)) |matched| return matched;
    return patternMatchesLiteral(value, pattern);
}

fn patternMatchesPosix(value: []const u8, pattern: []const u8) ?bool {
    if (pattern.len == 0) return true;

    const pattern_z = std.heap.c_allocator.dupeZ(u8, pattern) catch return null;
    defer std.heap.c_allocator.free(pattern_z);

    var regex: c.regex_t = undefined;
    if (c.regcomp(&regex, pattern_z.ptr, c.REG_EXTENDED) != 0) return null;
    defer c.regfree(&regex);

    const value_z = std.heap.c_allocator.dupeZ(u8, value) catch return null;
    defer std.heap.c_allocator.free(value_z);

    const exec_rc = c.regexec(&regex, value_z.ptr, 0, null, 0);
    if (exec_rc == 0) return true;
    if (exec_rc == c.REG_NOMATCH) return false;
    return null;
}

fn patternMatchesLiteral(value: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return true;

    const anchored_start = pattern[0] == '^';
    const anchored_end = pattern.len > 1 and pattern[pattern.len - 1] == '$';
    const body_start: usize = if (anchored_start) 1 else 0;
    const body_end: usize = if (anchored_end) pattern.len - 1 else pattern.len;
    const body = if (body_start <= body_end) pattern[body_start..body_end] else "";

    if (anchored_start and anchored_end) return std.mem.eql(u8, value, body);
    if (anchored_start) return std.mem.startsWith(u8, value, body);
    if (anchored_end) return std.mem.endsWith(u8, value, body);
    return std.mem.indexOf(u8, value, body) != null;
}

fn isProviderMarkerType(comptime T: type) bool {
    if (!isContainerType(T)) return false;
    return @hasDecl(T, "marker_kind") and @hasDecl(T, "Provider") and @hasField(T, "value");
}

fn isContainerType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => true,
        else => false,
    };
}

fn ensureBodyContentType(req: *Request, expected: []const u8) !void {
    const actual = req.header("content-type") orelse return;
    if (contentTypeMatches(actual, expected)) return;
    try addUnsupportedMediaIssue(req, "body", actual);
    return error.UnsupportedMediaType;
}

fn ensureFormContentType(req: *Request, expected: []const u8) !void {
    const actual = req.header("content-type") orelse return;
    const actual_token = mediaTypeToken(actual);

    if (std.ascii.eqlIgnoreCase(mediaTypeToken(expected), "application/x-www-form-urlencoded")) {
        if (std.ascii.eqlIgnoreCase(actual_token, "application/x-www-form-urlencoded") or
            std.ascii.eqlIgnoreCase(actual_token, "multipart/form-data"))
        {
            return;
        }
    } else if (contentTypeMatches(actual, expected)) {
        return;
    }

    try addUnsupportedMediaIssue(req, "form", actual);
    return error.UnsupportedMediaType;
}

fn ensureFileRequestContentType(req: *Request) !void {
    const actual = req.header("content-type") orelse return;
    if (std.ascii.eqlIgnoreCase(mediaTypeToken(actual), "multipart/form-data")) return;
    try addUnsupportedMediaIssue(req, "file", actual);
    return error.UnsupportedMediaType;
}

fn addUnsupportedMediaIssue(req: *Request, field: []const u8, actual: []const u8) !void {
    try req.addValidationIssue(.{
        .location = .body,
        .field = field,
        .message = "Unsupported media type",
        .issue_type = "unsupported_media_type",
        .input = actual,
    });
}

fn contentTypeMatches(actual: []const u8, expected: []const u8) bool {
    return std.ascii.eqlIgnoreCase(mediaTypeToken(actual), mediaTypeToken(expected));
}

fn mediaTypeToken(raw: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, raw, ';') orelse raw.len;
    return std.mem.trim(u8, raw[0..end], " \t");
}

fn resolveProviderMarker(
    comptime Marker: type,
    req: *Request,
    allocator: std.mem.Allocator,
    context: *ResolveContext,
) anyerror!Marker {
    const use_cache = markerUsesCache(Marker);
    const cache_key = markerRuntimeCacheKey(Marker);
    const cleanup_fn = markerDependsCleanup(Marker);
    const optional_security = markerOptionalSecurity(Marker);

    if (use_cache and cache_key != null) {
        if (try loadCachedMarkerValue(Marker, req, context, cache_key.?)) |cached| {
            var out_cached: Marker = .{};
            out_cached.value = cached;
            return out_cached;
        }
    }

    if (cache_key) |key| {
        if (context.contains(key)) return error.DependencyCycleDetected;
        try context.push(key);
        defer context.pop();
    }

    if (Marker.marker_kind == params.MarkerKind.security and
        @hasDecl(Marker, "required_scopes") and
        Marker.required_scopes.len > 0)
    {
        try security.setRequiredScopes(req, Marker.required_scopes);
    }

    const provider_result = try callProvider(Marker.Provider, req, allocator, context);

    var out: Marker = .{};
    const value_opt: ?Marker.ProviderValueType = provider_result;

    if (Marker.marker_kind == params.MarkerKind.security and value_opt == null) {
        if (optional_security and
            (!@hasDecl(Marker, "required_scopes") or Marker.required_scopes.len == 0))
        {
            out.value = null;
            return out;
        }
        return error.Unauthorized;
    }

    if (Marker.marker_kind == params.MarkerKind.security and
        @hasDecl(Marker, "required_scopes") and
        Marker.required_scopes.len > 0 and
        !security.hasRequiredScopes(req, Marker.required_scopes))
    {
        return error.InsufficientScope;
    }

    out.value = value_opt;

    if (cleanup_fn) |cleanup| {
        if (@hasDecl(Marker, "options") and Marker.options.cache_scope == .request) {
            if (value_opt) |value| {
                if (cacheableProviderValue(Marker.ProviderValueType, value)) |cleanup_value| {
                    const cleanup_key = cache_key orelse @typeName(@TypeOf(Marker.Provider));
                    try req.registerDependencyCleanup(cleanup_key, cleanup_value, cleanup);
                }
            }
        }
    }

    if (use_cache) {
        if (value_opt) |value| {
            if (cacheableProviderValue(Marker.ProviderValueType, value)) |cache_value| {
                if (@hasDecl(Marker, "dependency_name")) {
                    if (Marker.dependency_name) |named| {
                        try req.setDependencyValue(named, cache_value);
                    }
                }
                if (cache_key) |key| {
                    try context.setCached(key, cache_value);
                }
            }
        }
    }

    return out;
}

fn callProvider(
    comptime provider: anytype,
    req: *Request,
    allocator: std.mem.Allocator,
    context: *ResolveContext,
) anyerror!ProviderResultType(provider) {
    const ProviderType = @TypeOf(provider);
    if (@typeInfo(ProviderType) != .@"fn") @compileError("Provider must be a function");

    const fn_info = @typeInfo(ProviderType).@"fn";
    const ArgsTuple = std.meta.ArgsTuple(ProviderType);

    var args: ArgsTuple = undefined;
    inline for (fn_info.params, 0..) |param, idx| {
        const ParamType = param.type orelse @compileError("Provider parameters must have concrete types");
        @field(args, std.fmt.comptimePrint("{d}", .{idx})) = try resolveArg(ParamType, req, allocator, context);
    }

    const call_result = @call(.auto, provider, args);

    const ReturnType = fn_info.return_type orelse @compileError("Provider must return a value");
    if (@typeInfo(ReturnType) == .error_union) {
        return try call_result;
    }
    return call_result;
}

fn markerRuntimeCacheKey(comptime Marker: type) ?[]const u8 {
    if (@hasDecl(Marker, "dependency_name")) {
        if (Marker.dependency_name) |name| return name;
    }
    if (@hasDecl(Marker, "Provider")) return @typeName(@TypeOf(Marker.Provider));
    return null;
}

fn markerUsesCache(comptime Marker: type) bool {
    if (Marker.marker_kind == .depends and @hasDecl(Marker, "options")) {
        return Marker.options.use_cache;
    }
    return true;
}

fn markerOptionalSecurity(comptime Marker: type) bool {
    if (Marker.marker_kind != .security) return false;
    if (@hasDecl(Marker, "optional_security_marker")) return Marker.optional_security_marker;
    return false;
}

fn markerDependsCleanup(comptime Marker: type) ?Request.DependencyCleanupFn {
    if (Marker.marker_kind != .depends) return null;
    if (!@hasDecl(Marker, "options")) return null;
    return Marker.options.cleanup;
}

fn loadCachedMarkerValue(
    comptime Marker: type,
    req: *Request,
    context: *ResolveContext,
    key: []const u8,
) !?Marker.ProviderValueType {
    if (@hasDecl(Marker, "dependency_name")) {
        if (Marker.dependency_name) |name| {
            if (req.dependency(name)) |raw| {
                if (parseCachedProviderValue(Marker.ProviderValueType, raw)) |parsed| return parsed;
            }
        }
    }

    const raw_cached = context.getCached(key) orelse return null;
    return parseCachedProviderValue(Marker.ProviderValueType, raw_cached);
}

fn parseCachedProviderValue(comptime T: type, raw: []const u8) ?T {
    if (@typeInfo(T) == .pointer) {
        const ptr = @typeInfo(T).pointer;
        if (ptr.size == .slice and ptr.child == u8) return raw;
        return null;
    }

    return switch (@typeInfo(T)) {
        .bool => blk: {
            if (std.ascii.eqlIgnoreCase(raw, "true")) break :blk true;
            if (std.ascii.eqlIgnoreCase(raw, "false")) break :blk false;
            break :blk null;
        },
        .int, .comptime_int => std.fmt.parseInt(T, raw, 10) catch null,
        .float, .comptime_float => std.fmt.parseFloat(T, raw) catch null,
        else => null,
    };
}

fn cacheableProviderValue(comptime T: type, value: T) ?[]const u8 {
    if (@typeInfo(T) == .pointer) {
        const ptr = @typeInfo(T).pointer;
        if (ptr.size == .slice and ptr.child == u8) return value;
        return null;
    }
    return null;
}

fn ProviderResultType(comptime provider: anytype) type {
    const ProviderType = @TypeOf(provider);
    const ReturnType = @typeInfo(ProviderType).@"fn".return_type orelse @compileError("Provider must return a value");
    if (@typeInfo(ReturnType) == .error_union) {
        return @typeInfo(ReturnType).error_union.payload;
    }
    return ReturnType;
}

fn countProviderMarkers(comptime HandlerType: type) usize {
    if (@typeInfo(HandlerType) != .@"fn") return 0;
    const fn_info = @typeInfo(HandlerType).@"fn";

    var count: usize = 0;
    inline for (fn_info.params) |param| {
        const ParamType = param.type orelse continue;
        if (isProviderMarkerType(ParamType)) count += 1;
    }
    return count;
}

fn buildProviderSpecs(comptime HandlerType: type) [countProviderMarkers(HandlerType)]types.DependencySpec {
    const fn_info = @typeInfo(HandlerType).@"fn";
    var specs: [countProviderMarkers(HandlerType)]types.DependencySpec = undefined;
    var spec_idx: usize = 0;

    inline for (fn_info.params, 0..) |param, param_idx| {
        const ParamType = param.type orelse continue;
        if (!isProviderMarkerType(ParamType)) continue;
        specs[spec_idx] = providerSpecForMarker(ParamType, param_idx);
        spec_idx += 1;
    }

    return specs;
}

fn providerSpecForMarker(comptime Marker: type, comptime param_index: usize) types.DependencySpec {
    const marker_kind = Marker.marker_kind;
    const optional_security = markerOptionalSecurity(Marker);
    const has_required_scopes = marker_kind == .security and
        @hasDecl(Marker, "required_scopes") and
        Marker.required_scopes.len > 0;

    const name = blk: {
        if (@hasDecl(Marker, "dependency_name")) {
            if (Marker.dependency_name) |declared_name| break :blk declared_name;
        }
        break :blk defaultProviderSpecName(marker_kind, param_index);
    };

    const required = if (marker_kind == .security)
        (!optional_security or has_required_scopes)
    else if (@hasDecl(Marker, "provider_returns_optional"))
        !Marker.provider_returns_optional
    else
        true;

    const use_cache = if (marker_kind == .depends and @hasDecl(Marker, "options"))
        Marker.options.use_cache
    else
        true;

    const cache_scope = if (marker_kind == .depends and @hasDecl(Marker, "options"))
        switch (Marker.options.cache_scope) {
            .request => types.DependencyCacheScope.request,
            .app => types.DependencyCacheScope.app,
        }
    else
        types.DependencyCacheScope.request;

    const depends_on = if (marker_kind == .depends and @hasDecl(Marker, "options"))
        Marker.options.depends_on
    else
        &.{};

    const scopes = if (marker_kind == .security and @hasDecl(Marker, "required_scopes"))
        Marker.required_scopes
    else
        &.{};

    return .{
        .name = name,
        .required = required,
        .use_cache = use_cache,
        .cache_scope = cache_scope,
        .depends_on = depends_on,
        .scopes = scopes,
    };
}

fn defaultProviderSpecName(comptime marker_kind: params.MarkerKind, comptime param_index: usize) []const u8 {
    return switch (marker_kind) {
        .depends => std.fmt.comptimePrint("depends_{d}", .{param_index}),
        .security => std.fmt.comptimePrint("security_{d}", .{param_index}),
    };
}

const SchemaDescriptor = struct {
    schema_type: []const u8 = "string",
    schema_format: ?[]const u8 = null,
    is_array: bool = false,
};

fn countParameterMarkers(comptime HandlerType: type) usize {
    if (@typeInfo(HandlerType) != .@"fn") return 0;
    const fn_info = @typeInfo(HandlerType).@"fn";

    var count: usize = 0;
    inline for (fn_info.params) |param| {
        const ParamType = param.type orelse continue;
        if (!isParamMarkerType(ParamType)) continue;
        if (isParameterLocation(ParamType.Location)) count += 1;
    }
    return count;
}

fn buildParameterSpecs(comptime HandlerType: type) [countParameterMarkers(HandlerType)]types.InjectedParameter {
    const fn_info = @typeInfo(HandlerType).@"fn";
    var specs: [countParameterMarkers(HandlerType)]types.InjectedParameter = undefined;
    var spec_idx: usize = 0;

    inline for (fn_info.params) |param| {
        const ParamType = param.type orelse continue;
        if (!isParamMarkerType(ParamType)) continue;
        if (!isParameterLocation(ParamType.Location)) continue;

        specs[spec_idx] = parameterSpecForMarker(ParamType);
        spec_idx += 1;
    }
    return specs;
}

fn parameterSpecForMarker(comptime Marker: type) types.InjectedParameter {
    const location = Marker.Location;
    const schema = schemaForType(Marker.ValueType);
    const required_from_type = !isOptionalType(Marker.ValueType);

    return .{
        .name = switch (location) {
            .query, .path, .header, .cookie => Marker.options.alias orelse @compileError(
                "Injected marker requires `alias` for OpenAPI parameter generation",
            ),
            else => @compileError("Invalid parameter marker location"),
        },
        .in = switch (location) {
            .query => .query,
            .path => .path,
            .header => .header,
            .cookie => .cookie,
            else => @compileError("Invalid parameter marker location"),
        },
        .required = switch (location) {
            .query => Marker.options.required,
            .path => true,
            .header, .cookie => required_from_type,
            else => true,
        },
        .deprecated = switch (location) {
            .query => Marker.options.deprecated,
            else => false,
        },
        .description = Marker.options.description,
        .schema_type = schema.schema_type,
        .schema_format = schema.schema_format,
        .is_array = schema.is_array,
        .gt = Marker.options.gt,
        .ge = Marker.options.ge,
        .lt = Marker.options.lt,
        .le = Marker.options.le,
        .min_length = Marker.options.min_length,
        .max_length = Marker.options.max_length,
        .pattern = Marker.options.pattern,
        .enum_values = Marker.options.enum_values,
        .strict = Marker.options.strict,
    };
}

fn isParameterLocation(location: params.Location) bool {
    return switch (location) {
        .query, .path, .header, .cookie => true,
        else => false,
    };
}

fn isOptionalType(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

fn countRequestBodyMarkers(comptime HandlerType: type) usize {
    if (@typeInfo(HandlerType) != .@"fn") return 0;
    const fn_info = @typeInfo(HandlerType).@"fn";

    var count: usize = 0;
    inline for (fn_info.params) |param| {
        const ParamType = param.type orelse continue;
        if (!isParamMarkerType(ParamType)) continue;
        if (isRequestBodyLocation(ParamType.Location)) count += 1;
    }
    return count;
}

fn handlerHasFileMarker(comptime HandlerType: type) bool {
    if (@typeInfo(HandlerType) != .@"fn") return false;
    const fn_info = @typeInfo(HandlerType).@"fn";

    inline for (fn_info.params) |param| {
        const ParamType = param.type orelse continue;
        if (!isParamMarkerType(ParamType)) continue;
        if (ParamType.Location == .file) return true;
    }
    return false;
}

fn buildRequestBodySpecs(comptime HandlerType: type) [countRequestBodyMarkers(HandlerType)]types.InjectedRequestBody {
    const fn_info = @typeInfo(HandlerType).@"fn";
    const has_file = comptime handlerHasFileMarker(HandlerType);

    var specs: [countRequestBodyMarkers(HandlerType)]types.InjectedRequestBody = undefined;
    var spec_idx: usize = 0;

    inline for (fn_info.params) |param| {
        const ParamType = param.type orelse continue;
        if (!isParamMarkerType(ParamType)) continue;
        if (!isRequestBodyLocation(ParamType.Location)) continue;

        specs[spec_idx] = requestBodySpecForMarker(ParamType, has_file);
        spec_idx += 1;
    }
    return specs;
}

fn requestBodySpecForMarker(comptime Marker: type, comptime has_file: bool) types.InjectedRequestBody {
    const location = Marker.Location;
    const media_type = switch (location) {
        .body => Marker.options.media_type,
        .form => if (has_file) "multipart/form-data" else Marker.options.media_type,
        .file => "multipart/form-data",
        else => @compileError("Invalid request body marker location"),
    };
    const required = @typeInfo(Marker.ValueType) != .optional;
    const fields = deriveBodyFields(Marker, has_file);

    return .{
        .media_type = media_type,
        .required = required,
        .source = switch (location) {
            .body => .body,
            .form => .form,
            .file => .file,
            else => unreachable,
        },
        .fields = fields,
    };
}

fn isRequestBodyLocation(location: params.Location) bool {
    return switch (location) {
        .body, .form, .file => true,
        else => false,
    };
}

fn deriveBodyFields(comptime Marker: type, comptime has_file: bool) []const types.InjectedBodyField {
    const count = comptime countBodyFields(Marker);
    if (count == 0) return &.{};

    const Holder = struct {
        const fields = buildBodyFields(Marker, has_file);
    };
    return &Holder.fields;
}

fn countBodyFields(comptime Marker: type) usize {
    const location = Marker.Location;
    const ValueType = Marker.ValueType;

    if (location == .file) return 1;
    if (location == .body and Marker.options.embed) return 1;

    const BaseType = stripOptionalType(ValueType);
    if (@typeInfo(BaseType) == .@"struct" and BaseType != Request.UploadFile) {
        return @typeInfo(BaseType).@"struct".fields.len;
    }
    return 1;
}

fn buildBodyFields(comptime Marker: type, comptime has_file: bool) [countBodyFields(Marker)]types.InjectedBodyField {
    _ = has_file;
    const location = Marker.Location;
    const ValueType = Marker.ValueType;
    const BaseType = stripOptionalType(ValueType);
    var out: [countBodyFields(Marker)]types.InjectedBodyField = undefined;

    if (location == .file) {
        const schema = schemaForFileType(ValueType);
        out[0] = .{
            .name = "file",
            .required = !isOptionalType(ValueType),
            .schema_type = schema.schema_type,
            .schema_format = schema.schema_format,
            .is_array = schema.is_array,
            .description = Marker.options.description,
            .min_length = Marker.options.min_length,
            .max_length = Marker.options.max_length,
            .pattern = Marker.options.pattern,
            .enum_values = Marker.options.enum_values,
            .strict = Marker.options.strict,
        };
        return out;
    }

    if (location == .body and Marker.options.embed) {
        const schema = schemaForType(ValueType);
        out[0] = .{
            .name = "body",
            .required = !isOptionalType(ValueType),
            .schema_type = schema.schema_type,
            .schema_format = schema.schema_format,
            .is_array = schema.is_array,
            .description = Marker.options.description,
            .gt = Marker.options.gt,
            .ge = Marker.options.ge,
            .lt = Marker.options.lt,
            .le = Marker.options.le,
            .min_length = Marker.options.min_length,
            .max_length = Marker.options.max_length,
            .pattern = Marker.options.pattern,
            .enum_values = Marker.options.enum_values,
            .strict = Marker.options.strict,
        };
        return out;
    }

    if (@typeInfo(BaseType) == .@"struct" and BaseType != Request.UploadFile) {
        const fields = @typeInfo(BaseType).@"struct".fields;
        inline for (fields, 0..) |field, idx| {
            const schema = schemaForType(field.type);
            out[idx] = .{
                .name = field.name,
                .required = !isOptionalType(field.type) and field.default_value_ptr == null,
                .schema_type = schema.schema_type,
                .schema_format = schema.schema_format,
                .is_array = schema.is_array,
            };
        }
        return out;
    }

    const schema = schemaForType(ValueType);
    out[0] = .{
        .name = if (location == .body and Marker.options.embed) "body" else "value",
        .required = !isOptionalType(ValueType),
        .schema_type = schema.schema_type,
        .schema_format = schema.schema_format,
        .is_array = schema.is_array,
        .description = Marker.options.description,
        .gt = Marker.options.gt,
        .ge = Marker.options.ge,
        .lt = Marker.options.lt,
        .le = Marker.options.le,
        .min_length = Marker.options.min_length,
        .max_length = Marker.options.max_length,
        .pattern = Marker.options.pattern,
        .enum_values = Marker.options.enum_values,
        .strict = Marker.options.strict,
    };
    return out;
}

fn stripOptionalType(comptime T: type) type {
    if (@typeInfo(T) == .optional) {
        return @typeInfo(T).optional.child;
    }
    return T;
}

fn EmbeddedBodyWrapper(comptime ValueType: type) type {
    return if (isOptionalType(ValueType))
        struct { body: ValueType = null }
    else
        struct { body: ValueType };
}

fn schemaForFileType(comptime T: type) SchemaDescriptor {
    const Base = stripOptionalType(T);
    if (@typeInfo(Base) == .pointer) {
        const ptr = @typeInfo(Base).pointer;
        if (ptr.size == .slice and ptr.child == Request.UploadFile) {
            return .{ .schema_type = "string", .schema_format = "binary", .is_array = true };
        }
        if (ptr.size == .slice and ptr.child == u8) {
            return .{ .schema_type = "string", .schema_format = "binary" };
        }
    }
    if (Base == Request.UploadFile) {
        return .{ .schema_type = "string", .schema_format = "binary" };
    }
    return .{ .schema_type = "string", .schema_format = "binary" };
}

fn schemaForType(comptime T: type) SchemaDescriptor {
    const Base = stripOptionalType(T);
    return switch (@typeInfo(Base)) {
        .bool => .{ .schema_type = "boolean" },
        .int => |info| .{
            .schema_type = "integer",
            .schema_format = if (info.bits <= 32) "int32" else "int64",
        },
        .comptime_int => .{
            .schema_type = "integer",
            .schema_format = "int64",
        },
        .float => |info| .{
            .schema_type = "number",
            .schema_format = if (info.bits <= 32) "float" else "double",
        },
        .comptime_float => .{
            .schema_type = "number",
            .schema_format = "double",
        },
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child == u8) break :blk .{ .schema_type = "string" };
            if (ptr.size == .slice) {
                const child_schema = schemaForType(ptr.child);
                break :blk .{
                    .schema_type = child_schema.schema_type,
                    .schema_format = child_schema.schema_format,
                    .is_array = true,
                };
            }
            break :blk .{ .schema_type = "string" };
        },
        .@"struct" => if (Base == Request.UploadFile)
            .{ .schema_type = "string", .schema_format = "binary" }
        else
            .{ .schema_type = "object" },
        else => .{ .schema_type = "string" },
    };
}

fn adaptReturn(comptime HandlerType: type, result: anytype) anyerror!Response {
    const ReturnType = @typeInfo(HandlerType).@"fn".return_type orelse @compileError("Handler must return a value");

    if (@typeInfo(ReturnType) == .error_union) {
        const payload = @typeInfo(ReturnType).error_union.payload;
        if (payload != Response) {
            @compileError("Handler error union payload must be zigmund.Response, got " ++ @typeName(payload));
        }
        return try result;
    }

    if (ReturnType != Response) {
        @compileError("Handler return type must be zigmund.Response or !zigmund.Response");
    }
    return result;
}
