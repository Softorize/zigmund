const std = @import("std");
const types = @import("../core/types.zig");
const router_mod = @import("../core/router.zig");
const security = @import("../security/mod.zig");

const ComponentSchema = struct {
    name: []const u8,
    schema: types.OpenApiSchema,
};

const ParameterComponent = struct {
    name: []const u8,
    parameter: types.InjectedParameter,
};

const RequestBodyComponent = struct {
    name: []const u8,
    body_json: []const u8,
};

const ResponseEntryComponent = struct {
    name: []const u8,
    response_json: []const u8,
};

const GeneratedResponseEntry = struct {
    status_code: std.http.Status,
    description: []const u8,
    content_type: ?[]const u8,
    schema_opt: ?types.OpenApiSchema,
    schema_component_name: ?[]const u8,
    examples: []const types.OpenApiExample,
};

const OperationIdRegistry = struct {
    allocator: std.mem.Allocator,
    used: std.StringHashMapUnmanaged(void) = .empty,
    owned: std.ArrayList([]u8) = .empty,

    fn init(allocator: std.mem.Allocator) OperationIdRegistry {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *OperationIdRegistry) void {
        for (self.owned.items) |value| {
            self.allocator.free(value);
        }
        self.owned.deinit(self.allocator);
        self.used.deinit(self.allocator);
    }

    fn reserve(self: *OperationIdRegistry, candidate_raw: []const u8) ![]const u8 {
        const candidate = if (candidate_raw.len == 0) "operation" else candidate_raw;

        if (try self.addIfUnique(candidate)) |registered| {
            return registered;
        }

        var suffix: usize = 2;
        while (true) : (suffix += 1) {
            const with_suffix = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ candidate, suffix });
            defer self.allocator.free(with_suffix);
            if (try self.addIfUnique(with_suffix)) |registered| {
                return registered;
            }
        }
    }

    fn addIfUnique(self: *OperationIdRegistry, candidate: []const u8) !?[]const u8 {
        if (self.used.contains(candidate)) return null;

        const owned = try self.allocator.dupe(u8, candidate);
        errdefer self.allocator.free(owned);

        try self.owned.append(self.allocator, owned);
        try self.used.put(self.allocator, owned, {});
        return owned;
    }
};

const deterministic_http_method_order = [_]types.RouteMethod{
    .GET,
    .POST,
    .PUT,
    .PATCH,
    .DELETE,
    .OPTIONS,
    .HEAD,
    .TRACE,
};

pub fn generate(
    allocator: std.mem.Allocator,
    cfg: types.AppConfig,
    http_routes: []const router_mod.HttpRoute,
    websocket_routes: []const router_mod.WebSocketRoute,
    security_schemes: []const security.NamedScheme,
) ![]u8 {
    var unique_paths: std.ArrayList([]const u8) = .empty;
    defer unique_paths.deinit(allocator);

    for (http_routes) |route| {
        if (!route.options.include_in_schema) continue;
        try appendUniquePath(allocator, &unique_paths, route.path);
    }
    for (websocket_routes) |route| try appendUniquePath(allocator, &unique_paths, route.path);

    var response_components: std.ArrayList(ComponentSchema) = .empty;
    defer response_components.deinit(allocator);
    try collectResponseComponents(allocator, &response_components, http_routes);

    var parameter_components: std.ArrayList(ParameterComponent) = .empty;
    defer parameter_components.deinit(allocator);
    var owned_parameter_component_names: std.ArrayList([]u8) = .empty;
    defer {
        for (owned_parameter_component_names.items) |name| allocator.free(name);
        owned_parameter_component_names.deinit(allocator);
    }
    try collectParameterComponents(
        allocator,
        &parameter_components,
        &owned_parameter_component_names,
        http_routes,
    );

    var request_body_components: std.ArrayList(RequestBodyComponent) = .empty;
    defer request_body_components.deinit(allocator);
    var owned_request_body_component_names: std.ArrayList([]u8) = .empty;
    defer {
        for (owned_request_body_component_names.items) |name| allocator.free(name);
        owned_request_body_component_names.deinit(allocator);
    }
    defer {
        for (request_body_components.items) |entry| allocator.free(entry.body_json);
    }
    try collectRequestBodyComponents(
        allocator,
        &request_body_components,
        &owned_request_body_component_names,
        http_routes,
    );

    var response_entry_components: std.ArrayList(ResponseEntryComponent) = .empty;
    defer response_entry_components.deinit(allocator);
    var owned_response_entry_component_names: std.ArrayList([]u8) = .empty;
    defer {
        for (owned_response_entry_component_names.items) |name| allocator.free(name);
        owned_response_entry_component_names.deinit(allocator);
    }
    defer {
        for (response_entry_components.items) |entry| allocator.free(entry.response_json);
    }
    try collectResponseEntryComponents(
        allocator,
        &response_entry_components,
        &owned_response_entry_component_names,
        http_routes,
        response_components.items,
    );

    var operation_ids = OperationIdRegistry.init(allocator);
    defer operation_ids.deinit();

    var sorted_security_schemes: ?[]security.NamedScheme = null;
    defer if (sorted_security_schemes) |items| allocator.free(items);
    const component_security_schemes: []const security.NamedScheme = if (cfg.openapi_deterministic and security_schemes.len > 1) blk: {
        const copy = try allocator.alloc(security.NamedScheme, security_schemes.len);
        @memcpy(copy, security_schemes);
        std.mem.sort(security.NamedScheme, copy, {}, lessThanSecuritySchemeName);
        sorted_security_schemes = copy;
        break :blk copy;
    } else security_schemes;

    if (cfg.openapi_deterministic) {
        std.mem.sort([]const u8, unique_paths.items, {}, lessThanString);
        std.mem.sort(ComponentSchema, response_components.items, {}, lessThanComponentSchema);
        std.mem.sort(ParameterComponent, parameter_components.items, {}, lessThanParameterComponent);
        std.mem.sort(RequestBodyComponent, request_body_components.items, {}, lessThanRequestBodyComponent);
        std.mem.sort(ResponseEntryComponent, response_entry_components.items, {}, lessThanResponseEntryComponent);
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var writer = out.writer(allocator);
    try writer.writeAll("{");

    try writeFieldName(&writer, "openapi");
    try writer.writeAll("\"3.1.0\",");

    try writeFieldName(&writer, "info");
    try writer.writeAll("{");
    try writeFieldName(&writer, "title");
    try writeJsonString(&writer, cfg.title);
    try writer.writeAll(",");
    try writeFieldName(&writer, "version");
    try writeJsonString(&writer, cfg.version);
    try writer.writeAll("},");

    try writeFieldName(&writer, "servers");
    try writer.writeAll("[");
    for (cfg.servers, 0..) |server_url, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writer.writeAll("{");
        try writeFieldName(&writer, "url");
        try writeJsonString(&writer, server_url);
        try writer.writeAll("}");
    }
    try writer.writeAll("]");

    if (security_schemes.len > 0 or response_components.items.len > 0 or parameter_components.items.len > 0 or request_body_components.items.len > 0 or response_entry_components.items.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(&writer, "components");
        try writeComponents(
            &writer,
            component_security_schemes,
            response_components.items,
            parameter_components.items,
            request_body_components.items,
            response_entry_components.items,
        );
    }

    try writer.writeAll(",");
    try writeFieldName(&writer, "paths");
    try writer.writeAll("{");

    for (unique_paths.items, 0..) |path, path_idx| {
        if (path_idx != 0) try writer.writeAll(",");

        try writeJsonString(&writer, path);
        try writer.writeAll(":{");

        var field_count: usize = 0;

        if (cfg.openapi_deterministic) {
            for (deterministic_http_method_order) |method| {
                for (http_routes) |route| {
                    if (!std.mem.eql(u8, route.path, path)) continue;
                    if (route.method != method) continue;
                    if (!route.options.include_in_schema) continue;
                    if (field_count != 0) try writer.writeAll(",");
                    field_count += 1;
                    try writeHttpOperation(
                        &writer,
                        allocator,
                        route,
                        security_schemes,
                        response_components.items,
                        parameter_components.items,
                        request_body_components.items,
                        response_entry_components.items,
                        &operation_ids,
                    );
                }
            }
        } else {
            for (http_routes) |route| {
                if (!std.mem.eql(u8, route.path, path)) continue;
                if (!route.options.include_in_schema) continue;
                if (field_count != 0) try writer.writeAll(",");
                field_count += 1;
                try writeHttpOperation(
                    &writer,
                    allocator,
                    route,
                    security_schemes,
                    response_components.items,
                    parameter_components.items,
                    request_body_components.items,
                    response_entry_components.items,
                    &operation_ids,
                );
            }
        }

        for (websocket_routes) |route| {
            if (!std.mem.eql(u8, route.path, path)) continue;
            if (field_count != 0) try writer.writeAll(",");
            field_count += 1;
            try writeWebSocketOperation(
                &writer,
                allocator,
                route,
                security_schemes,
                &operation_ids,
            );
        }

        try writer.writeAll("}");
    }

    try writer.writeAll("}");

    if (cfg.webhooks.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(&writer, "webhooks");
        try writeWebhooks(&writer, allocator, cfg.webhooks, &operation_ids);
    }
    try writeOpenApiExtensions(&writer, allocator, cfg.openapi_extensions);
    try writer.writeAll("}");

    return out.toOwnedSlice(allocator);
}

fn lessThanString(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn lessThanComponentSchema(_: void, lhs: ComponentSchema, rhs: ComponentSchema) bool {
    return std.mem.order(u8, lhs.name, rhs.name) == .lt;
}

fn lessThanParameterComponent(_: void, lhs: ParameterComponent, rhs: ParameterComponent) bool {
    return std.mem.order(u8, lhs.name, rhs.name) == .lt;
}

fn lessThanRequestBodyComponent(_: void, lhs: RequestBodyComponent, rhs: RequestBodyComponent) bool {
    return std.mem.order(u8, lhs.name, rhs.name) == .lt;
}

fn lessThanResponseEntryComponent(_: void, lhs: ResponseEntryComponent, rhs: ResponseEntryComponent) bool {
    return std.mem.order(u8, lhs.name, rhs.name) == .lt;
}

fn lessThanSecuritySchemeName(_: void, lhs: security.NamedScheme, rhs: security.NamedScheme) bool {
    return std.mem.order(u8, lhs.name, rhs.name) == .lt;
}

fn writeHttpOperation(
    writer: anytype,
    allocator: std.mem.Allocator,
    route: router_mod.HttpRoute,
    security_schemes: []const security.NamedScheme,
    response_components: []const ComponentSchema,
    parameter_components: []const ParameterComponent,
    request_body_components: []const RequestBodyComponent,
    response_entry_components: []const ResponseEntryComponent,
    operation_ids: *OperationIdRegistry,
) !void {
    try writeJsonString(writer, route.method.asString());
    try writer.writeAll(":{");

    var owned_operation_id: ?[]u8 = null;
    defer {
        if (owned_operation_id) |op_id| allocator.free(op_id);
    }

    const candidate_operation_id = route.options.operation_id orelse route.options.name orelse blk: {
        const generated = try buildDefaultHttpOperationId(allocator, route.method, route.path);
        owned_operation_id = generated;
        break :blk generated;
    };
    const operation_id = try operation_ids.reserve(candidate_operation_id);
    const summary = route.options.summary orelse operation_id;
    const description = route.options.description orelse "";

    try writeFieldName(writer, "operationId");
    try writeJsonString(writer, operation_id);
    try writer.writeAll(",");

    try writeFieldName(writer, "summary");
    try writeJsonString(writer, summary);
    try writer.writeAll(",");

    try writeFieldName(writer, "description");
    try writeJsonString(writer, description);
    try writer.writeAll(",");

    try writeFieldName(writer, "deprecated");
    try writer.writeAll(if (route.options.deprecated) "true" else "false");

    if (route.options.tags.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "tags");
        try writeStringArray(writer, route.options.tags);
    }

    const injected_parameters = route.options.injected_parameters;
    if (pathParamCount(route.path) > 0 or injected_parameters.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "parameters");
        try writeOperationParameterArray(writer, route.path, injected_parameters, parameter_components);
    }

    const explicit_dependencies = route.options.dependencies;
    const injected_dependencies = route.options.injected_dependencies;
    const injected_request_bodies = route.options.injected_request_bodies;
    if (explicit_dependencies.len + injected_dependencies.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "x-zigmund-dependencies");
        try writeDependenciesArray(writer, explicit_dependencies, injected_dependencies);

        if (countRouteSecurityRequirements(
            explicit_dependencies,
            injected_dependencies,
            security_schemes,
        ) > 0) {
            try writer.writeAll(",");
            try writeFieldName(writer, "security");
            try writeRouteSecurity(
                writer,
                explicit_dependencies,
                injected_dependencies,
                security_schemes,
            );
        }
    }

    if (injected_request_bodies.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "requestBody");
        if (try requestBodyComponentName(
            allocator,
            injected_request_bodies,
            route.options.openapi_request_examples,
            request_body_components,
        )) |component_name| {
            try writeComponentRequestBodyRef(writer, component_name);
        } else {
            try writeInjectedRequestBody(
                writer,
                injected_request_bodies,
                route.options.openapi_request_examples,
            );
        }
    }

    if (route.options.response_model_name) |model_name| {
        try writer.writeAll(",");
        try writeFieldName(writer, "x-zigmund-response-model");
        try writeJsonString(writer, model_name);
    }

    if (route.options.openapi_callbacks.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "callbacks");
        try writeOperationCallbacks(writer, allocator, route.options.openapi_callbacks, operation_ids);
    }

    try writer.writeAll(",");
    try writeFieldName(writer, "responses");
    const response_component_name = responseComponentName(route.options, response_components);
    try writeResponsesObject(
        writer,
        allocator,
        route.options,
        response_component_name,
        response_entry_components,
    );

    try writeOpenApiExtensions(writer, allocator, route.options.openapi_extensions);
    try writer.writeAll("}");
}

fn writeWebSocketOperation(
    writer: anytype,
    allocator: std.mem.Allocator,
    route: router_mod.WebSocketRoute,
    security_schemes: []const security.NamedScheme,
    operation_ids: *OperationIdRegistry,
) !void {
    try writeFieldName(writer, "x-zigmund-websocket");
    try writer.writeAll("{");
    var owned_ws_operation_id: ?[]u8 = null;
    defer {
        if (owned_ws_operation_id) |op_id| allocator.free(op_id);
    }

    const candidate_operation_id = route.options.operation_id orelse route.options.name orelse blk: {
        const generated = try buildDefaultWebSocketOperationId(allocator, route.path);
        owned_ws_operation_id = generated;
        break :blk generated;
    };
    const operation_id = try operation_ids.reserve(candidate_operation_id);
    try writeFieldName(writer, "operationId");
    try writeJsonString(writer, operation_id);
    if (route.options.dependencies.len + route.injected_dependencies.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "dependencies");
        try writeDependenciesArray(writer, route.options.dependencies, route.injected_dependencies);

        if (countRouteSecurityRequirements(
            route.options.dependencies,
            route.injected_dependencies,
            security_schemes,
        ) > 0) {
            try writer.writeAll(",");
            try writeFieldName(writer, "security");
            try writeRouteSecurity(
                writer,
                route.options.dependencies,
                route.injected_dependencies,
                security_schemes,
            );
        }
    }
    if (route.options.allowed_origins.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "allowedOrigins");
        try writeStringArray(writer, route.options.allowed_origins);
    }
    if (route.options.subprotocols.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "subprotocols");
        try writeStringArray(writer, route.options.subprotocols);
    }
    if (route.options.require_subprotocol) {
        try writer.writeAll(",");
        try writeFieldName(writer, "requireSubprotocol");
        try writer.writeAll("true");
    }
    if (route.options.ping_interval_ms) |ping_interval_ms| {
        try writer.writeAll(",");
        try writeFieldName(writer, "pingIntervalMs");
        try writer.print("{d}", .{ping_interval_ms});
    }
    if (route.options.pong_timeout_ms) |pong_timeout_ms| {
        try writer.writeAll(",");
        try writeFieldName(writer, "pongTimeoutMs");
        try writer.print("{d}", .{pong_timeout_ms});
    }
    if (route.options.max_message_bytes) |max_message_bytes| {
        try writer.writeAll(",");
        try writeFieldName(writer, "maxMessageBytes");
        try writer.print("{d}", .{max_message_bytes});
    }
    if (route.options.max_pending_messages) |max_pending_messages| {
        try writer.writeAll(",");
        try writeFieldName(writer, "maxPendingMessages");
        try writer.print("{d}", .{max_pending_messages});
    }
    if (route.options.send_timeout_ms) |send_timeout_ms| {
        try writer.writeAll(",");
        try writeFieldName(writer, "sendTimeoutMs");
        try writer.print("{d}", .{send_timeout_ms});
    }
    if (route.options.idle_timeout_ms) |idle_timeout_ms| {
        try writer.writeAll(",");
        try writeFieldName(writer, "idleTimeoutMs");
        try writer.print("{d}", .{idle_timeout_ms});
    }
    if (!route.options.auto_pong) {
        try writer.writeAll(",");
        try writeFieldName(writer, "autoPong");
        try writer.writeAll("false");
    }

    try writeOpenApiExtensions(writer, allocator, route.options.openapi_extensions);
    try writer.writeAll("}");
}

fn writeOpenApiExtensions(
    writer: anytype,
    allocator: std.mem.Allocator,
    extensions: []const types.OpenApiExtension,
) !void {
    for (extensions) |extension| {
        if (!isValidOpenApiExtensionKey(extension.key)) return error.InvalidOpenApiExtensionKey;
        const valid_json = try std.json.Scanner.validate(allocator, extension.value_json);
        if (!valid_json) return error.InvalidOpenApiExtensionJson;

        try writer.writeAll(",");
        try writeJsonString(writer, extension.key);
        try writer.writeAll(":");
        try writer.writeAll(extension.value_json);
    }
}

fn isValidOpenApiExtensionKey(key: []const u8) bool {
    if (key.len < 3) return false;
    return std.ascii.toLower(key[0]) == 'x' and key[1] == '-';
}

fn appendUniquePath(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), path: []const u8) !void {
    for (list.items) |existing| {
        if (std.mem.eql(u8, existing, path)) return;
    }
    try list.append(allocator, path);
}

fn collectResponseComponents(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(ComponentSchema),
    routes: []const router_mod.HttpRoute,
) !void {
    for (routes) |route| {
        if (!route.options.include_in_schema) continue;
        const model_name = route.options.response_model_name orelse continue;
        const model_schema = route.options.response_model_schema orelse continue;

        if (responseComponentName(route.options, list.items) != null) continue;
        try list.append(allocator, .{
            .name = model_name,
            .schema = model_schema,
        });
    }
}

fn responseComponentName(
    route_options: types.StoredRouteOptions,
    components: []const ComponentSchema,
) ?[]const u8 {
    const model_name = route_options.response_model_name orelse return null;
    for (components) |component| {
        if (std.mem.eql(u8, component.name, model_name)) return component.name;
    }
    return null;
}

fn collectParameterComponents(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(ParameterComponent),
    owned_names: *std.ArrayList([]u8),
    routes: []const router_mod.HttpRoute,
) !void {
    for (routes) |route| {
        if (!route.options.include_in_schema) continue;
        for (route.options.injected_parameters) |parameter| {
            if (parameterComponentName(parameter, list.items) != null) continue;

            const name = try uniqueParameterComponentName(allocator, list.items, parameter);
            errdefer allocator.free(name);

            try owned_names.append(allocator, name);
            try list.append(allocator, .{
                .name = name,
                .parameter = parameter,
            });
        }
    }
}

fn uniqueParameterComponentName(
    allocator: std.mem.Allocator,
    components: []const ParameterComponent,
    parameter: types.InjectedParameter,
) ![]u8 {
    const base_name = try buildParameterComponentBaseName(allocator, parameter);
    errdefer allocator.free(base_name);

    if (!hasParameterComponentName(components, base_name)) {
        return base_name;
    }

    var suffix: usize = 2;
    while (true) : (suffix += 1) {
        const candidate = try std.fmt.allocPrint(allocator, "{s}_{d}", .{ base_name, suffix });
        errdefer allocator.free(candidate);
        if (hasParameterComponentName(components, candidate)) {
            allocator.free(candidate);
            continue;
        }
        allocator.free(base_name);
        return candidate;
    }
}

fn buildParameterComponentBaseName(
    allocator: std.mem.Allocator,
    parameter: types.InjectedParameter,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try appendNormalizedIdentifierPart(&out, allocator, parameter.in.asString());
    if (out.items.len > 0 and out.items[out.items.len - 1] != '_') {
        try out.append(allocator, '_');
    }
    try appendNormalizedIdentifierPart(&out, allocator, parameter.name);
    if (out.items.len == 0) {
        try out.appendSlice(allocator, "parameter");
    }

    while (out.items.len > 0 and out.items[out.items.len - 1] == '_') {
        _ = out.pop();
    }

    return out.toOwnedSlice(allocator);
}

fn hasParameterComponentName(components: []const ParameterComponent, name: []const u8) bool {
    for (components) |component| {
        if (std.mem.eql(u8, component.name, name)) return true;
    }
    return false;
}

fn parameterComponentName(
    target: types.InjectedParameter,
    components: []const ParameterComponent,
) ?[]const u8 {
    for (components) |component| {
        if (sameInjectedParameter(target, component.parameter)) return component.name;
    }
    return null;
}

fn sameInjectedParameter(lhs: types.InjectedParameter, rhs: types.InjectedParameter) bool {
    if (!std.mem.eql(u8, lhs.name, rhs.name)) return false;
    if (lhs.in != rhs.in) return false;
    if (lhs.required != rhs.required) return false;
    if (lhs.deprecated != rhs.deprecated) return false;
    if (!optionalStringEql(lhs.description, rhs.description)) return false;
    if (!std.mem.eql(u8, lhs.schema_type, rhs.schema_type)) return false;
    if (!optionalStringEql(lhs.schema_format, rhs.schema_format)) return false;
    if (lhs.is_array != rhs.is_array) return false;
    if (lhs.gt != rhs.gt) return false;
    if (lhs.ge != rhs.ge) return false;
    if (lhs.lt != rhs.lt) return false;
    if (lhs.le != rhs.le) return false;
    if (lhs.min_length != rhs.min_length) return false;
    if (lhs.max_length != rhs.max_length) return false;
    if (!optionalStringEql(lhs.pattern, rhs.pattern)) return false;
    if (!stringSliceArrayEql(lhs.enum_values, rhs.enum_values)) return false;
    if (lhs.strict != rhs.strict) return false;
    return true;
}

fn optionalStringEql(lhs: ?[]const u8, rhs: ?[]const u8) bool {
    if (lhs == null and rhs == null) return true;
    if (lhs == null or rhs == null) return false;
    return std.mem.eql(u8, lhs.?, rhs.?);
}

fn stringSliceArrayEql(lhs: []const []const u8, rhs: []const []const u8) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |lhs_item, rhs_item| {
        if (!std.mem.eql(u8, lhs_item, rhs_item)) return false;
    }
    return true;
}

fn collectRequestBodyComponents(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(RequestBodyComponent),
    owned_names: *std.ArrayList([]u8),
    routes: []const router_mod.HttpRoute,
) !void {
    for (routes) |route| {
        if (!route.options.include_in_schema) continue;
        const specs = route.options.injected_request_bodies;
        if (specs.len == 0) continue;

        const body_json = try renderInjectedRequestBodyJson(
            allocator,
            specs,
            route.options.openapi_request_examples,
        );
        errdefer allocator.free(body_json);

        if (requestBodyComponentNameByJson(body_json, list.items) != null) {
            allocator.free(body_json);
            continue;
        }

        const name = try uniqueRequestBodyComponentName(allocator, list.items, route);
        errdefer allocator.free(name);

        try owned_names.append(allocator, name);
        try list.append(allocator, .{
            .name = name,
            .body_json = body_json,
        });
    }
}

fn uniqueRequestBodyComponentName(
    allocator: std.mem.Allocator,
    components: []const RequestBodyComponent,
    route: router_mod.HttpRoute,
) ![]u8 {
    const base_name = try buildRequestBodyComponentBaseName(allocator, route.method, route.path);
    errdefer allocator.free(base_name);

    if (!hasRequestBodyComponentName(components, base_name)) {
        return base_name;
    }

    var suffix: usize = 2;
    while (true) : (suffix += 1) {
        const candidate = try std.fmt.allocPrint(allocator, "{s}_{d}", .{ base_name, suffix });
        errdefer allocator.free(candidate);
        if (hasRequestBodyComponentName(components, candidate)) {
            allocator.free(candidate);
            continue;
        }
        allocator.free(base_name);
        return candidate;
    }
}

fn buildRequestBodyComponentBaseName(
    allocator: std.mem.Allocator,
    method: types.RouteMethod,
    path: []const u8,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try appendNormalizedIdentifierPart(&out, allocator, "request_body");
    if (out.items.len > 0 and out.items[out.items.len - 1] != '_') {
        try out.append(allocator, '_');
    }
    try appendNormalizedIdentifierPart(&out, allocator, method.asString());
    if (out.items.len > 0 and out.items[out.items.len - 1] != '_') {
        try out.append(allocator, '_');
    }
    try appendNormalizedIdentifierPart(&out, allocator, path);

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "request_body");
    }

    while (out.items.len > 0 and out.items[out.items.len - 1] == '_') {
        _ = out.pop();
    }

    return out.toOwnedSlice(allocator);
}

fn hasRequestBodyComponentName(components: []const RequestBodyComponent, name: []const u8) bool {
    for (components) |component| {
        if (std.mem.eql(u8, component.name, name)) return true;
    }
    return false;
}

fn renderInjectedRequestBodyJson(
    allocator: std.mem.Allocator,
    specs: []const types.InjectedRequestBody,
    examples: []const types.OpenApiExample,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var writer = out.writer(allocator);
    try writeInjectedRequestBody(&writer, specs, examples);
    return out.toOwnedSlice(allocator);
}

fn requestBodyComponentName(
    allocator: std.mem.Allocator,
    specs: []const types.InjectedRequestBody,
    examples: []const types.OpenApiExample,
    components: []const RequestBodyComponent,
) !?[]const u8 {
    const body_json = try renderInjectedRequestBodyJson(allocator, specs, examples);
    defer allocator.free(body_json);
    return requestBodyComponentNameByJson(body_json, components);
}

fn requestBodyComponentNameByJson(
    body_json: []const u8,
    components: []const RequestBodyComponent,
) ?[]const u8 {
    for (components) |component| {
        if (std.mem.eql(u8, component.body_json, body_json)) return component.name;
    }
    return null;
}

fn collectResponseEntryComponents(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(ResponseEntryComponent),
    owned_names: *std.ArrayList([]u8),
    routes: []const router_mod.HttpRoute,
    response_schema_components: []const ComponentSchema,
) !void {
    for (routes) |route| {
        if (!route.options.include_in_schema) continue;
        const schema_component_name = responseComponentName(route.options, response_schema_components);

        var entries: std.ArrayList(GeneratedResponseEntry) = .empty;
        defer entries.deinit(allocator);
        try appendGeneratedResponseEntries(
            allocator,
            &entries,
            route.options,
            schema_component_name,
        );

        for (entries.items) |entry| {
            const response_json = try renderResponseEntryValueJson(allocator, entry);
            errdefer allocator.free(response_json);

            if (responseEntryComponentNameByJson(response_json, list.items) != null) {
                allocator.free(response_json);
                continue;
            }

            const name = try uniqueResponseEntryComponentName(
                allocator,
                list.items,
                route.method,
                route.path,
                entry.status_code,
            );
            errdefer allocator.free(name);

            try owned_names.append(allocator, name);
            try list.append(allocator, .{
                .name = name,
                .response_json = response_json,
            });
        }
    }
}

fn uniqueResponseEntryComponentName(
    allocator: std.mem.Allocator,
    components: []const ResponseEntryComponent,
    method: types.RouteMethod,
    path: []const u8,
    status_code: std.http.Status,
) ![]u8 {
    const base_name = try buildResponseEntryComponentBaseName(allocator, method, path, status_code);
    errdefer allocator.free(base_name);

    if (!hasResponseEntryComponentName(components, base_name)) {
        return base_name;
    }

    var suffix: usize = 2;
    while (true) : (suffix += 1) {
        const candidate = try std.fmt.allocPrint(allocator, "{s}_{d}", .{ base_name, suffix });
        errdefer allocator.free(candidate);
        if (hasResponseEntryComponentName(components, candidate)) {
            allocator.free(candidate);
            continue;
        }
        allocator.free(base_name);
        return candidate;
    }
}

fn buildResponseEntryComponentBaseName(
    allocator: std.mem.Allocator,
    method: types.RouteMethod,
    path: []const u8,
    status_code: std.http.Status,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try appendNormalizedIdentifierPart(&out, allocator, "response");
    if (out.items.len > 0 and out.items[out.items.len - 1] != '_') try out.append(allocator, '_');

    var status_buf: [3]u8 = undefined;
    const status_str = try std.fmt.bufPrint(&status_buf, "{d}", .{@intFromEnum(status_code)});
    try appendNormalizedIdentifierPart(&out, allocator, status_str);
    if (out.items.len > 0 and out.items[out.items.len - 1] != '_') try out.append(allocator, '_');

    try appendNormalizedIdentifierPart(&out, allocator, method.asString());
    if (out.items.len > 0 and out.items[out.items.len - 1] != '_') try out.append(allocator, '_');

    try appendNormalizedIdentifierPart(&out, allocator, path);

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "response");
    }
    while (out.items.len > 0 and out.items[out.items.len - 1] == '_') {
        _ = out.pop();
    }
    return out.toOwnedSlice(allocator);
}

fn hasResponseEntryComponentName(components: []const ResponseEntryComponent, name: []const u8) bool {
    for (components) |component| {
        if (std.mem.eql(u8, component.name, name)) return true;
    }
    return false;
}

fn responseEntryComponentNameByJson(
    response_json: []const u8,
    components: []const ResponseEntryComponent,
) ?[]const u8 {
    for (components) |component| {
        if (std.mem.eql(u8, component.response_json, response_json)) return component.name;
    }
    return null;
}

fn responseEntryComponentName(
    allocator: std.mem.Allocator,
    entry: GeneratedResponseEntry,
    components: []const ResponseEntryComponent,
) !?[]const u8 {
    const response_json = try renderResponseEntryValueJson(allocator, entry);
    defer allocator.free(response_json);
    return responseEntryComponentNameByJson(response_json, components);
}

fn buildDefaultHttpOperationId(
    allocator: std.mem.Allocator,
    method: types.RouteMethod,
    path: []const u8,
) ![]u8 {
    return buildDefaultOperationId(allocator, method.asString(), path);
}

fn buildDefaultWebSocketOperationId(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]u8 {
    return buildDefaultOperationId(allocator, "websocket", path);
}

fn buildDefaultOperationId(
    allocator: std.mem.Allocator,
    prefix: []const u8,
    path: []const u8,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try appendNormalizedIdentifierPart(&out, allocator, prefix);
    try out.append(allocator, '_');

    const trimmed = std.mem.trim(u8, path, "/");
    if (trimmed.len == 0) {
        try out.appendSlice(allocator, "root");
    } else {
        var wrote_any = false;
        for (trimmed) |ch| {
            if (std.ascii.isAlphanumeric(ch)) {
                try out.append(allocator, std.ascii.toLower(ch));
                wrote_any = true;
                continue;
            }

            if (out.items.len == 0 or out.items[out.items.len - 1] == '_') continue;
            try out.append(allocator, '_');
        }

        if (!wrote_any) {
            try out.appendSlice(allocator, "route");
        }
    }

    while (out.items.len > 0 and out.items[out.items.len - 1] == '_') {
        _ = out.pop();
    }

    return out.toOwnedSlice(allocator);
}

fn appendNormalizedIdentifierPart(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: []const u8,
) !void {
    for (value) |ch| {
        if (std.ascii.isAlphanumeric(ch)) {
            try out.append(allocator, std.ascii.toLower(ch));
            continue;
        }
        if (out.items.len == 0 or out.items[out.items.len - 1] == '_') continue;
        try out.append(allocator, '_');
    }
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.print("{f}", .{std.json.fmt(value, .{})});
}

fn writeFieldName(writer: anytype, name: []const u8) !void {
    try writeJsonString(writer, name);
    try writer.writeAll(":");
}

fn writeStringArray(writer: anytype, values: []const []const u8) !void {
    try writer.writeAll("[");
    for (values, 0..) |value, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writeJsonString(writer, value);
    }
    try writer.writeAll("]");
}

fn writeOperationParameterArray(
    writer: anytype,
    path: []const u8,
    injected_parameters: []const types.InjectedParameter,
    parameter_components: []const ParameterComponent,
) !void {
    try writer.writeAll("[");

    var wrote: usize = 0;
    for (injected_parameters) |param| {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        if (parameterComponentName(param, parameter_components)) |component_name| {
            try writeComponentParameterRef(writer, component_name);
        } else {
            try writeInjectedParameter(writer, param);
        }
    }

    var idx: usize = 0;
    while (std.mem.indexOfScalarPos(u8, path, idx, '{')) |start| {
        const end = std.mem.indexOfScalarPos(u8, path, start + 1, '}') orelse break;
        if (end <= start + 1) {
            idx = end + 1;
            continue;
        }

        const placeholder = path[start + 1 .. end];
        const name = placeholderName(placeholder);
        if (name.len == 0) {
            idx = end + 1;
            continue;
        }
        if (hasInjectedPathParameter(injected_parameters, name)) {
            idx = end + 1;
            continue;
        }

        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writeFallbackPathParameter(writer, name);
        idx = end + 1;
    }

    try writer.writeAll("]");
}

fn placeholderName(placeholder: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, placeholder, " \t");
    if (trimmed.len == 0) return "";

    if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon_idx| {
        return std.mem.trim(u8, trimmed[0..colon_idx], " \t");
    }

    return trimmed;
}

fn writeInjectedParameter(writer: anytype, parameter: types.InjectedParameter) !void {
    try writer.writeAll("{");
    try writeFieldName(writer, "name");
    try writeJsonString(writer, parameter.name);
    try writer.writeAll(",");
    try writeFieldName(writer, "in");
    try writeJsonString(writer, parameter.in.asString());
    try writer.writeAll(",");
    try writeFieldName(writer, "required");
    try writer.writeAll(if (parameter.in == .path or parameter.required) "true" else "false");

    if (parameter.deprecated) {
        try writer.writeAll(",");
        try writeFieldName(writer, "deprecated");
        try writer.writeAll("true");
    }

    if (parameter.description) |description| {
        try writer.writeAll(",");
        try writeFieldName(writer, "description");
        try writeJsonString(writer, description);
    }

    try writer.writeAll(",");
    try writeFieldName(writer, "schema");
    try writer.writeAll("{");
    if (parameter.is_array) {
        try writeFieldName(writer, "type");
        try writeJsonString(writer, "array");
        try writer.writeAll(",");
        try writeFieldName(writer, "items");
        try writeSchema(writer, arrayItemSchemaType(parameter.schema_type), parameter.schema_format, false, &.{});
    } else {
        try writeFieldName(writer, "type");
        try writeJsonString(writer, parameter.schema_type);
        if (parameter.schema_format) |fmt| {
            try writer.writeAll(",");
            try writeFieldName(writer, "format");
            try writeJsonString(writer, fmt);
        }
    }
    try writeSchemaConstraints(
        writer,
        parameter.gt,
        parameter.ge,
        parameter.lt,
        parameter.le,
        parameter.min_length,
        parameter.max_length,
        parameter.pattern,
        parameter.enum_values,
        parameter.strict,
    );
    try writer.writeAll("}");
    try writer.writeAll("}");
}

fn writeComponentParameterRef(writer: anytype, component_name: []const u8) !void {
    try writer.writeAll("{");
    try writeFieldName(writer, "$ref");
    try writer.writeAll("\"#/components/parameters/");
    try writer.writeAll(component_name);
    try writer.writeAll("\"}");
}

fn writeComponentRequestBodyRef(writer: anytype, component_name: []const u8) !void {
    try writer.writeAll("{");
    try writeFieldName(writer, "$ref");
    try writer.writeAll("\"#/components/requestBodies/");
    try writer.writeAll(component_name);
    try writer.writeAll("\"}");
}

fn writeComponentResponseRef(writer: anytype, component_name: []const u8) !void {
    try writer.writeAll("{");
    try writeFieldName(writer, "$ref");
    try writer.writeAll("\"#/components/responses/");
    try writer.writeAll(component_name);
    try writer.writeAll("\"}");
}

fn writeFallbackPathParameter(writer: anytype, name: []const u8) !void {
    try writer.writeAll("{");
    try writeFieldName(writer, "name");
    try writeJsonString(writer, name);
    try writer.writeAll(",");
    try writeFieldName(writer, "in");
    try writeJsonString(writer, "path");
    try writer.writeAll(",");
    try writeFieldName(writer, "required");
    try writer.writeAll("true,");
    try writeFieldName(writer, "schema");
    try writeSchema(writer, "string", null, false, &.{});
    try writer.writeAll("}");
}

fn hasInjectedPathParameter(parameters: []const types.InjectedParameter, name: []const u8) bool {
    for (parameters) |parameter| {
        if (parameter.in != .path) continue;
        if (std.mem.eql(u8, parameter.name, name)) return true;
    }
    return false;
}

fn writeSchema(
    writer: anytype,
    schema_type: []const u8,
    schema_format: ?[]const u8,
    is_array: bool,
    fields: []const types.OpenApiSchemaField,
) !void {
    try writeOpenApiSchema(writer, .{
        .schema_type = schema_type,
        .schema_format = schema_format,
        .is_array = is_array,
        .fields = fields,
    });
}

fn writeOpenApiSchema(writer: anytype, schema: types.OpenApiSchema) anyerror!void {
    if (schema.is_array) {
        try writer.writeAll("{");
        try writeFieldName(writer, "type");
        try writeJsonString(writer, "array");
        try writer.writeAll(",");
        try writeFieldName(writer, "items");
        try writeOpenApiSchema(writer, .{
            .schema_type = arrayItemSchemaType(schema.schema_type),
            .schema_format = schema.schema_format,
            .fields = schema.fields,
            .one_of = schema.one_of,
            .any_of = schema.any_of,
            .all_of = schema.all_of,
            .discriminator_property_name = schema.discriminator_property_name,
            .discriminator_mapping = schema.discriminator_mapping,
        });
        try writer.writeAll("}");
        return;
    }

    try writer.writeAll("{");
    try writeFieldName(writer, "type");
    try writeJsonString(writer, schema.schema_type);

    if (schema.schema_format) |fmt| {
        try writer.writeAll(",");
        try writeFieldName(writer, "format");
        try writeJsonString(writer, fmt);
    }

    if (schema.one_of.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "oneOf");
        try writeOpenApiSchemaArray(writer, schema.one_of);
    }
    if (schema.any_of.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "anyOf");
        try writeOpenApiSchemaArray(writer, schema.any_of);
    }
    if (schema.all_of.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "allOf");
        try writeOpenApiSchemaArray(writer, schema.all_of);
    }
    if (schema.discriminator_property_name) |property_name| {
        try writer.writeAll(",");
        try writeFieldName(writer, "discriminator");
        try writer.writeAll("{");
        try writeFieldName(writer, "propertyName");
        try writeJsonString(writer, property_name);
        if (schema.discriminator_mapping.len > 0) {
            try writer.writeAll(",");
            try writeFieldName(writer, "mapping");
            try writer.writeAll("{");
            for (schema.discriminator_mapping, 0..) |mapping, idx| {
                if (idx != 0) try writer.writeAll(",");
                try writeJsonString(writer, mapping.value);
                try writer.writeAll(":");
                try writeJsonString(writer, mapping.schema_ref);
            }
            try writer.writeAll("}");
        }
        try writer.writeAll("}");
    }

    if (std.mem.eql(u8, schema.schema_type, "object") and schema.fields.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "properties");
        try writer.writeAll("{");
        var wrote: usize = 0;
        for (schema.fields) |field| {
            if (wrote != 0) try writer.writeAll(",");
            wrote += 1;
            try writeJsonString(writer, field.name);
            try writer.writeAll(":");
            try writeOpenApiSchema(writer, .{
                .schema_type = field.schema_type,
                .schema_format = field.schema_format,
                .is_array = field.is_array,
                .fields = field.fields,
            });
        }
        try writer.writeAll("}");

        const required_count = schemaRequiredFieldCount(schema.fields);
        if (required_count > 0) {
            try writer.writeAll(",");
            try writeFieldName(writer, "required");
            try writer.writeAll("[");
            var required_written: usize = 0;
            for (schema.fields) |field| {
                if (!field.required) continue;
                if (required_written != 0) try writer.writeAll(",");
                required_written += 1;
                try writeJsonString(writer, field.name);
            }
            try writer.writeAll("]");
        }
    }

    try writer.writeAll("}");
}

fn writeOpenApiSchemaArray(writer: anytype, schemas: []const types.OpenApiSchema) anyerror!void {
    try writer.writeAll("[");
    for (schemas, 0..) |schema, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writeOpenApiSchema(writer, schema);
    }
    try writer.writeAll("]");
}

fn schemaRequiredFieldCount(fields: []const types.OpenApiSchemaField) usize {
    var count: usize = 0;
    for (fields) |field| {
        if (field.required) count += 1;
    }
    return count;
}

fn arrayItemSchemaType(schema_type: []const u8) []const u8 {
    if (std.mem.eql(u8, schema_type, "array")) return "string";
    return schema_type;
}

fn writeDependenciesArray(
    writer: anytype,
    dependencies: []const types.DependencySpec,
    injected_dependencies: []const types.DependencySpec,
) !void {
    try writer.writeAll("[");
    var wrote: usize = 0;

    for (dependencies) |dep| {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writer.writeAll("{");
        try writeFieldName(writer, "name");
        try writeJsonString(writer, dep.name);
        try writer.writeAll(",");
        try writeFieldName(writer, "required");
        try writer.writeAll(if (dep.required) "true" else "false");
        try writer.writeAll(",");
        try writeFieldName(writer, "useCache");
        try writer.writeAll(if (dep.use_cache) "true" else "false");
        try writer.writeAll(",");
        try writeFieldName(writer, "cacheScope");
        try writeJsonString(writer, dependencyCacheScopeString(dep.cache_scope));
        if (dep.depends_on.len > 0) {
            try writer.writeAll(",");
            try writeFieldName(writer, "dependsOn");
            try writeStringArray(writer, dep.depends_on);
        }
        if (dep.scopes.len > 0) {
            try writer.writeAll(",");
            try writeFieldName(writer, "scopes");
            try writeStringArray(writer, dep.scopes);
        }
        try writer.writeAll("}");
    }

    for (injected_dependencies) |dep| {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writer.writeAll("{");
        try writeFieldName(writer, "name");
        try writeJsonString(writer, dep.name);
        try writer.writeAll(",");
        try writeFieldName(writer, "required");
        try writer.writeAll(if (dep.required) "true" else "false");
        try writer.writeAll(",");
        try writeFieldName(writer, "useCache");
        try writer.writeAll(if (dep.use_cache) "true" else "false");
        try writer.writeAll(",");
        try writeFieldName(writer, "cacheScope");
        try writeJsonString(writer, dependencyCacheScopeString(dep.cache_scope));
        if (dep.depends_on.len > 0) {
            try writer.writeAll(",");
            try writeFieldName(writer, "dependsOn");
            try writeStringArray(writer, dep.depends_on);
        }
        if (dep.scopes.len > 0) {
            try writer.writeAll(",");
            try writeFieldName(writer, "scopes");
            try writeStringArray(writer, dep.scopes);
        }
        try writer.writeAll("}");
    }
    try writer.writeAll("]");
}

fn dependencyCacheScopeString(scope: types.DependencyCacheScope) []const u8 {
    return switch (scope) {
        .request => "request",
        .app => "app",
    };
}

fn writeOpenApiExamples(writer: anytype, examples: []const types.OpenApiExample) !void {
    try writer.writeAll("{");
    for (examples, 0..) |example, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writeJsonString(writer, example.name);
        try writer.writeAll(":{");

        var wrote: usize = 0;
        if (example.summary) |summary| {
            try writeFieldName(writer, "summary");
            try writeJsonString(writer, summary);
            wrote += 1;
        }
        if (example.description) |description| {
            if (wrote != 0) try writer.writeAll(",");
            try writeFieldName(writer, "description");
            try writeJsonString(writer, description);
            wrote += 1;
        }
        if (wrote != 0) try writer.writeAll(",");
        try writeFieldName(writer, "value");
        try writer.writeAll(example.value_json);
        try writer.writeAll("}");
    }
    try writer.writeAll("}");
}

fn writeInjectedRequestBody(
    writer: anytype,
    specs: []const types.InjectedRequestBody,
    examples: []const types.OpenApiExample,
) !void {
    var required = false;
    for (specs) |spec| {
        if (spec.required) {
            required = true;
            break;
        }
    }

    try writer.writeAll("{");
    try writeFieldName(writer, "required");
    try writer.writeAll(if (required) "true" else "false");
    try writer.writeAll(",");
    try writeFieldName(writer, "content");
    try writer.writeAll("{");

    var wrote: usize = 0;
    for (specs, 0..) |spec, idx| {
        if (requestBodyMediaTypeSeen(specs[0..idx], spec.media_type)) continue;

        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;

        try writeJsonString(writer, spec.media_type);
        try writer.writeAll(":{\"schema\":");
        try writeRequestBodySchema(writer, spec.media_type, specs);
        if (examples.len > 0) {
            try writer.writeAll(",");
            try writeFieldName(writer, "examples");
            try writeOpenApiExamples(writer, examples);
        }
        try writer.writeAll("}");
    }

    try writer.writeAll("}");
    try writer.writeAll("}");
}

fn writeRequestBodySchema(
    writer: anytype,
    media_type: []const u8,
    specs: []const types.InjectedRequestBody,
) !void {
    const properties_count = countRequestBodyProperties(media_type, specs);
    const required_count = countRequestBodyRequiredProperties(media_type, specs);

    try writer.writeAll("{");
    try writeFieldName(writer, "type");
    try writeJsonString(writer, "object");

    if (properties_count > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "properties");
        try writer.writeAll("{");

        var wrote: usize = 0;
        for (specs, 0..) |spec, spec_idx| {
            if (!std.ascii.eqlIgnoreCase(spec.media_type, media_type)) continue;
            for (spec.fields, 0..) |field, field_idx| {
                if (requestBodyFieldSeen(specs, media_type, spec_idx, field_idx, field.name)) continue;

                if (wrote != 0) try writer.writeAll(",");
                wrote += 1;

                try writeJsonString(writer, field.name);
                try writer.writeAll(":");
                try writeRequestBodyFieldSchema(writer, field);
            }
        }
        try writer.writeAll("}");
    }

    if (required_count > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "required");
        try writer.writeAll("[");

        var wrote_required: usize = 0;
        for (specs, 0..) |spec, spec_idx| {
            if (!std.ascii.eqlIgnoreCase(spec.media_type, media_type)) continue;
            for (spec.fields, 0..) |field, field_idx| {
                if (requestBodyFieldSeen(specs, media_type, spec_idx, field_idx, field.name)) continue;
                if (!requestBodyFieldIsRequired(specs, media_type, field.name)) continue;

                if (wrote_required != 0) try writer.writeAll(",");
                wrote_required += 1;
                try writeJsonString(writer, field.name);
            }
        }
        try writer.writeAll("]");
    }

    try writer.writeAll("}");
}

fn writeRequestBodyFieldSchema(writer: anytype, field: types.InjectedBodyField) !void {
    try writer.writeAll("{");
    if (field.is_array) {
        try writeFieldName(writer, "type");
        try writeJsonString(writer, "array");
        try writer.writeAll(",");
        try writeFieldName(writer, "items");
        try writeSchema(writer, arrayItemSchemaType(field.schema_type), field.schema_format, false, &.{});
    } else {
        try writeFieldName(writer, "type");
        try writeJsonString(writer, field.schema_type);
        if (field.schema_format) |fmt| {
            try writer.writeAll(",");
            try writeFieldName(writer, "format");
            try writeJsonString(writer, fmt);
        }
    }

    if (field.description) |description| {
        try writer.writeAll(",");
        try writeFieldName(writer, "description");
        try writeJsonString(writer, description);
    }
    try writeSchemaConstraints(
        writer,
        field.gt,
        field.ge,
        field.lt,
        field.le,
        field.min_length,
        field.max_length,
        field.pattern,
        field.enum_values,
        field.strict,
    );
    try writer.writeAll("}");
}

fn writeSchemaConstraints(
    writer: anytype,
    gt: ?f64,
    ge: ?f64,
    lt: ?f64,
    le: ?f64,
    min_length: ?usize,
    max_length: ?usize,
    pattern: ?[]const u8,
    enum_values: []const []const u8,
    strict: bool,
) !void {
    if (gt) |value| {
        try writer.writeAll(",");
        try writeFieldName(writer, "exclusiveMinimum");
        try writer.print("{d}", .{value});
    }
    if (ge) |value| {
        try writer.writeAll(",");
        try writeFieldName(writer, "minimum");
        try writer.print("{d}", .{value});
    }
    if (lt) |value| {
        try writer.writeAll(",");
        try writeFieldName(writer, "exclusiveMaximum");
        try writer.print("{d}", .{value});
    }
    if (le) |value| {
        try writer.writeAll(",");
        try writeFieldName(writer, "maximum");
        try writer.print("{d}", .{value});
    }
    if (min_length) |value| {
        try writer.writeAll(",");
        try writeFieldName(writer, "minLength");
        try writer.print("{d}", .{value});
    }
    if (max_length) |value| {
        try writer.writeAll(",");
        try writeFieldName(writer, "maxLength");
        try writer.print("{d}", .{value});
    }
    if (pattern) |value| {
        try writer.writeAll(",");
        try writeFieldName(writer, "pattern");
        try writeJsonString(writer, value);
    }
    if (enum_values.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "enum");
        try writeStringArray(writer, enum_values);
    }
    if (strict) {
        try writer.writeAll(",");
        try writeFieldName(writer, "x-zigmund-strict");
        try writer.writeAll("true");
    }
}

fn countRequestBodyProperties(media_type: []const u8, specs: []const types.InjectedRequestBody) usize {
    var count: usize = 0;
    for (specs, 0..) |spec, spec_idx| {
        if (!std.ascii.eqlIgnoreCase(spec.media_type, media_type)) continue;
        for (spec.fields, 0..) |field, field_idx| {
            if (requestBodyFieldSeen(specs, media_type, spec_idx, field_idx, field.name)) continue;
            count += 1;
        }
    }
    return count;
}

fn countRequestBodyRequiredProperties(media_type: []const u8, specs: []const types.InjectedRequestBody) usize {
    var count: usize = 0;
    for (specs, 0..) |spec, spec_idx| {
        if (!std.ascii.eqlIgnoreCase(spec.media_type, media_type)) continue;
        for (spec.fields, 0..) |field, field_idx| {
            if (requestBodyFieldSeen(specs, media_type, spec_idx, field_idx, field.name)) continue;
            if (requestBodyFieldIsRequired(specs, media_type, field.name)) count += 1;
        }
    }
    return count;
}

fn requestBodyFieldSeen(
    specs: []const types.InjectedRequestBody,
    media_type: []const u8,
    spec_idx: usize,
    field_idx: usize,
    field_name: []const u8,
) bool {
    var i: usize = 0;
    while (i < spec_idx) : (i += 1) {
        const spec = specs[i];
        if (!std.ascii.eqlIgnoreCase(spec.media_type, media_type)) continue;
        for (spec.fields) |field| {
            if (std.mem.eql(u8, field.name, field_name)) return true;
        }
    }

    const spec = specs[spec_idx];
    if (!std.ascii.eqlIgnoreCase(spec.media_type, media_type)) return false;
    for (spec.fields[0..field_idx]) |field| {
        if (std.mem.eql(u8, field.name, field_name)) return true;
    }

    return false;
}

fn requestBodyFieldIsRequired(
    specs: []const types.InjectedRequestBody,
    media_type: []const u8,
    field_name: []const u8,
) bool {
    for (specs) |spec| {
        if (!std.ascii.eqlIgnoreCase(spec.media_type, media_type)) continue;
        for (spec.fields) |field| {
            if (!std.mem.eql(u8, field.name, field_name)) continue;
            if (field.required) return true;
        }
    }
    return false;
}

fn requestBodyMediaTypeSeen(previous: []const types.InjectedRequestBody, media_type: []const u8) bool {
    for (previous) |spec| {
        if (std.ascii.eqlIgnoreCase(spec.media_type, media_type)) return true;
    }
    return false;
}

fn writeOperationCallbacks(
    writer: anytype,
    allocator: std.mem.Allocator,
    callbacks: []const types.OpenApiCallback,
    operation_ids: *OperationIdRegistry,
) !void {
    try writer.writeAll("{");
    for (callbacks, 0..) |callback, idx| {
        if (idx != 0) try writer.writeAll(",");
        var owned_default_operation_id: ?[]u8 = null;
        defer {
            if (owned_default_operation_id) |value| allocator.free(value);
        }

        const operation_id = callback.operation_id orelse blk: {
            const generated = try buildDefaultOperationId(allocator, "callback", callback.name);
            owned_default_operation_id = generated;
            break :blk generated;
        };
        try writeJsonString(writer, callback.name);
        try writer.writeAll(":{");
        try writeJsonString(writer, callback.expression);
        try writer.writeAll(":{");
        try writeJsonString(writer, callback.method.asString());
        try writer.writeAll(":{");
        try writeCallbackOrWebhookOperationFields(writer, .{
            .operation_id = operation_id,
            .summary = callback.summary,
            .description = callback.description,
            .tags = callback.tags,
            .request_body_required = callback.request_body_required,
            .request_body_content_type = callback.request_body_content_type,
            .request_body_schema = callback.request_body_schema,
            .response_status = callback.response_status,
            .response_description = callback.response_description,
            .response_content_type = callback.response_content_type,
            .response_schema = callback.response_schema,
        }, operation_ids);
        try writer.writeAll("}}}");
    }
    try writer.writeAll("}");
}

fn writeWebhooks(
    writer: anytype,
    allocator: std.mem.Allocator,
    webhooks: []const types.OpenApiWebhook,
    operation_ids: *OperationIdRegistry,
) !void {
    try writer.writeAll("{");
    for (webhooks, 0..) |webhook, idx| {
        if (idx != 0) try writer.writeAll(",");
        var owned_default_operation_id: ?[]u8 = null;
        defer {
            if (owned_default_operation_id) |value| allocator.free(value);
        }

        const operation_id = webhook.operation_id orelse blk: {
            const generated = try buildDefaultOperationId(allocator, "webhook", webhook.name);
            owned_default_operation_id = generated;
            break :blk generated;
        };
        try writeJsonString(writer, webhook.name);
        try writer.writeAll(":{");
        try writeJsonString(writer, webhook.method.asString());
        try writer.writeAll(":{");
        try writeCallbackOrWebhookOperationFields(writer, .{
            .operation_id = operation_id,
            .summary = webhook.summary,
            .description = webhook.description,
            .tags = webhook.tags,
            .request_body_required = webhook.request_body_required,
            .request_body_content_type = webhook.request_body_content_type,
            .request_body_schema = webhook.request_body_schema,
            .response_status = webhook.response_status,
            .response_description = webhook.response_description,
            .response_content_type = webhook.response_content_type,
            .response_schema = webhook.response_schema,
        }, operation_ids);
        try writer.writeAll("}}");
    }
    try writer.writeAll("}");
}

fn writeCallbackOrWebhookOperationFields(
    writer: anytype,
    options: struct {
        operation_id: []const u8,
        summary: ?[]const u8,
        description: ?[]const u8,
        tags: []const []const u8,
        request_body_required: bool,
        request_body_content_type: []const u8,
        request_body_schema: ?types.OpenApiSchema,
        response_status: std.http.Status,
        response_description: ?[]const u8,
        response_content_type: []const u8,
        response_schema: ?types.OpenApiSchema,
    },
    operation_ids: *OperationIdRegistry,
) !void {
    const operation_id = try operation_ids.reserve(options.operation_id);
    try writeFieldName(writer, "operationId");
    try writeJsonString(writer, operation_id);

    if (options.summary) |summary| {
        try writer.writeAll(",");
        try writeFieldName(writer, "summary");
        try writeJsonString(writer, summary);
    }

    if (options.description) |description| {
        try writer.writeAll(",");
        try writeFieldName(writer, "description");
        try writeJsonString(writer, description);
    }

    if (options.tags.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "tags");
        try writeStringArray(writer, options.tags);
    }

    if (options.request_body_schema) |request_schema| {
        try writer.writeAll(",");
        try writeFieldName(writer, "requestBody");
        try writer.writeAll("{");
        try writeFieldName(writer, "required");
        try writer.writeAll(if (options.request_body_required) "true" else "false");
        try writer.writeAll(",");
        try writeFieldName(writer, "content");
        try writer.writeAll("{");
        try writeJsonString(writer, options.request_body_content_type);
        try writer.writeAll(":{\"schema\":");
        try writeOpenApiSchema(writer, request_schema);
        try writer.writeAll("}}");
        try writer.writeAll("}");
    }

    try writer.writeAll(",");
    try writeFieldName(writer, "responses");
    try writer.writeAll("{");
    var status_buf: [3]u8 = undefined;
    const status_str = try std.fmt.bufPrint(&status_buf, "{d}", .{@intFromEnum(options.response_status)});
    try writeJsonString(writer, status_str);
    try writer.writeAll(":{");
    try writeFieldName(writer, "description");
    try writeJsonString(writer, options.response_description orelse "Successful Response");
    if (options.response_schema) |response_schema| {
        try writer.writeAll(",");
        try writeFieldName(writer, "content");
        try writeResponseContent(writer, options.response_content_type, response_schema, &.{});
    }
    try writer.writeAll("}");
    try writer.writeAll("}");
}

fn writeResponsesObject(
    writer: anytype,
    allocator: std.mem.Allocator,
    options: types.StoredRouteOptions,
    response_component_name: ?[]const u8,
    response_entry_components: []const ResponseEntryComponent,
) !void {
    var entries: std.ArrayList(GeneratedResponseEntry) = .empty;
    defer entries.deinit(allocator);
    try appendGeneratedResponseEntries(allocator, &entries, options, response_component_name);

    try writer.writeAll("{");
    for (entries.items, 0..) |entry, idx| {
        if (idx != 0) try writer.writeAll(",");
        var status_buf: [3]u8 = undefined;
        const status_str = try std.fmt.bufPrint(&status_buf, "{d}", .{@intFromEnum(entry.status_code)});
        try writeJsonString(writer, status_str);
        try writer.writeAll(":");
        if (try responseEntryComponentName(allocator, entry, response_entry_components)) |component_name| {
            try writeComponentResponseRef(writer, component_name);
        } else {
            try writeResponseEntryValue(writer, allocator, entry);
        }
    }
    try writer.writeAll("}");
}

fn appendGeneratedResponseEntries(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(GeneratedResponseEntry),
    options: types.StoredRouteOptions,
    response_component_name: ?[]const u8,
) !void {
    const default_status = options.status_code orelse .ok;
    const response_model_schema = options.response_model_schema;
    const default_content_type = defaultResponseContentType(options);
    var has_default = false;

    for (options.responses) |spec| {
        if (spec.status_code == default_status) has_default = true;
        const applies_model_schema = response_model_schema != null and spec.status_code == default_status;
        const content_type = if (spec.content_type) |ct|
            ct
        else if (applies_model_schema or options.default_response_class != null)
            default_content_type
        else
            null;

        const examples = responseExamplesForStatusAndContentType(
            options.openapi_response_examples,
            spec.status_code,
            content_type orelse default_content_type,
        );

        try list.append(allocator, .{
            .status_code = spec.status_code,
            .description = spec.description orelse "Response",
            .content_type = content_type,
            .schema_opt = if (applies_model_schema and response_component_name == null) response_model_schema else null,
            .schema_component_name = if (applies_model_schema) response_component_name else null,
            .examples = examples,
        });
    }

    if (!has_default) {
        const default_examples = responseExamplesForStatusAndContentType(
            options.openapi_response_examples,
            default_status,
            default_content_type,
        );
        const default_content: ?[]const u8 = if (response_model_schema != null or default_examples.len > 0 or options.default_response_class != null)
            default_content_type
        else
            null;

        try list.append(allocator, .{
            .status_code = default_status,
            .description = "Successful Response",
            .content_type = default_content,
            .schema_opt = if (response_model_schema != null and response_component_name == null) response_model_schema else null,
            .schema_component_name = if (response_model_schema != null) response_component_name else null,
            .examples = default_examples,
        });
    }
}

fn writeResponseEntryValue(
    writer: anytype,
    allocator: std.mem.Allocator,
    entry: GeneratedResponseEntry,
) !void {
    try writer.writeAll("{");
    try writeFieldName(writer, "description");
    try writeJsonString(writer, entry.description);

    if (entry.content_type) |content_type| {
        try writer.writeAll(",");
        try writeFieldName(writer, "content");
        if (entry.schema_component_name) |schema_component_name| {
            try writeResponseContentRef(
                writer,
                allocator,
                content_type,
                schema_component_name,
                entry.examples,
            );
        } else {
            try writeResponseContent(
                writer,
                content_type,
                entry.schema_opt,
                entry.examples,
            );
        }
    }

    try writer.writeAll("}");
}

fn renderResponseEntryValueJson(
    allocator: std.mem.Allocator,
    entry: GeneratedResponseEntry,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var writer = out.writer(allocator);
    try writeResponseEntryValue(&writer, allocator, entry);
    return out.toOwnedSlice(allocator);
}

fn defaultResponseContentType(options: types.StoredRouteOptions) []const u8 {
    const class_name = options.default_response_class orelse return "application/json";

    if (std.ascii.eqlIgnoreCase(class_name, "PlainTextResponse")) return "text/plain; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(class_name, "HTMLResponse")) return "text/html; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(class_name, "FileResponse")) return "application/octet-stream";
    if (std.ascii.eqlIgnoreCase(class_name, "StreamingResponse")) return "application/octet-stream";
    if (std.ascii.eqlIgnoreCase(class_name, "EventSourceResponse")) return "text/event-stream; charset=utf-8";

    return "application/json";
}

fn responseExamplesForStatusAndContentType(
    specs: []const types.OpenApiResponseExamples,
    status_code: std.http.Status,
    content_type: []const u8,
) []const types.OpenApiExample {
    for (specs) |spec| {
        if (spec.status_code != status_code) continue;
        if (!std.ascii.eqlIgnoreCase(spec.content_type, content_type)) continue;
        return spec.examples;
    }
    return &.{};
}

fn writeResponseContent(
    writer: anytype,
    content_type: []const u8,
    schema_opt: ?types.OpenApiSchema,
    examples: []const types.OpenApiExample,
) !void {
    try writer.writeAll("{");
    try writeJsonString(writer, content_type);
    try writer.writeAll(":{\"schema\":");
    if (schema_opt) |schema| {
        try writeOpenApiSchema(writer, schema);
    } else {
        try writeSchema(writer, "string", null, false, &.{});
    }
    if (examples.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "examples");
        try writeOpenApiExamples(writer, examples);
    }
    try writer.writeAll("}}");
}

fn writeResponseContentRef(
    writer: anytype,
    allocator: std.mem.Allocator,
    content_type: []const u8,
    schema_component_name: []const u8,
    examples: []const types.OpenApiExample,
) !void {
    const ref_path = try allocSchemaRefPath(allocator, schema_component_name);
    defer allocator.free(ref_path);

    try writer.writeAll("{");
    try writeJsonString(writer, content_type);
    try writer.writeAll(":{\"schema\":{");
    try writeFieldName(writer, "$ref");
    try writeJsonString(writer, ref_path);
    try writer.writeAll("}");
    if (examples.len > 0) {
        try writer.writeAll(",");
        try writeFieldName(writer, "examples");
        try writeOpenApiExamples(writer, examples);
    }
    try writer.writeAll("}}");
}

fn allocSchemaRefPath(allocator: std.mem.Allocator, schema_component_name: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, "#/components/schemas/");
    for (schema_component_name) |ch| {
        switch (ch) {
            '~' => try out.appendSlice(allocator, "~0"),
            '/' => try out.appendSlice(allocator, "~1"),
            else => try out.append(allocator, ch),
        }
    }
    return out.toOwnedSlice(allocator);
}

fn pathParamCount(path: []const u8) usize {
    var idx: usize = 0;
    var count: usize = 0;
    while (std.mem.indexOfScalarPos(u8, path, idx, '{')) |start| {
        const end = std.mem.indexOfScalarPos(u8, path, start + 1, '}') orelse break;
        if (end > start + 1) count += 1;
        idx = end + 1;
    }
    return count;
}

fn countRouteSecurityRequirements(
    dependencies: []const types.DependencySpec,
    injected_dependencies: []const types.DependencySpec,
    security_schemes: []const security.NamedScheme,
) usize {
    var count: usize = 0;
    for (dependencies) |dep| {
        if (lookupSecurityScheme(security_schemes, dep.name) != null) count += 1;
    }
    for (injected_dependencies) |dep| {
        if (lookupSecurityScheme(security_schemes, dep.name) != null) count += 1;
    }
    return count;
}

fn writeRouteSecurity(
    writer: anytype,
    dependencies: []const types.DependencySpec,
    injected_dependencies: []const types.DependencySpec,
    security_schemes: []const security.NamedScheme,
) !void {
    try writer.writeAll("[");
    var wrote: usize = 0;
    for (dependencies) |dep| {
        if (lookupSecurityScheme(security_schemes, dep.name) == null) continue;
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;

        try writer.writeAll("{");
        try writeJsonString(writer, dep.name);
        try writer.writeAll(":");
        try writeStringArray(writer, dep.scopes);
        try writer.writeAll("}");
    }
    for (injected_dependencies) |dep| {
        if (lookupSecurityScheme(security_schemes, dep.name) == null) continue;
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;

        try writer.writeAll("{");
        try writeJsonString(writer, dep.name);
        try writer.writeAll(":");
        try writeStringArray(writer, dep.scopes);
        try writer.writeAll("}");
    }
    try writer.writeAll("]");
}

fn lookupSecurityScheme(
    security_schemes: []const security.NamedScheme,
    name: []const u8,
) ?security.NamedScheme {
    for (security_schemes) |scheme| {
        if (std.mem.eql(u8, scheme.name, name)) return scheme;
    }
    return null;
}

fn writeComponents(
    writer: anytype,
    security_schemes: []const security.NamedScheme,
    response_components: []const ComponentSchema,
    parameter_components: []const ParameterComponent,
    request_body_components: []const RequestBodyComponent,
    response_entry_components: []const ResponseEntryComponent,
) !void {
    try writer.writeAll("{");

    var wrote: usize = 0;
    if (security_schemes.len > 0) {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writeFieldName(writer, "securitySchemes");
        try writer.writeAll("{");
        for (security_schemes, 0..) |entry, idx| {
            if (idx != 0) try writer.writeAll(",");
            try writeJsonString(writer, entry.name);
            try writer.writeAll(":");
            try writeSecurityScheme(writer, entry.scheme);
        }
        try writer.writeAll("}");
    }

    if (response_components.len > 0) {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writeFieldName(writer, "schemas");
        try writer.writeAll("{");
        for (response_components, 0..) |entry, idx| {
            if (idx != 0) try writer.writeAll(",");
            try writeJsonString(writer, entry.name);
            try writer.writeAll(":");
            try writeOpenApiSchema(writer, entry.schema);
        }
        try writer.writeAll("}");
    }

    if (parameter_components.len > 0) {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writeFieldName(writer, "parameters");
        try writer.writeAll("{");
        for (parameter_components, 0..) |entry, idx| {
            if (idx != 0) try writer.writeAll(",");
            try writeJsonString(writer, entry.name);
            try writer.writeAll(":");
            try writeInjectedParameter(writer, entry.parameter);
        }
        try writer.writeAll("}");
    }

    if (request_body_components.len > 0) {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writeFieldName(writer, "requestBodies");
        try writer.writeAll("{");
        for (request_body_components, 0..) |entry, idx| {
            if (idx != 0) try writer.writeAll(",");
            try writeJsonString(writer, entry.name);
            try writer.writeAll(":");
            try writer.writeAll(entry.body_json);
        }
        try writer.writeAll("}");
    }

    if (response_entry_components.len > 0) {
        if (wrote != 0) try writer.writeAll(",");
        try writeFieldName(writer, "responses");
        try writer.writeAll("{");
        for (response_entry_components, 0..) |entry, idx| {
            if (idx != 0) try writer.writeAll(",");
            try writeJsonString(writer, entry.name);
            try writer.writeAll(":");
            try writer.writeAll(entry.response_json);
        }
        try writer.writeAll("}");
    }

    try writer.writeAll("}");
}

fn writeSecurityScheme(writer: anytype, scheme: security.OpenApiSecurityScheme) !void {
    try writer.writeAll("{");

    switch (scheme) {
        .api_key => |api_key| {
            try writeFieldName(writer, "type");
            try writeJsonString(writer, "apiKey");
            try writer.writeAll(",");
            try writeFieldName(writer, "name");
            try writeJsonString(writer, api_key.name);
            try writer.writeAll(",");
            try writeFieldName(writer, "in");
            try writeJsonString(writer, api_key.in.asString());
        },
        .http => |http| {
            try writeFieldName(writer, "type");
            try writeJsonString(writer, "http");
            try writer.writeAll(",");
            try writeFieldName(writer, "scheme");
            try writeJsonString(writer, http.scheme);
            if (http.bearer_format) |format| {
                try writer.writeAll(",");
                try writeFieldName(writer, "bearerFormat");
                try writeJsonString(writer, format);
            }
        },
        .oauth2 => |oauth2| {
            try writeFieldName(writer, "type");
            try writeJsonString(writer, "oauth2");
            try writer.writeAll(",");
            try writeFieldName(writer, "flows");
            try writeOAuthFlows(writer, oauth2.flows);
        },
        .openid_connect => |oidc| {
            try writeFieldName(writer, "type");
            try writeJsonString(writer, "openIdConnect");
            try writer.writeAll(",");
            try writeFieldName(writer, "openIdConnectUrl");
            try writeJsonString(writer, oidc.openid_connect_url);
        },
    }

    try writer.writeAll("}");
}

fn writeOAuthFlows(writer: anytype, flows: security.OAuthFlows) !void {
    try writer.writeAll("{");
    var wrote: usize = 0;

    if (flows.implicit) |flow| {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writeFieldName(writer, "implicit");
        try writeOAuthFlow(writer, flow);
    }
    if (flows.password) |flow| {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writeFieldName(writer, "password");
        try writeOAuthFlow(writer, flow);
    }
    if (flows.client_credentials) |flow| {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writeFieldName(writer, "clientCredentials");
        try writeOAuthFlow(writer, flow);
    }
    if (flows.authorization_code) |flow| {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writeFieldName(writer, "authorizationCode");
        try writeOAuthFlow(writer, flow);
    }

    try writer.writeAll("}");
}

fn writeOAuthFlow(writer: anytype, flow: security.OAuthFlow) !void {
    try writer.writeAll("{");
    var wrote: usize = 0;

    if (flow.authorization_url) |url| {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writeFieldName(writer, "authorizationUrl");
        try writeJsonString(writer, url);
    }
    if (flow.token_url) |url| {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writeFieldName(writer, "tokenUrl");
        try writeJsonString(writer, url);
    }
    if (flow.refresh_url) |url| {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;
        try writeFieldName(writer, "refreshUrl");
        try writeJsonString(writer, url);
    }

    if (wrote != 0) try writer.writeAll(",");
    try writeFieldName(writer, "scopes");
    try writeScopeMap(writer, flow.scopes);

    try writer.writeAll("}");
}

fn writeScopeMap(writer: anytype, scopes: []const security.Scope) !void {
    try writer.writeAll("{");
    for (scopes, 0..) |scope, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writeJsonString(writer, scope.name);
        try writer.writeAll(":");
        try writeJsonString(writer, scope.description orelse "");
    }
    try writer.writeAll("}");
}

test "generate openapi with enriched metadata" {
    const fake_handler = struct {
        fn run(req: *@import("../http/request.zig").Request, allocator: std.mem.Allocator) !@import("../http/response.zig").Response {
            _ = req;
            _ = allocator;
            return @import("../http/response.zig").Response.text("ok");
        }
    };

    var router = router_mod.Router.init(std.testing.allocator);
    defer router.deinit();

    try router.addHttpRoute(.GET, "/items/{item_id}", fake_handler.run, .{
        .summary = "Read item",
        .tags = &.{"items"},
        .dependencies = &.{.{ .name = "auth", .scopes = &.{"items:read"} }},
        .responses = &.{.{
            .status_code = .created,
            .description = "Created",
            .content_type = "application/json",
        }},
        .response_model = []const u8,
    });

    const schemes = [_]security.NamedScheme{
        .{ .name = "auth", .scheme = .{ .http = .{ .scheme = "bearer", .bearer_format = "JWT" } } },
    };

    const doc = try generate(
        std.testing.allocator,
        .{
            .title = "Zigmund",
            .version = "0.1.0",
        },
        router.httpRoutes(),
        router.websocketRoutes(),
        &schemes,
    );
    defer std.testing.allocator.free(doc);

    try std.testing.expect(std.mem.indexOf(u8, doc, "\"tags\":[\"items\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"x-zigmund-dependencies\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"parameters\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"201\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"securitySchemes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"security\"") != null);
}
