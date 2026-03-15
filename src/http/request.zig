const std = @import("std");
const BackgroundTasks = @import("../core/background.zig").BackgroundTasks;
const state_store = @import("../core/state_store.zig");

pub const Request = struct {
    pub const ValidationLocation = enum {
        query,
        path,
        header,
        cookie,
        body,

        pub fn asString(self: ValidationLocation) []const u8 {
            return switch (self) {
                .query => "query",
                .path => "path",
                .header => "header",
                .cookie => "cookie",
                .body => "body",
            };
        }
    };

    pub const ValidationIssue = struct {
        location: ValidationLocation,
        field: []const u8,
        message: []const u8,
        issue_type: []const u8,
        input: ?[]const u8 = null,
    };

    pub const UploadFile = struct {
        filename: ?[]const u8 = null,
        content_type: ?[]const u8 = null,
        data: []const u8 = "",
    };

    pub const DependencyCleanupFn = *const fn (*Request, []const u8, []const u8, std.mem.Allocator) anyerror!void;
    const DependencyCleanupRunFn = *const fn (*Request, []const u8, ?*anyopaque, std.mem.Allocator) anyerror!void;
    const DependencyCleanupPayloadDeinitFn = *const fn (?*anyopaque, std.mem.Allocator) void;

    const SyntheticHeader = struct {
        name: []u8,
        value: []u8,
    };

    const MultipartPart = struct {
        name: []const u8,
        filename: ?[]const u8 = null,
        content_type: ?[]const u8 = null,
        data: []const u8 = "",
    };

    const ParamModelSource = enum {
        query,
        header,
        cookie,
    };

    const RawDependencyCleanupPayload = struct {
        value: []u8,
        cleanup: DependencyCleanupFn,
    };

    const DependencyCleanup = struct {
        key: []u8,
        payload: ?*anyopaque,
        run: DependencyCleanupRunFn,
        payload_deinit: DependencyCleanupPayloadDeinitFn,
    };

    pub const DependencyOverride = struct {
        resolver: *const fn (*Request, std.mem.Allocator) anyerror!?[]const u8,
        cleanup: ?DependencyCleanupFn = null,
    };

    pub const DependencyOverrideLookupFn = *const fn (?*anyopaque, []const u8) ?DependencyOverride;

    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    raw: ?*std.http.Server.Request = null,
    peer_address: ?std.net.Address = null,
    method: std.http.Method,
    target: []const u8,
    path: []const u8,
    query: []const u8,
    body: []const u8 = "",
    owned_body: ?[]u8 = null,
    request_id: ?[]const u8 = null,
    owned_request_id: ?[]u8 = null,
    request_id_inline: [64]u8 = undefined,
    request_id_inline_len: usize = 0,
    path_params: std.StringHashMapUnmanaged([]const u8) = .empty,
    query_params: std.StringHashMapUnmanaged([]const u8) = .empty,
    synthetic_headers: std.ArrayListUnmanaged(SyntheticHeader) = .empty,
    state: state_store.Store,
    app_state: ?*state_store.Store = null,
    dependency_override_ctx: ?*anyopaque = null,
    dependency_override_lookup: ?DependencyOverrideLookupFn = null,
    dependency_values: std.StringHashMapUnmanaged([]const u8) = .empty,
    dependency_owned_values: std.ArrayListUnmanaged([]u8) = .empty,
    dependency_cleanups: std.ArrayListUnmanaged(DependencyCleanup) = .empty,
    dependency_cleanups_ran: bool = false,
    validation_issues: std.ArrayListUnmanaged(ValidationIssue) = .empty,
    background_tasks: BackgroundTasks,
    background_tasks_ran: bool = false,

    pub const BodyError = error{ BodyTooLarge, BodyReadTimeout } || std.http.Server.Request.ExpectContinueError || std.Io.Reader.LimitedAllocError;

    pub fn initFromRaw(allocator: std.mem.Allocator, raw: *std.http.Server.Request) !Request {
        return initFromRawWithBodyLimit(allocator, raw, 8 * 1024 * 1024);
    }

    pub fn initFromRawWithBodyLimit(
        allocator: std.mem.Allocator,
        raw: *std.http.Server.Request,
        max_body_bytes: usize,
    ) !Request {
        return initFromRawWithBodyLimitAndPeer(allocator, raw, max_body_bytes, null);
    }

    pub fn initFromRawWithBodyLimitAndPeer(
        allocator: std.mem.Allocator,
        raw: *std.http.Server.Request,
        max_body_bytes: usize,
        peer_address: ?std.net.Address,
    ) !Request {
        const split = splitTarget(raw.head.target);
        var req: Request = .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .raw = raw,
            .peer_address = peer_address,
            .method = raw.head.method,
            .target = raw.head.target,
            .path = split.path,
            .query = split.query,
            .body = "",
            .state = state_store.Store.init(allocator),
            .background_tasks = BackgroundTasks.init(allocator),
        };
        errdefer req.deinit();

        try req.storeRawHeaders(raw);
        try req.parseQueryParams();
        try req.readBodyFromRaw(max_body_bytes);
        return req;
    }

    pub fn initSynthetic(
        allocator: std.mem.Allocator,
        method: std.http.Method,
        target: []const u8,
        body: []const u8,
    ) !Request {
        return initSyntheticWithHeaders(allocator, method, target, body, &.{});
    }

    pub fn initSyntheticWithHeaders(
        allocator: std.mem.Allocator,
        method: std.http.Method,
        target: []const u8,
        body: []const u8,
        headers: []const std.http.Header,
    ) !Request {
        const split = splitTarget(target);
        var req: Request = .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .raw = null,
            .method = method,
            .target = target,
            .path = split.path,
            .query = split.query,
            .body = body,
            .state = state_store.Store.init(allocator),
            .background_tasks = BackgroundTasks.init(allocator),
        };
        errdefer req.deinit();

        try req.storeSyntheticHeaders(headers);
        try req.parseQueryParams();
        return req;
    }

    pub fn deinit(self: *Request) void {
        self.state.deinit();
        self.arena.deinit();

        if (self.owned_body) |buf| {
            self.allocator.free(buf);
            self.owned_body = null;
        }
        if (self.owned_request_id) |id| {
            self.allocator.free(id);
            self.owned_request_id = null;
            self.request_id = null;
        }

        for (self.dependency_owned_values.items) |item| {
            self.allocator.free(item);
        }
        self.dependency_owned_values.deinit(self.allocator);
        self.dependency_values.deinit(self.allocator);

        for (self.dependency_cleanups.items) |cleanup| {
            self.allocator.free(cleanup.key);
            cleanup.payload_deinit(cleanup.payload, self.allocator);
        }
        self.dependency_cleanups.deinit(self.allocator);

        self.validation_issues.deinit(self.allocator);
        self.background_tasks.deinit();
        for (self.synthetic_headers.items) |hdr| {
            self.allocator.free(hdr.name);
            self.allocator.free(hdr.value);
        }
        self.synthetic_headers.deinit(self.allocator);

        self.path_params.deinit(self.allocator);
        self.query_params.deinit(self.allocator);
    }

    pub fn setStateBorrowed(self: *Request, key: []const u8, value: anytype) !void {
        try self.state.setBorrowed(key, state_store.Store.erasePointer(value));
    }

    pub fn setStateOwned(self: *Request, key: []const u8, value: anytype, cleanup: anytype) !void {
        try self.state.setOwned(
            key,
            state_store.Store.erasePointer(value),
            state_store.Store.normalizeCleanup(cleanup),
        );
    }

    pub fn removeState(self: *Request, key: []const u8) bool {
        return self.state.remove(key);
    }

    pub fn stateAs(self: *Request, comptime Ptr: type, key: []const u8) ?Ptr {
        return self.state.getAs(Ptr, key);
    }

    pub fn attachAppState(self: *Request, app_state: *state_store.Store) void {
        self.app_state = app_state;
    }

    pub fn appStateAs(self: *Request, comptime Ptr: type, key: []const u8) ?Ptr {
        const store = self.app_state orelse return null;
        return store.getAs(Ptr, key);
    }

    pub fn attachDependencyOverrideLookup(
        self: *Request,
        ctx: ?*anyopaque,
        lookup: ?DependencyOverrideLookupFn,
    ) void {
        self.dependency_override_ctx = ctx;
        self.dependency_override_lookup = lookup;
    }

    pub fn dependencyOverride(self: *const Request, key: []const u8) ?DependencyOverride {
        const lookup = self.dependency_override_lookup orelse return null;
        return lookup(self.dependency_override_ctx, key);
    }

    pub fn header(self: *const Request, name: []const u8) ?[]const u8 {
        for (self.synthetic_headers.items) |hdr| {
            if (std.ascii.eqlIgnoreCase(hdr.name, name)) return hdr.value;
        }
        return null;
    }

    pub fn cookie(self: *const Request, key: []const u8) ?[]const u8 {
        const cookie_header = self.header("cookie") orelse return null;
        var pairs = std.mem.splitScalar(u8, cookie_header, ';');
        while (pairs.next()) |pair| {
            const trimmed = std.mem.trim(u8, pair, " \t");
            if (trimmed.len == 0) continue;
            const eq_idx = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            const name = trimmed[0..eq_idx];
            const value = trimmed[eq_idx + 1 ..];
            if (std.mem.eql(u8, name, key)) return value;
        }
        return null;
    }

    pub fn cookieAs(self: *Request, comptime T: type, key: []const u8) !T {
        return self.resolveTypedValue(T, self.cookie(key), .cookie, key);
    }

    pub fn setPathParam(self: *Request, key: []const u8, value: []const u8) !void {
        try self.path_params.put(self.allocator, key, value);
    }

    pub fn param(self: *const Request, key: []const u8) ?[]const u8 {
        return self.path_params.get(key);
    }

    pub fn queryParam(self: *const Request, key: []const u8) ?[]const u8 {
        return self.query_params.get(key);
    }

    pub fn queryParamsAllLeaky(self: *Request, key: []const u8) ![]const []const u8 {
        var values: std.ArrayList([]const u8) = .empty;
        errdefer values.deinit(self.arena.allocator());

        if (self.query.len == 0) return &.{};

        var pairs = std.mem.splitScalar(u8, self.query, '&');
        while (pairs.next()) |pair| {
            if (pair.len == 0) continue;
            if (std.mem.indexOfScalar(u8, pair, '=')) |idx| {
                const decoded_key = try self.decodeFormComponentLeaky(pair[0..idx]);
                if (!std.mem.eql(u8, decoded_key, key)) continue;
                const decoded_value = try self.decodeFormComponentLeaky(pair[idx + 1 ..]);
                try values.append(self.arena.allocator(), decoded_value);
                continue;
            }

            const decoded_key = try self.decodeFormComponentLeaky(pair);
            if (!std.mem.eql(u8, decoded_key, key)) continue;
            try values.append(self.arena.allocator(), "");
        }

        return values.toOwnedSlice(self.arena.allocator());
    }

    pub fn queryAs(self: *Request, comptime T: type, key: []const u8) !T {
        return self.resolveTypedValue(T, self.queryParam(key), .query, key);
    }

    pub fn paramAs(self: *Request, comptime T: type, key: []const u8) !T {
        return self.resolveTypedValue(T, self.param(key), .path, key);
    }

    pub fn headerAs(self: *Request, comptime T: type, key: []const u8) !T {
        return self.resolveTypedValue(T, self.header(key), .header, key);
    }

    pub fn queryModelAsLeaky(self: *Request, comptime T: type) !T {
        return self.bindParameterModelLeaky(T, .query, false);
    }

    pub fn headerModelAsLeaky(self: *Request, comptime T: type, comptime convert_underscores: bool) !T {
        return self.bindParameterModelLeaky(T, .header, convert_underscores);
    }

    pub fn cookieModelAsLeaky(self: *Request, comptime T: type) !T {
        return self.bindParameterModelLeaky(T, .cookie, false);
    }

    pub fn bodyJson(self: *Request, comptime T: type) !std.json.Parsed(T) {
        return std.json.parseFromSlice(T, self.allocator, self.body, .{}) catch {
            try self.addValidationIssue(.{
                .location = .body,
                .field = "body",
                .message = "Invalid JSON body",
                .issue_type = "json_invalid",
                .input = self.body,
            });
            return error.ValidationFailed;
        };
    }

    pub fn bodyJsonLeaky(self: *Request, comptime T: type) !T {
        return std.json.parseFromSliceLeaky(T, self.arena.allocator(), self.body, .{}) catch {
            try self.addValidationIssue(.{
                .location = .body,
                .field = "body",
                .message = "Invalid JSON body",
                .issue_type = "json_invalid",
                .input = self.body,
            });
            return error.ValidationFailed;
        };
    }

    pub fn formField(self: *Request, key: []const u8) !?[]const u8 {
        if (self.isMultipartFormData()) {
            const parts = try self.multipartPartsLeaky();
            for (parts) |part| {
                if (!std.mem.eql(u8, part.name, key)) continue;
                return part.data;
            }
            return null;
        }

        var pairs = std.mem.splitScalar(u8, self.body, '&');
        while (pairs.next()) |pair| {
            if (pair.len == 0) continue;

            const eq_idx = std.mem.indexOfScalar(u8, pair, '=') orelse {
                const decoded_key = try self.decodeFormComponentLeaky(pair);
                if (std.mem.eql(u8, decoded_key, key)) return "";
                continue;
            };

            const decoded_key = try self.decodeFormComponentLeaky(pair[0..eq_idx]);
            if (!std.mem.eql(u8, decoded_key, key)) continue;

            const value = pair[eq_idx + 1 ..];
            return try self.decodeFormComponentLeaky(value);
        }
        return null;
    }

    pub fn formAsLeaky(self: *Request, comptime T: type) !T {
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                var out: T = undefined;
                inline for (info.fields) |field| {
                    const raw_value = self.formField(field.name) catch {
                        try self.failValidation(.body, field.name, "Invalid form encoding", "form_invalid", self.body);
                        return error.ValidationFailed;
                    };

                    if (raw_value) |raw| {
                        const parsed = parseFormValue(field.type, raw) catch {
                            try self.failValidation(.body, field.name, "Invalid value", "type_error", raw);
                            return error.ValidationFailed;
                        };
                        @field(out, field.name) = parsed;
                    } else {
                        if (field.default_value_ptr) |default_ptr| {
                            const typed_default: *const field.type = @ptrCast(@alignCast(default_ptr));
                            @field(out, field.name) = typed_default.*;
                        } else if (@typeInfo(field.type) == .optional) {
                            @field(out, field.name) = null;
                        } else {
                            try self.failValidation(.body, field.name, "Field required", "missing", null);
                            return error.ValidationFailed;
                        }
                    }
                }
                return out;
            },
            else => {
                const decoded = self.decodeFormComponentLeaky(self.body) catch {
                    try self.failValidation(.body, "body", "Invalid form encoding", "form_invalid", self.body);
                    return error.ValidationFailed;
                };
                return parseFormValue(T, decoded) catch {
                    try self.failValidation(.body, "body", "Invalid value", "type_error", decoded);
                    return error.ValidationFailed;
                };
            },
        }
    }

    pub fn fileAs(self: *Request, comptime T: type) !T {
        return self.fileAsWithMediaType(T, null);
    }

    pub fn fileAsWithMediaType(self: *Request, comptime T: type, expected_file_media: ?[]const u8) !T {
        if (comptime isUploadFileSliceType(T)) {
            if (self.isMultipartFormData()) {
                const parts = try self.resolveAllMultipartFileParts();
                for (parts) |part| try self.validateFileMediaType(expected_file_media, part.content_type);
                return self.coerceUploadFileSliceOutput(T, parts);
            }

            const raw_content_type = self.header("content-type");
            try self.validateFileMediaType(expected_file_media, raw_content_type);
            return self.coerceSingleUploadFileSliceOutput(T, self.body, raw_content_type);
        }

        if (self.isMultipartFormData()) {
            const part = try self.resolveMultipartFilePart();
            try self.validateFileMediaType(expected_file_media, part.content_type);
            return self.coerceFileOutput(T, part.data, part.filename, part.content_type);
        }

        const raw_content_type = self.header("content-type");
        try self.validateFileMediaType(expected_file_media, raw_content_type);
        return self.coerceFileOutput(T, self.body, null, raw_content_type);
    }

    fn validateFileMediaType(self: *Request, expected_file_media: ?[]const u8, actual_media: ?[]const u8) !void {
        const expected = expected_file_media orelse return;
        if (std.ascii.eqlIgnoreCase(expected, "application/octet-stream")) return;

        if (actual_media) |actual| {
            if (contentTypeMatches(actual, expected)) return;
        } else {
            // When no content type is provided, keep backward-compatible behavior.
            return;
        }

        try self.addValidationIssue(.{
            .location = .body,
            .field = "file",
            .message = "Unsupported media type",
            .issue_type = "unsupported_media_type",
            .input = if (actual_media) |actual| actual else "(missing)",
        });
        return error.UnsupportedMediaType;
    }

    fn isUploadFileSliceType(comptime T: type) bool {
        if (@typeInfo(T) != .pointer) return false;
        const ptr = @typeInfo(T).pointer;
        return ptr.size == .slice and ptr.child == UploadFile;
    }

    fn coerceFileOutput(
        self: *Request,
        comptime T: type,
        data: []const u8,
        filename: ?[]const u8,
        content_type: ?[]const u8,
    ) !T {
        switch (@typeInfo(T)) {
            .pointer => |ptr| {
                if (ptr.size != .slice or ptr.child != u8) {
                    try self.addValidationIssue(.{
                        .location = .body,
                        .field = "file",
                        .message = "Unsupported file target type",
                        .issue_type = "type_error",
                    });
                    return error.ValidationFailed;
                }

                if (ptr.is_const) return data;
                return try self.arena.allocator().dupe(u8, data);
            },
            .@"struct" => {
                if (T == UploadFile) {
                    return .{
                        .filename = filename,
                        .content_type = content_type,
                        .data = data,
                    };
                }
                try self.addValidationIssue(.{
                    .location = .body,
                    .field = "file",
                    .message = "Unsupported file target type",
                    .issue_type = "type_error",
                });
                return error.ValidationFailed;
            },
            else => {
                try self.addValidationIssue(.{
                    .location = .body,
                    .field = "file",
                    .message = "Unsupported file target type",
                    .issue_type = "type_error",
                });
                return error.ValidationFailed;
            },
        }
    }

    fn coerceUploadFileSliceOutput(self: *Request, comptime T: type, parts: []const MultipartPart) !T {
        const out = try self.arena.allocator().alloc(UploadFile, parts.len);
        for (parts, 0..) |part, idx| {
            out[idx] = .{
                .filename = part.filename,
                .content_type = part.content_type,
                .data = part.data,
            };
        }
        return out;
    }

    fn coerceSingleUploadFileSliceOutput(
        self: *Request,
        comptime T: type,
        data: []const u8,
        content_type: ?[]const u8,
    ) !T {
        const out = try self.arena.allocator().alloc(UploadFile, 1);
        out[0] = .{
            .filename = null,
            .content_type = content_type,
            .data = data,
        };
        return out;
    }

    pub fn setDependencyValue(self: *Request, key: []const u8, value: []const u8) !void {
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        try self.dependency_owned_values.append(self.allocator, owned_value);
        try self.dependency_values.put(self.allocator, key, owned_value);
    }

    pub fn setDependencyValueBorrowed(self: *Request, key: []const u8, value: []const u8) !void {
        try self.dependency_values.put(self.allocator, key, value);
    }

    pub fn registerDependencyCleanup(
        self: *Request,
        key: []const u8,
        value: []const u8,
        cleanup: DependencyCleanupFn,
    ) !void {
        const payload = try self.allocator.create(RawDependencyCleanupPayload);
        errdefer self.allocator.destroy(payload);

        payload.value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(payload.value);
        payload.cleanup = cleanup;

        try self.registerCleanupEntry(key, payload, runRawDependencyCleanup, deinitRawDependencyCleanupPayload);
    }

    pub fn registerAutoDependencyCleanup(self: *Request, comptime T: type, key: []const u8, value: T) !void {
        if (!comptime supportsAutoDependencyCleanup(T)) {
            @compileError("automatic dependency cleanup requires a zigmund_cleanup, deinit, or close method");
        }

        const Cleanup = struct {
            fn run(req: *Request, cleanup_key: []const u8, payload: ?*anyopaque, allocator: std.mem.Allocator) anyerror!void {
                _ = cleanup_key;
                const typed: *T = @ptrCast(@alignCast(payload orelse return));
                return callAutoDependencyCleanup(T, typed, req, allocator);
            }

            fn deinitPayload(payload: ?*anyopaque, allocator: std.mem.Allocator) void {
                const typed: *T = @ptrCast(@alignCast(payload orelse return));
                allocator.destroy(typed);
            }
        };

        const payload = try self.allocator.create(T);
        errdefer self.allocator.destroy(payload);
        payload.* = value;

        try self.registerCleanupEntry(key, payload, Cleanup.run, Cleanup.deinitPayload);
    }

    pub fn runDependencyCleanups(self: *Request, allocator: std.mem.Allocator) !void {
        if (self.dependency_cleanups_ran) return;
        self.dependency_cleanups_ran = true;

        var first_err: ?anyerror = null;
        var idx = self.dependency_cleanups.items.len;
        while (idx > 0) {
            idx -= 1;
            const cleanup = self.dependency_cleanups.items[idx];
            cleanup.run(self, cleanup.key, cleanup.payload, allocator) catch |err| {
                std.log.debug("dependency cleanup failed for '{s}': {s}", .{ cleanup.key, @errorName(err) });
                if (first_err == null) first_err = err;
            };
        }
        if (first_err) |err| return err;
    }

    fn registerCleanupEntry(
        self: *Request,
        key: []const u8,
        payload: ?*anyopaque,
        run: DependencyCleanupRunFn,
        payload_deinit: DependencyCleanupPayloadDeinitFn,
    ) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);

        try self.dependency_cleanups.append(self.allocator, .{
            .key = owned_key,
            .payload = payload,
            .run = run,
            .payload_deinit = payload_deinit,
        });
    }

    fn runRawDependencyCleanup(
        req: *Request,
        key: []const u8,
        payload: ?*anyopaque,
        allocator: std.mem.Allocator,
    ) anyerror!void {
        const typed: *RawDependencyCleanupPayload = @ptrCast(@alignCast(payload orelse return));
        return typed.cleanup(req, key, typed.value, allocator);
    }

    fn deinitRawDependencyCleanupPayload(payload: ?*anyopaque, allocator: std.mem.Allocator) void {
        const typed: *RawDependencyCleanupPayload = @ptrCast(@alignCast(payload orelse return));
        allocator.free(typed.value);
        allocator.destroy(typed);
    }

    const AutoCleanupCallKind = enum {
        value_only,
        value_with_allocator,
        value_with_request_allocator,
        pointer_only,
        pointer_with_allocator,
        pointer_with_request_allocator,
    };

    const AutoCleanupSpec = struct {
        decl_name: []const u8,
        call_kind: AutoCleanupCallKind,
    };

    pub fn supportsAutoDependencyCleanup(comptime T: type) bool {
        return autoCleanupSpecFor(T, T) != null or
            (autoCleanupPointeeType(T) != null and autoCleanupSpecFor(T, autoCleanupPointeeType(T).?) != null);
    }

    fn callAutoDependencyCleanup(
        comptime T: type,
        value: *T,
        req: *Request,
        allocator: std.mem.Allocator,
    ) anyerror!void {
        if (comptime autoCleanupSpecFor(T, T)) |spec| {
            return invokeAutoCleanup(T, T, value, req, allocator, spec);
        }
        if (comptime autoCleanupPointeeType(T)) |Owner| {
            if (comptime autoCleanupSpecFor(T, Owner)) |spec| {
                return invokeAutoCleanup(T, Owner, value, req, allocator, spec);
            }
        }
        unreachable;
    }

    fn invokeAutoCleanup(
        comptime T: type,
        comptime Owner: type,
        value: *T,
        req: *Request,
        allocator: std.mem.Allocator,
        comptime spec: AutoCleanupSpec,
    ) anyerror!void {
        const cleanup = @field(Owner, spec.decl_name);
        switch (spec.call_kind) {
            .value_only => try finishAutoCleanupCall(@call(.auto, cleanup, .{value.*})),
            .value_with_allocator => try finishAutoCleanupCall(@call(.auto, cleanup, .{ value.*, allocator })),
            .value_with_request_allocator => try finishAutoCleanupCall(@call(.auto, cleanup, .{ value.*, req, allocator })),
            .pointer_only => try finishAutoCleanupCall(@call(.auto, cleanup, .{value})),
            .pointer_with_allocator => try finishAutoCleanupCall(@call(.auto, cleanup, .{ value, allocator })),
            .pointer_with_request_allocator => try finishAutoCleanupCall(@call(.auto, cleanup, .{ value, req, allocator })),
        }
    }

    fn finishAutoCleanupCall(result: anytype) anyerror!void {
        const ResultType = @TypeOf(result);
        if (@typeInfo(ResultType) == .error_union) {
            try result;
            return;
        }
    }

    fn autoCleanupSpecFor(comptime T: type, comptime Owner: type) ?AutoCleanupSpec {
        if (!isAutoCleanupOwnerType(Owner)) return null;

        inline for ([_][]const u8{ "zigmund_cleanup", "deinit", "close" }) |decl_name| {
            if (!@hasDecl(Owner, decl_name)) continue;
            const FnType = @TypeOf(@field(Owner, decl_name));
            if (autoCleanupCallKind(FnType, T)) |call_kind| {
                return .{
                    .decl_name = decl_name,
                    .call_kind = call_kind,
                };
            }
        }
        return null;
    }

    fn autoCleanupCallKind(comptime FnType: type, comptime T: type) ?AutoCleanupCallKind {
        if (@typeInfo(FnType) != .@"fn") return null;
        const info = @typeInfo(FnType).@"fn";
        const ReturnType = info.return_type orelse return null;
        if (!isVoidLikeType(ReturnType)) return null;

        if (info.params.len == 1 and info.params[0].type == T) return .value_only;
        if (info.params.len == 2 and info.params[0].type == T and info.params[1].type == std.mem.Allocator) {
            return .value_with_allocator;
        }
        if (info.params.len == 3 and
            info.params[0].type == T and
            info.params[1].type == *Request and
            info.params[2].type == std.mem.Allocator)
        {
            return .value_with_request_allocator;
        }

        if (isPointerType(T)) return null;

        if (info.params.len == 1 and info.params[0].type == *T) return .pointer_only;
        if (info.params.len == 2 and info.params[0].type == *T and info.params[1].type == std.mem.Allocator) {
            return .pointer_with_allocator;
        }
        if (info.params.len == 3 and
            info.params[0].type == *T and
            info.params[1].type == *Request and
            info.params[2].type == std.mem.Allocator)
        {
            return .pointer_with_request_allocator;
        }
        return null;
    }

    fn autoCleanupPointeeType(comptime T: type) ?type {
        if (@typeInfo(T) != .pointer) return null;
        const child = @typeInfo(T).pointer.child;
        if (!isAutoCleanupOwnerType(child)) return null;
        return child;
    }

    fn isAutoCleanupOwnerType(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .@"struct", .@"union", .@"enum", .@"opaque" => true,
            else => false,
        };
    }

    fn isVoidLikeType(comptime T: type) bool {
        if (T == void) return true;
        if (@typeInfo(T) != .error_union) return false;
        return @typeInfo(T).error_union.payload == void;
    }

    fn isPointerType(comptime T: type) bool {
        return @typeInfo(T) == .pointer;
    }

    pub fn setRequestId(self: *Request, request_id: []const u8) !void {
        const owned = try self.allocator.dupe(u8, request_id);
        errdefer self.allocator.free(owned);

        if (self.owned_request_id) |current| {
            self.allocator.free(current);
        }

        self.owned_request_id = owned;
        self.request_id = owned;
        self.request_id_inline_len = 0;
    }

    pub fn setRequestIdBorrowed(self: *Request, request_id: []const u8) void {
        if (self.owned_request_id) |current| {
            self.allocator.free(current);
            self.owned_request_id = null;
        }
        self.request_id = request_id;
        self.request_id_inline_len = 0;
    }

    pub fn setRequestIdInline(self: *Request, request_id: []const u8) !void {
        if (request_id.len > self.request_id_inline.len) return error.RequestIdTooLong;
        if (self.owned_request_id) |current| {
            self.allocator.free(current);
            self.owned_request_id = null;
        }
        @memcpy(self.request_id_inline[0..request_id.len], request_id);
        self.request_id_inline_len = request_id.len;
        self.request_id = self.request_id_inline[0..request_id.len];
    }

    pub fn requestId(self: *const Request) ?[]const u8 {
        return self.request_id;
    }

    pub fn setPeerAddress(self: *Request, peer_address: std.net.Address) void {
        self.peer_address = peer_address;
    }

    pub fn peerAddress(self: *const Request) ?std.net.Address {
        return self.peer_address;
    }

    pub fn dependency(self: *const Request, key: []const u8) ?[]const u8 {
        return self.dependency_values.get(key);
    }

    pub fn validationIssues(self: *const Request) []const ValidationIssue {
        return self.validation_issues.items;
    }

    pub fn hasValidationIssues(self: *const Request) bool {
        return self.validation_issues.items.len != 0;
    }

    pub fn backgroundTasks(self: *Request) *BackgroundTasks {
        return &self.background_tasks;
    }

    pub fn runBackgroundTasks(self: *Request) !void {
        if (self.background_tasks_ran) return;
        self.background_tasks_ran = true;
        try self.background_tasks.runAll();
    }

    fn splitTarget(target: []const u8) struct { path: []const u8, query: []const u8 } {
        if (std.mem.indexOfScalar(u8, target, '?')) |idx| {
            return .{ .path = target[0..idx], .query = target[idx + 1 ..] };
        }
        return .{ .path = target, .query = "" };
    }

    fn storeHeaderOwned(self: *Request, name: []const u8, value: []const u8) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);
        try self.synthetic_headers.append(self.allocator, .{
            .name = owned_name,
            .value = owned_value,
        });
    }

    fn storeSyntheticHeaders(self: *Request, headers: []const std.http.Header) !void {
        for (headers) |hdr| {
            try self.storeHeaderOwned(hdr.name, hdr.value);
        }
    }

    fn storeRawHeaders(self: *Request, raw: *std.http.Server.Request) !void {
        var it = raw.iterateHeaders();
        while (it.next()) |hdr| {
            try self.storeHeaderOwned(hdr.name, hdr.value);
        }
    }

    fn parseQueryParams(self: *Request) !void {
        if (self.query.len == 0) return;

        var pairs = std.mem.splitScalar(u8, self.query, '&');
        while (pairs.next()) |pair| {
            if (pair.len == 0) continue;
            if (std.mem.indexOfScalar(u8, pair, '=')) |idx| {
                const key = try self.decodeFormComponentLeaky(pair[0..idx]);
                const value = try self.decodeFormComponentLeaky(pair[idx + 1 ..]);
                if (key.len == 0) continue;
                try self.query_params.put(self.allocator, key, value);
            } else {
                const decoded_key = try self.decodeFormComponentLeaky(pair);
                if (decoded_key.len == 0) continue;
                try self.query_params.put(self.allocator, decoded_key, "");
            }
        }
    }

    fn readBodyFromRaw(self: *Request, max_len: usize) BodyError!void {
        const raw = self.raw orelse return;
        if (!raw.head.method.requestHasBody()) return;

        var read_buffer: [8192]u8 = undefined;
        const reader = try raw.readerExpectContinue(&read_buffer);
        const body = reader.allocRemaining(self.allocator, .limited(max_len)) catch |err| switch (err) {
            error.StreamTooLong => return error.BodyTooLarge,
            error.ReadFailed => return error.BodyReadTimeout,
            else => return err,
        };
        self.owned_body = body;
        self.body = body;
    }

    fn isMultipartFormData(self: *const Request) bool {
        const content_type = self.header("content-type") orelse return false;
        return startsWithIgnoreCase(content_type, "multipart/form-data");
    }

    fn resolveMultipartFilePart(self: *Request) !MultipartPart {
        const file_parts = try self.resolveAllMultipartFileParts();
        return file_parts[0];
    }

    fn resolveAllMultipartFileParts(self: *Request) ![]const MultipartPart {
        const parts = self.multipartPartsLeaky() catch {
            try self.addValidationIssue(.{
                .location = .body,
                .field = "file",
                .message = "Invalid multipart body",
                .issue_type = "multipart_invalid",
                .input = self.body,
            });
            return error.ValidationFailed;
        };

        var file_parts: std.ArrayList(MultipartPart) = .empty;
        errdefer file_parts.deinit(self.arena.allocator());

        for (parts) |part| {
            if (part.filename != null) {
                try file_parts.append(self.arena.allocator(), part);
            }
        }

        if (file_parts.items.len == 0) {
            for (parts) |part| {
                if (std.mem.eql(u8, part.name, "file")) {
                    try file_parts.append(self.arena.allocator(), part);
                }
            }
        }

        if (file_parts.items.len != 0) {
            return try file_parts.toOwnedSlice(self.arena.allocator());
        }

        try self.addValidationIssue(.{
            .location = .body,
            .field = "file",
            .message = "Field required",
            .issue_type = "missing",
        });
        return error.ValidationFailed;
    }

    fn multipartPartsLeaky(self: *Request) ![]const MultipartPart {
        const boundary = self.multipartBoundary() orelse return error.MissingMultipartBoundary;
        const boundary_marker = try std.fmt.allocPrint(self.arena.allocator(), "--{s}", .{boundary});
        const part_delimiter = try std.fmt.allocPrint(self.arena.allocator(), "\r\n--{s}", .{boundary});

        if (!std.mem.startsWith(u8, self.body, boundary_marker)) return error.InvalidMultipartBody;

        var cursor: usize = boundary_marker.len;
        var parts: std.ArrayList(MultipartPart) = .empty;
        errdefer parts.deinit(self.arena.allocator());

        while (cursor <= self.body.len) {
            if (std.mem.startsWith(u8, self.body[cursor..], "--")) {
                return try parts.toOwnedSlice(self.arena.allocator());
            }

            if (!std.mem.startsWith(u8, self.body[cursor..], "\r\n")) return error.InvalidMultipartBody;
            cursor += 2;

            const header_end_rel = std.mem.indexOf(u8, self.body[cursor..], "\r\n\r\n") orelse return error.InvalidMultipartBody;
            const header_blob = self.body[cursor .. cursor + header_end_rel];
            cursor += header_end_rel + 4;

            var part = try parseMultipartHeaders(header_blob);
            const body_end_rel = std.mem.indexOf(u8, self.body[cursor..], part_delimiter) orelse return error.InvalidMultipartBody;
            part.data = self.body[cursor .. cursor + body_end_rel];
            try parts.append(self.arena.allocator(), part);

            cursor += body_end_rel + 2;
            if (!std.mem.startsWith(u8, self.body[cursor..], boundary_marker)) return error.InvalidMultipartBody;
            cursor += boundary_marker.len;
        }

        return error.InvalidMultipartBody;
    }

    fn multipartBoundary(self: *const Request) ?[]const u8 {
        const content_type = self.header("content-type") orelse return null;

        var parts = std.mem.splitScalar(u8, content_type, ';');
        const media_type = std.mem.trim(u8, parts.next() orelse return null, " \t");
        if (!std.ascii.eqlIgnoreCase(media_type, "multipart/form-data")) return null;

        while (parts.next()) |segment| {
            const parameter = std.mem.trim(u8, segment, " \t");
            const eq_idx = std.mem.indexOfScalar(u8, parameter, '=') orelse continue;

            const key = std.mem.trim(u8, parameter[0..eq_idx], " \t");
            if (!std.ascii.eqlIgnoreCase(key, "boundary")) continue;

            var value = std.mem.trim(u8, parameter[eq_idx + 1 ..], " \t");
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }
            if (value.len == 0) return null;
            return value;
        }

        return null;
    }

    fn parseMultipartHeaders(headers: []const u8) !MultipartPart {
        var part: MultipartPart = .{ .name = "" };

        var lines = std.mem.splitSequence(u8, headers, "\r\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const colon_idx = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const header_name = std.mem.trim(u8, line[0..colon_idx], " \t");
            const header_value = std.mem.trim(u8, line[colon_idx + 1 ..], " \t");

            if (std.ascii.eqlIgnoreCase(header_name, "content-disposition")) {
                try parseContentDispositionHeader(header_value, &part);
            } else if (std.ascii.eqlIgnoreCase(header_name, "content-type")) {
                part.content_type = header_value;
            }
        }

        if (part.name.len == 0) return error.MultipartMissingName;
        return part;
    }

    fn parseContentDispositionHeader(value: []const u8, part: *MultipartPart) !void {
        var tokens = std.mem.splitScalar(u8, value, ';');
        const kind = std.mem.trim(u8, tokens.next() orelse return error.InvalidMultipartDisposition, " \t");
        if (!std.ascii.eqlIgnoreCase(kind, "form-data")) return error.InvalidMultipartDisposition;

        while (tokens.next()) |token| {
            const attr = std.mem.trim(u8, token, " \t");
            if (attr.len == 0) continue;

            const eq_idx = std.mem.indexOfScalar(u8, attr, '=') orelse continue;
            const key = std.mem.trim(u8, attr[0..eq_idx], " \t");
            var attr_value = std.mem.trim(u8, attr[eq_idx + 1 ..], " \t");
            if (attr_value.len >= 2 and attr_value[0] == '"' and attr_value[attr_value.len - 1] == '"') {
                attr_value = attr_value[1 .. attr_value.len - 1];
            }

            if (std.ascii.eqlIgnoreCase(key, "name")) {
                part.name = attr_value;
            } else if (std.ascii.eqlIgnoreCase(key, "filename")) {
                part.filename = attr_value;
            }
        }
    }

    fn startsWithIgnoreCase(value: []const u8, prefix: []const u8) bool {
        if (value.len < prefix.len) return false;
        return std.ascii.eqlIgnoreCase(value[0..prefix.len], prefix);
    }

    fn contentTypeMatches(actual: []const u8, expected: []const u8) bool {
        return std.ascii.eqlIgnoreCase(mediaTypeToken(actual), mediaTypeToken(expected));
    }

    fn mediaTypeToken(raw: []const u8) []const u8 {
        const end = std.mem.indexOfScalar(u8, raw, ';') orelse raw.len;
        return std.mem.trim(u8, raw[0..end], " \t");
    }

    fn parseScalar(comptime T: type, input: []const u8) !T {
        if (T == std.Uri) return std.Uri.parse(input);
        if (T == std.net.Address) return std.net.Address.parseIp(input, 0);
        if (T == std.net.Ip4Address) return std.net.Ip4Address.parse(input, 0);
        if (T == std.net.Ip6Address) return std.net.Ip6Address.parse(input, 0);

        switch (@typeInfo(T)) {
            .optional => |opt| return try parseScalar(opt.child, input),
            .int => return std.fmt.parseInt(T, input, 10),
            .comptime_int => return std.fmt.parseInt(T, input, 10),
            .float => return std.fmt.parseFloat(T, input),
            .comptime_float => return std.fmt.parseFloat(T, input),
            .bool => {
                if (std.ascii.eqlIgnoreCase(input, "true") or std.mem.eql(u8, input, "1")) return true;
                if (std.ascii.eqlIgnoreCase(input, "false") or std.mem.eql(u8, input, "0")) return false;
                return error.InvalidBoolean;
            },
            .pointer => |info| {
                if (info.size == .slice and info.child == u8) return input;
                return error.UnsupportedType;
            },
            else => return error.UnsupportedType,
        }
    }

    fn parseFormValue(comptime T: type, raw: []const u8) !T {
        if (@typeInfo(T) == .optional) {
            const Child = @typeInfo(T).optional.child;
            if (raw.len == 0) return null;
            return try parseScalar(Child, raw);
        }
        return parseScalar(T, raw);
    }

    fn bindParameterModelLeaky(
        self: *Request,
        comptime T: type,
        comptime source: ParamModelSource,
        comptime convert_underscores: bool,
    ) !T {
        const Base = stripOptionalType(T);
        if (@typeInfo(Base) != .@"struct") return error.UnsupportedType;

        var out: Base = undefined;
        inline for (@typeInfo(Base).@"struct".fields) |field| {
            const key = parameterModelFieldName(Base, source, field.name, convert_underscores);

            if (comptime source == .query and isRepeatedQueryFieldType(field.type)) {
                const raw_values = try self.queryParamsAllLeaky(key);
                if (raw_values.len == 0) {
                    try self.assignMissingParameterModelField(Base, field, &out, source, key);
                } else {
                    @field(out, field.name) = try self.parseRepeatedQueryField(field.type, key, raw_values);
                }
            } else {
                const raw_value = switch (source) {
                    .query => self.queryParam(key),
                    .header => self.header(key),
                    .cookie => self.cookie(key),
                };

                if (raw_value) |raw| {
                    const parsed = parseScalar(field.type, raw) catch {
                        try self.failValidation(validationLocationForModelSource(source), key, "Invalid value", "type_error", raw);
                        return error.ValidationFailed;
                    };
                    @field(out, field.name) = parsed;
                } else {
                    try self.assignMissingParameterModelField(Base, field, &out, source, key);
                }
            }
        }

        return out;
    }

    fn parseRepeatedQueryField(
        self: *Request,
        comptime T: type,
        key: []const u8,
        raw_values: []const []const u8,
    ) !T {
        const SliceType = stripOptionalType(T);
        const ptr = @typeInfo(SliceType).pointer;
        const Child = ptr.child;

        const out = try self.arena.allocator().alloc(Child, raw_values.len);
        for (raw_values, 0..) |raw, idx| {
            out[idx] = parseScalar(Child, raw) catch {
                try self.failValidation(.query, key, "Invalid value", "type_error", raw);
                return error.ValidationFailed;
            };
        }
        return out;
    }

    fn assignMissingParameterModelField(
        self: *Request,
        comptime Base: type,
        comptime field: std.builtin.Type.StructField,
        out: *Base,
        comptime source: ParamModelSource,
        key: []const u8,
    ) !void {
        if (field.default_value_ptr) |default_ptr| {
            const typed_default: *const field.type = @ptrCast(@alignCast(default_ptr));
            @field(out.*, field.name) = typed_default.*;
            return;
        }
        if (@typeInfo(field.type) == .optional) {
            @field(out.*, field.name) = null;
            return;
        }
        try self.failValidation(validationLocationForModelSource(source), key, "Field required", "missing", null);
        return error.ValidationFailed;
    }

    fn validationLocationForModelSource(source: ParamModelSource) ValidationLocation {
        return switch (source) {
            .query => .query,
            .header => .header,
            .cookie => .cookie,
        };
    }

    fn parameterModelFieldName(
        comptime Model: type,
        comptime source: ParamModelSource,
        comptime field_name: []const u8,
        comptime convert_underscores: bool,
    ) []const u8 {
        if (parameterModelFieldAlias(Model, source, field_name)) |alias| return alias;
        if (source != .header or !convert_underscores) return field_name;

        const Holder = struct {
            fn build() [field_name.len]u8 {
                var out: [field_name.len]u8 = undefined;
                inline for (field_name, 0..) |ch, idx| {
                    out[idx] = if (ch == '_') '-' else ch;
                }
                return out;
            }

            const value = build();
        };
        return Holder.value[0..];
    }

    fn parameterModelFieldAlias(
        comptime Model: type,
        comptime source: ParamModelSource,
        comptime field_name: []const u8,
    ) ?[]const u8 {
        const decl_name = switch (source) {
            .query => "zigmund_query_aliases",
            .header => "zigmund_header_aliases",
            .cookie => "zigmund_cookie_aliases",
        };
        if (!@hasDecl(Model, decl_name)) return null;

        const raw = @field(Model, decl_name);
        const RawType = @TypeOf(raw);
        switch (@typeInfo(RawType)) {
            .pointer => |ptr| {
                if (ptr.size == .slice) {
                    inline for (raw) |entry| {
                        validateParameterModelAliasEntry(@TypeOf(entry));
                        if (std.mem.eql(u8, entry.field, field_name)) return entry.alias;
                    }
                } else if (@typeInfo(ptr.child) == .array) {
                    inline for (raw.*) |entry| {
                        validateParameterModelAliasEntry(@TypeOf(entry));
                        if (std.mem.eql(u8, entry.field, field_name)) return entry.alias;
                    }
                } else if (ptr.size == .one and @typeInfo(ptr.child) == .@"struct") {
                    const entry = raw.*;
                    validateParameterModelAliasEntry(@TypeOf(entry));
                    if (std.mem.eql(u8, entry.field, field_name)) return entry.alias;
                } else {
                    @compileError("parameter model aliases must be slices, arrays, or pointers to alias entries");
                }
            },
            .array => {
                inline for (raw[0..]) |entry| {
                    validateParameterModelAliasEntry(@TypeOf(entry));
                    if (std.mem.eql(u8, entry.field, field_name)) return entry.alias;
                }
            },
            else => @compileError("parameter model aliases must be a slice or array"),
        }
        return null;
    }

    fn validateParameterModelAliasEntry(comptime EntryType: type) void {
        if (@typeInfo(EntryType) != .@"struct") {
            @compileError("parameter model alias entries must be structs with `field` and `alias`");
        }
        if (!@hasField(EntryType, "field") or !@hasField(EntryType, "alias")) {
            @compileError("parameter model alias entries must define `field` and `alias`");
        }
        if (@FieldType(EntryType, "field") != []const u8 or @FieldType(EntryType, "alias") != []const u8) {
            @compileError("parameter model alias entry fields must be []const u8");
        }
    }

    fn isRepeatedQueryFieldType(comptime T: type) bool {
        const Base = stripOptionalType(T);
        if (@typeInfo(Base) != .pointer) return false;
        const ptr = @typeInfo(Base).pointer;
        return ptr.size == .slice and ptr.child != u8;
    }

    fn stripOptionalType(comptime T: type) type {
        if (@typeInfo(T) == .optional) {
            return @typeInfo(T).optional.child;
        }
        return T;
    }

    fn decodeFormComponentLeaky(self: *Request, input: []const u8) ![]const u8 {
        if (std.mem.indexOfScalar(u8, input, '+') == null and std.mem.indexOfScalar(u8, input, '%') == null) {
            return input;
        }

        const out = try self.arena.allocator().alloc(u8, input.len);
        var in_idx: usize = 0;
        var out_idx: usize = 0;
        while (in_idx < input.len) : (in_idx += 1) {
            const ch = input[in_idx];
            switch (ch) {
                '+' => {
                    out[out_idx] = ' ';
                    out_idx += 1;
                },
                '%' => {
                    if (in_idx + 2 >= input.len) return error.InvalidPercentEncoding;
                    const hi = hexNibble(input[in_idx + 1]) orelse return error.InvalidPercentEncoding;
                    const lo = hexNibble(input[in_idx + 2]) orelse return error.InvalidPercentEncoding;
                    out[out_idx] = (hi << 4) | lo;
                    out_idx += 1;
                    in_idx += 2;
                },
                else => {
                    out[out_idx] = ch;
                    out_idx += 1;
                },
            }
        }
        return out[0..out_idx];
    }

    fn hexNibble(ch: u8) ?u8 {
        return switch (ch) {
            '0'...'9' => ch - '0',
            'a'...'f' => ch - 'a' + 10,
            'A'...'F' => ch - 'A' + 10,
            else => null,
        };
    }

    pub fn addValidationIssue(self: *Request, issue: ValidationIssue) !void {
        try self.validation_issues.append(self.allocator, issue);
    }

    /// Helper to add a validation issue. Used by formAsLeaky to reduce
    /// the repeated addValidationIssue + return error.ValidationFailed pattern.
    fn failValidation(
        self: *Request,
        comptime location: ValidationLocation,
        field: []const u8,
        message: []const u8,
        issue_type: []const u8,
        input: ?[]const u8,
    ) !void {
        try self.addValidationIssue(.{
            .location = location,
            .field = field,
            .message = message,
            .issue_type = issue_type,
            .input = input,
        });
    }

    /// Generic helper that eliminates duplication across cookieAs, queryAs,
    /// paramAs, and headerAs. Resolves a raw string value into a typed T,
    /// recording a validation issue when the key is missing or unparseable.
    fn resolveTypedValue(
        self: *Request,
        comptime T: type,
        raw_value: ?[]const u8,
        comptime location: ValidationLocation,
        field: []const u8,
    ) !T {
        const raw = raw_value orelse {
            if (@typeInfo(T) == .optional) return null;
            try self.addValidationIssue(.{
                .location = location,
                .field = field,
                .message = "Field required",
                .issue_type = "missing",
            });
            return error.ValidationFailed;
        };

        return parseScalar(T, raw) catch {
            try self.addValidationIssue(.{
                .location = location,
                .field = field,
                .message = "Invalid value",
                .issue_type = "type_error",
                .input = raw,
            });
            return error.ValidationFailed;
        };
    }
};

test "query parsing" {
    var req = try Request.initSynthetic(std.testing.allocator, .GET, "/items?page=1&size=20", "");
    defer req.deinit();

    try std.testing.expectEqualStrings("1", req.queryParam("page").?);
    try std.testing.expectEqualStrings("20", req.queryParam("size").?);
}

test "typed query parsing" {
    var req = try Request.initSynthetic(std.testing.allocator, .GET, "/items?page=2&active=true", "");
    defer req.deinit();

    try std.testing.expectEqual(@as(i64, 2), try req.queryAs(i64, "page"));
    try std.testing.expectEqual(true, try req.queryAs(bool, "active"));
}
