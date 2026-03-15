const std = @import("std");

pub const DocsTheme = enum {
    light,
    dark,
};

pub const SwaggerDocExpansion = enum {
    list,
    full,
    none,
};

pub const SwaggerUiConfig = struct {
    title: ?[]const u8 = null,
    persist_authorization: bool = false,
    deep_linking: bool = true,
    display_operation_id: bool = false,
    doc_expansion: SwaggerDocExpansion = .list,
    theme: DocsTheme = .light,
};

pub const RedocUiConfig = struct {
    title: ?[]const u8 = null,
    hide_download_button: bool = false,
    disable_search: bool = false,
    theme: DocsTheme = .light,
};

pub const OpenApiContact = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    email: ?[]const u8 = null,
};

pub const OpenApiLicense = struct {
    name: []const u8,
    identifier: ?[]const u8 = null,
    url: ?[]const u8 = null,
};

pub const AppConfig = struct {
    title: []const u8,
    version: []const u8,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    terms_of_service: ?[]const u8 = null,
    contact: ?OpenApiContact = null,
    license_info: ?OpenApiLicense = null,
    root_path: ?[]const u8 = null,
    openapi_url: ?[]const u8 = "/openapi.json",
    docs_url: ?[]const u8 = "/docs",
    redoc_url: ?[]const u8 = "/redoc",
    metrics_url: ?[]const u8 = null,
    redirect_slashes: bool = true,
    request_id_enabled: bool = true,
    request_id_header: []const u8 = "x-request-id",
    docs: SwaggerUiConfig = .{},
    redoc: RedocUiConfig = .{},
    servers: []const []const u8 = &.{},
    strict_validation: bool = false,
    json_schema_dialect: ?[]const u8 = "https://json-schema.org/draft/2020-12/schema",
    structured_access_logs: bool = false,
    structured_telemetry_logs: bool = false,
    structured_trace_logs: bool = false,
    structured_metrics_logs: bool = false,
    structured_audit_logs: bool = false,
    structured_log_redaction_text: []const u8 = "[redacted]",
    structured_log_redact_tracestate: bool = true,
    structured_log_redact_baggage: bool = true,
    structured_log_redact_remote_addr: bool = true,
    structured_log_redact_user_agent: bool = true,
    openapi_deterministic: bool = false,
    openapi_extensions: []const OpenApiExtension = &.{},
    webhooks: []const OpenApiWebhook = &.{},
};

pub const DependencySpec = struct {
    name: []const u8,
    required: bool = true,
    use_cache: bool = true,
    cache_scope: DependencyCacheScope = .request,
    depends_on: []const []const u8 = &.{},
    scopes: []const []const u8 = &.{},
};

pub const DependencyCacheScope = enum {
    request,
    app,
};

pub const InjectedRequestBody = struct {
    media_type: []const u8,
    required: bool = true,
    source: enum {
        body,
        form,
        file,
    },
    fields: []const InjectedBodyField = &.{},
};

/// NOTE: Constraint fields (gt, ge, lt, le, min_length, max_length, pattern, enum_values, strict)
/// are shared with InjectedParameter -- see audit #41.
pub const InjectedBodyField = struct {
    name: []const u8,
    required: bool = true,
    schema_type: []const u8 = "string",
    schema_format: ?[]const u8 = null,
    is_array: bool = false,
    description: ?[]const u8 = null,
    gt: ?f64 = null,
    ge: ?f64 = null,
    lt: ?f64 = null,
    le: ?f64 = null,
    min_length: ?usize = null,
    max_length: ?usize = null,
    pattern: ?[]const u8 = null,
    enum_values: []const []const u8 = &.{},
    strict: bool = false,
};

pub const InjectedParameterIn = enum {
    query,
    path,
    header,
    cookie,

    pub fn asString(self: InjectedParameterIn) []const u8 {
        return switch (self) {
            .query => "query",
            .path => "path",
            .header => "header",
            .cookie => "cookie",
        };
    }
};

/// NOTE: Constraint fields (gt, ge, lt, le, min_length, max_length, pattern, enum_values, strict)
/// are shared with InjectedBodyField -- see audit #41.
pub const InjectedParameter = struct {
    name: []const u8,
    in: InjectedParameterIn,
    required: bool = true,
    deprecated: bool = false,
    description: ?[]const u8 = null,
    schema_type: []const u8 = "string",
    schema_format: ?[]const u8 = null,
    is_array: bool = false,
    gt: ?f64 = null,
    ge: ?f64 = null,
    lt: ?f64 = null,
    le: ?f64 = null,
    min_length: ?usize = null,
    max_length: ?usize = null,
    pattern: ?[]const u8 = null,
    enum_values: []const []const u8 = &.{},
    strict: bool = false,
};

pub const OpenApiSchemaField = struct {
    name: []const u8,
    required: bool = true,
    schema_type: []const u8 = "string",
    schema_format: ?[]const u8 = null,
    is_array: bool = false,
    fields: []const OpenApiSchemaField = &.{},
};

pub const OpenApiSchema = struct {
    schema_type: []const u8 = "string",
    schema_format: ?[]const u8 = null,
    is_array: bool = false,
    fields: []const OpenApiSchemaField = &.{},
    one_of: []const OpenApiSchema = &.{},
    any_of: []const OpenApiSchema = &.{},
    all_of: []const OpenApiSchema = &.{},
    discriminator_property_name: ?[]const u8 = null,
    discriminator_mapping: []const OpenApiDiscriminatorMapping = &.{},
};

pub const OpenApiDiscriminatorMapping = struct {
    value: []const u8,
    schema_ref: []const u8,
};

pub const OpenApiExample = struct {
    name: []const u8,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    value_json: []const u8,
};

pub const OpenApiExtension = struct {
    key: []const u8,
    value_json: []const u8,
};

pub const OpenApiSecurityRequirement = struct {
    scheme: []const u8,
    scopes: []const []const u8 = &.{},
};

pub const OpenApiSecurityAlternative = struct {
    requirements: []const OpenApiSecurityRequirement = &.{},
};

pub const OpenApiResponseExamples = struct {
    status_code: std.http.Status,
    content_type: []const u8 = "application/json",
    examples: []const OpenApiExample = &.{},
};

/// NOTE: Shares most fields with OpenApiWebhook -- see audit #40.
pub const OpenApiCallback = struct {
    name: []const u8,
    expression: []const u8,
    method: RouteMethod = .POST,
    operation_id: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    request_body_required: bool = true,
    request_body_content_type: []const u8 = "application/json",
    request_body_schema: ?OpenApiSchema = null,
    response_status: std.http.Status = .ok,
    response_description: ?[]const u8 = null,
    response_content_type: []const u8 = "application/json",
    response_schema: ?OpenApiSchema = null,
    tags: []const []const u8 = &.{},
};

/// NOTE: Shares most fields with OpenApiCallback -- see audit #40.
pub const OpenApiWebhook = struct {
    name: []const u8,
    method: RouteMethod = .POST,
    operation_id: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    request_body_required: bool = true,
    request_body_content_type: []const u8 = "application/json",
    request_body_schema: ?OpenApiSchema = null,
    response_status: std.http.Status = .ok,
    response_description: ?[]const u8 = null,
    response_content_type: []const u8 = "application/json",
    response_schema: ?OpenApiSchema = null,
    tags: []const []const u8 = &.{},
};

pub const ResponseSpec = struct {
    status_code: std.http.Status,
    description: ?[]const u8 = null,
    content_type: ?[]const u8 = null,
};

pub const ResponseModelAlias = struct {
    path: []const u8,
    alias: []const u8,
};

pub const ResponseModelDefaultValue = union(enum) {
    none,
    null,
    bool: bool,
    integer: i64,
    float: f64,
    string: []const u8,
};

pub const ResponseModelFieldRule = struct {
    path: []const u8,
    alias: ?[]const u8 = null,
    default_value: ResponseModelDefaultValue = .none,
};

pub const ResponseModelTransformFn = *const fn (*std.json.Value, std.mem.Allocator) anyerror!void;
pub const ResponseModelValidateFn = *const fn (*const std.json.Value, std.mem.Allocator) anyerror!void;

pub const RouteOptions = struct {
    name: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    status_code: ?std.http.Status = null,
    include_in_schema: bool = true,
    response_model: ?type = null,
    openapi_response_schema: ?OpenApiSchema = null,
    response_model_include: []const []const u8 = &.{},
    response_model_exclude: []const []const u8 = &.{},
    response_model_by_alias: bool = true,
    response_model_exclude_unset: bool = false,
    response_model_exclude_defaults: bool = false,
    response_model_exclude_none: bool = false,
    openapi_request_examples: []const OpenApiExample = &.{},
    openapi_response_examples: []const OpenApiResponseExamples = &.{},
    openapi_callbacks: []const OpenApiCallback = &.{},
    openapi_extensions: []const OpenApiExtension = &.{},
    openapi_security: []const OpenApiSecurityAlternative = &.{},
    strict_validation: ?bool = null,
    max_header_bytes: ?usize = null,
    max_query_bytes: ?usize = null,
    max_body_bytes: ?usize = null,
    dependencies: []const DependencySpec = &.{},
    responses: []const ResponseSpec = &.{},
    deprecated: bool = false,
    operation_id: ?[]const u8 = null,
    default_response_class: ?[]const u8 = null,
};

/// Stored version of RouteOptions with owned copies of string data.
/// NOTE: Many fields are shared with RouteOptions -- see docs/audit-2026-02-27.md #39.
/// A future refactoring could embed a shared base struct to reduce duplication.
pub const StoredRouteOptions = struct {
    name: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    status_code: ?std.http.Status = null,
    include_in_schema: bool = true,
    response_model_name: ?[]const u8 = null,
    response_model_schema: ?OpenApiSchema = null,
    openapi_request_examples: []const OpenApiExample = &.{},
    openapi_response_examples: []const OpenApiResponseExamples = &.{},
    openapi_callbacks: []const OpenApiCallback = &.{},
    openapi_extensions: []const OpenApiExtension = &.{},
    openapi_security: []const OpenApiSecurityAlternative = &.{},
    response_model_field_rules: []const ResponseModelFieldRule = &.{},
    response_model_transform: ?ResponseModelTransformFn = null,
    response_model_validate: ?ResponseModelValidateFn = null,
    response_model_include: []const []const u8 = &.{},
    response_model_exclude: []const []const u8 = &.{},
    response_model_by_alias: bool = true,
    response_model_exclude_unset: bool = false,
    response_model_exclude_defaults: bool = false,
    response_model_exclude_none: bool = false,
    strict_validation: ?bool = null,
    max_header_bytes: ?usize = null,
    max_query_bytes: ?usize = null,
    max_body_bytes: ?usize = null,
    dependencies: []const DependencySpec = &.{},
    injected_dependencies: []const DependencySpec = &.{},
    injected_parameters: []const InjectedParameter = &.{},
    injected_request_bodies: []const InjectedRequestBody = &.{},
    responses: []const ResponseSpec = &.{},
    deprecated: bool = false,
    operation_id: ?[]const u8 = null,
    default_response_class: ?[]const u8 = null,
};

pub fn storeRouteOptions(opts: RouteOptions) StoredRouteOptions {
    return .{
        .name = opts.name,
        .summary = opts.summary,
        .description = opts.description,
        .tags = opts.tags,
        .status_code = opts.status_code,
        .include_in_schema = opts.include_in_schema,
        .response_model_name = if (opts.response_model) |T| @typeName(T) else null,
        .response_model_schema = opts.openapi_response_schema orelse
            (if (opts.response_model) |T| deriveOpenApiSchema(T) else null),
        .openapi_request_examples = opts.openapi_request_examples,
        .openapi_response_examples = opts.openapi_response_examples,
        .openapi_callbacks = opts.openapi_callbacks,
        .openapi_extensions = opts.openapi_extensions,
        .openapi_security = opts.openapi_security,
        .response_model_field_rules = if (opts.response_model) |T| deriveResponseModelFieldRules(T) else &.{},
        .response_model_transform = if (opts.response_model) |T| deriveResponseModelTransformFn(T) else null,
        .response_model_validate = if (opts.response_model) |T| deriveResponseModelValidateFn(T) else null,
        .response_model_include = opts.response_model_include,
        .response_model_exclude = opts.response_model_exclude,
        .response_model_by_alias = opts.response_model_by_alias,
        .response_model_exclude_unset = opts.response_model_exclude_unset,
        .response_model_exclude_defaults = opts.response_model_exclude_defaults,
        .response_model_exclude_none = opts.response_model_exclude_none,
        .strict_validation = opts.strict_validation,
        .max_header_bytes = opts.max_header_bytes,
        .max_query_bytes = opts.max_query_bytes,
        .max_body_bytes = opts.max_body_bytes,
        .dependencies = opts.dependencies,
        .injected_dependencies = &.{},
        .injected_parameters = &.{},
        .injected_request_bodies = &.{},
        .responses = opts.responses,
        .deprecated = opts.deprecated,
        .operation_id = opts.operation_id,
        .default_response_class = opts.default_response_class,
    };
}

pub const WebSocketRouteOptions = struct {
    name: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    idle_timeout_ms: ?u64 = null,
    auto_pong: bool = true,
    ping_interval_ms: ?u64 = null,
    pong_timeout_ms: ?u64 = null,
    max_message_bytes: ?usize = null,
    max_pending_messages: ?usize = null,
    send_timeout_ms: ?u64 = null,
    allowed_origins: []const []const u8 = &.{},
    subprotocols: []const []const u8 = &.{},
    require_subprotocol: bool = false,
    dependencies: []const DependencySpec = &.{},
    openapi_security: []const OpenApiSecurityAlternative = &.{},
    deprecated: bool = false,
    operation_id: ?[]const u8 = null,
    openapi_extensions: []const OpenApiExtension = &.{},
};

pub const IncludeRouterOptions = struct {
    tags: []const []const u8 = &.{},
    dependencies: []const DependencySpec = &.{},
    default_response_class: ?[]const u8 = null,
    include_in_schema: bool = true,
};

fn deriveOpenApiSchema(comptime T: type) OpenApiSchema {
    const Base = stripOptionalType(T);
    if (Base == std.Uri) {
        return .{
            .schema_type = "string",
            .schema_format = "uri",
        };
    }
    if (Base == std.net.Ip4Address) {
        return .{
            .schema_type = "string",
            .schema_format = "ipv4",
        };
    }
    if (Base == std.net.Ip6Address) {
        return .{
            .schema_type = "string",
            .schema_format = "ipv6",
        };
    }
    if (Base == std.net.Address) {
        return .{ .schema_type = "string" };
    }

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
                const child_schema = deriveOpenApiSchema(ptr.child);
                break :blk .{
                    .schema_type = child_schema.schema_type,
                    .schema_format = child_schema.schema_format,
                    .is_array = true,
                    .fields = child_schema.fields,
                };
            }
            break :blk .{ .schema_type = "string" };
        },
        .@"struct" => .{
            .schema_type = "object",
            .fields = deriveSchemaFields(Base),
        },
        else => .{ .schema_type = "string" },
    };
}

fn deriveSchemaFields(comptime T: type) []const OpenApiSchemaField {
    if (@typeInfo(T) != .@"struct") return &.{};
    const field_count = @typeInfo(T).@"struct".fields.len;
    if (field_count == 0) return &.{};

    const Holder = struct {
        const items = buildSchemaFields(T);
    };
    return &Holder.items;
}

fn deriveResponseModelFieldRules(comptime T: type) []const ResponseModelFieldRule {
    const Root = responseModelRuleRootType(T);
    if (@typeInfo(Root) != .@"struct") return &.{};

    const count = comptime countResponseModelFieldRules(Root, "");
    if (count == 0) return &.{};

    const Holder = struct {
        const items = buildResponseModelFieldRules(Root);
    };
    return &Holder.items;
}

fn deriveResponseModelTransformFn(comptime T: type) ?ResponseModelTransformFn {
    const Root = responseModelRuleRootType(T);
    return switch (@typeInfo(Root)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => blk: {
            if (!@hasDecl(Root, "zigmund_response_transform")) break :blk null;
            const transform: ResponseModelTransformFn = &Root.zigmund_response_transform;
            break :blk transform;
        },
        else => null,
    };
}

fn deriveResponseModelValidateFn(comptime T: type) ?ResponseModelValidateFn {
    const Root = responseModelRuleRootType(T);
    return switch (@typeInfo(Root)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => blk: {
            if (!@hasDecl(Root, "zigmund_response_validate")) break :blk null;
            const validate: ResponseModelValidateFn = &Root.zigmund_response_validate;
            break :blk validate;
        },
        else => null,
    };
}

fn responseModelRuleRootType(comptime T: type) type {
    const Base = stripOptionalType(T);
    return switch (@typeInfo(Base)) {
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child != u8) break :blk stripOptionalType(ptr.child);
            break :blk Base;
        },
        else => Base,
    };
}

fn countResponseModelFieldRules(comptime T: type, comptime prefix: []const u8) usize {
    const Base = stripOptionalType(T);
    if (@typeInfo(Base) != .@"struct") return 0;

    const fields = @typeInfo(Base).@"struct".fields;
    var count: usize = 0;
    inline for (fields) |field| {
        const path = joinResponseModelPath(prefix, field.name);
        count += 1;
        count += countResponseModelFieldRules(field.type, path);
    }
    return count;
}

fn buildResponseModelFieldRules(comptime Root: type) [countResponseModelFieldRules(Root, "")]ResponseModelFieldRule {
    var out: [countResponseModelFieldRules(Root, "")]ResponseModelFieldRule = undefined;
    var idx: usize = 0;
    fillResponseModelFieldRules(Root, Root, "", &out, &idx);
    return out;
}

fn fillResponseModelFieldRules(
    comptime Root: type,
    comptime T: type,
    comptime prefix: []const u8,
    out: []ResponseModelFieldRule,
    idx: *usize,
) void {
    const Base = stripOptionalType(T);
    if (@typeInfo(Base) != .@"struct") return;

    const fields = @typeInfo(Base).@"struct".fields;
    inline for (fields) |field| {
        const path = joinResponseModelPath(prefix, field.name);
        out[idx.*] = .{
            .path = path,
            .alias = responseModelAliasForPath(Root, path),
            .default_value = responseModelDefaultForField(field.type, field.default_value_ptr),
        };
        idx.* += 1;
        fillResponseModelFieldRules(Root, field.type, path, out, idx);
    }
}

fn joinResponseModelPath(comptime prefix: []const u8, comptime field_name: []const u8) []const u8 {
    if (prefix.len == 0) return field_name;
    return std.fmt.comptimePrint("{s}.{s}", .{ prefix, field_name });
}

fn responseModelAliases(comptime T: type) []const ResponseModelAlias {
    if (!@hasDecl(T, "zigmund_response_aliases")) return &.{};

    const raw = T.zigmund_response_aliases;
    const RawType = @TypeOf(raw);

    if (RawType == []const ResponseModelAlias) return raw;
    if (@typeInfo(RawType) == .pointer) {
        const ptr = @typeInfo(RawType).pointer;
        if (ptr.size == .one and @typeInfo(ptr.child) == .array and @typeInfo(ptr.child).array.child == ResponseModelAlias) {
            return raw;
        }
    }
    @compileError("zigmund_response_aliases must be []const types.ResponseModelAlias");
}

fn responseModelAliasForPath(comptime Root: type, comptime path: []const u8) ?[]const u8 {
    const aliases = responseModelAliases(Root);
    inline for (aliases) |entry| {
        if (std.mem.eql(u8, entry.path, path)) return entry.alias;
    }
    return null;
}

fn responseModelDefaultForField(comptime FieldType: type, default_ptr: ?*const anyopaque) ResponseModelDefaultValue {
    if (default_ptr == null) return .none;
    const ptr: *const FieldType = @ptrCast(@alignCast(default_ptr.?));
    return responseModelDefaultFromValue(FieldType, ptr.*);
}

fn responseModelDefaultFromValue(comptime T: type, value: T) ResponseModelDefaultValue {
    if (@typeInfo(T) == .optional) {
        if (value == null) return .null;
        const Child = @typeInfo(T).optional.child;
        return responseModelDefaultFromValue(Child, value.?);
    }

    return switch (@typeInfo(T)) {
        .bool => .{ .bool = value },
        .int => |info| blk: {
            if (info.bits > 63) break :blk .none;
            break :blk .{ .integer = @as(i64, @intCast(value)) };
        },
        .comptime_int => blk: {
            if (value > std.math.maxInt(i64) or value < std.math.minInt(i64)) break :blk .none;
            break :blk .{ .integer = @as(i64, @intCast(value)) };
        },
        .float, .comptime_float => .{ .float = @as(f64, @floatCast(value)) },
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child == u8) break :blk .{ .string = value };
            break :blk .none;
        },
        .@"enum" => .{ .string = @tagName(value) },
        else => .none,
    };
}

fn buildSchemaFields(comptime T: type) [@typeInfo(T).@"struct".fields.len]OpenApiSchemaField {
    const fields = @typeInfo(T).@"struct".fields;
    var out: [fields.len]OpenApiSchemaField = undefined;

    inline for (fields, 0..) |field, idx| {
        const field_schema = deriveOpenApiSchema(field.type);
        out[idx] = .{
            .name = field.name,
            .required = !isOptionalType(field.type) and field.default_value_ptr == null,
            .schema_type = field_schema.schema_type,
            .schema_format = field_schema.schema_format,
            .is_array = field_schema.is_array,
            .fields = field_schema.fields,
        };
    }
    return out;
}

fn stripOptionalType(comptime T: type) type {
    if (@typeInfo(T) == .optional) {
        return @typeInfo(T).optional.child;
    }
    return T;
}

fn isOptionalType(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

pub const RouteMethod = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    OPTIONS,
    HEAD,
    TRACE,

    pub fn fromHttpMethod(method: std.http.Method) ?RouteMethod {
        return switch (method) {
            .GET => .GET,
            .POST => .POST,
            .PUT => .PUT,
            .PATCH => .PATCH,
            .DELETE => .DELETE,
            .OPTIONS => .OPTIONS,
            .HEAD => .HEAD,
            .TRACE => .TRACE,
            else => null,
        };
    }

    pub fn toHttpMethod(self: RouteMethod) std.http.Method {
        return switch (self) {
            .GET => .GET,
            .POST => .POST,
            .PUT => .PUT,
            .PATCH => .PATCH,
            .DELETE => .DELETE,
            .OPTIONS => .OPTIONS,
            .HEAD => .HEAD,
            .TRACE => .TRACE,
        };
    }

    pub fn asString(self: RouteMethod) []const u8 {
        return switch (self) {
            .GET => "get",
            .POST => "post",
            .PUT => "put",
            .PATCH => "patch",
            .DELETE => "delete",
            .OPTIONS => "options",
            .HEAD => "head",
            .TRACE => "trace",
        };
    }
};
