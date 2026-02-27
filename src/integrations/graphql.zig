const std = @import("std");
const core = @import("../core/mod.zig");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const GraphQlExecutor = *const fn (
    query: []const u8,
    operation_name: ?[]const u8,
    variables_json: ?[]const u8,
    req: *Request,
    allocator: std.mem.Allocator,
) anyerror!Response;

pub const GraphQlOptions = struct {
    allow_get: bool = true,
    playground: bool = true,
    include_in_schema: bool = true,
};

pub const GraphQlIntegration = struct {
    endpoint: []const u8,
    options: GraphQlOptions = .{},

    pub fn init(endpoint: []const u8) GraphQlIntegration {
        return .{
            .endpoint = endpoint,
            .options = .{},
        };
    }

    pub fn withOptions(self: GraphQlIntegration, options: GraphQlOptions) GraphQlIntegration {
        var next = self;
        next.options = options;
        return next;
    }

    pub fn mount(self: GraphQlIntegration, app: *core.App, executor: anytype) !void {
        try mountGraphQl(app, self.endpoint, executor, self.options);
    }
};

const Registration = struct {
    endpoint: []u8,
    executor: GraphQlExecutor,
    options: GraphQlOptions,
};

var registrations: std.ArrayListUnmanaged(Registration) = .empty;
var registrations_lock: std.Thread.Mutex = .{};

pub fn mountGraphQl(
    app: *core.App,
    endpoint: []const u8,
    executor: anytype,
    options: GraphQlOptions,
) !void {
    if (endpoint.len == 0 or endpoint[0] != '/') return error.InvalidEndpoint;

    const normalized_executor = normalizeExecutor(executor);
    try registerEndpoint(endpoint, normalized_executor, options);

    if (options.include_in_schema) {
        try app.post(endpoint, graphQlPostHandler, .{
            .summary = "GraphQL endpoint",
        });
    } else {
        try app.post(endpoint, graphQlPostHandler, .{
            .summary = "GraphQL endpoint",
            .include_in_schema = false,
        });
    }

    if (options.allow_get) {
        if (options.include_in_schema) {
            try app.get(endpoint, graphQlGetHandler, .{
                .summary = "GraphQL endpoint",
            });
        } else {
            try app.get(endpoint, graphQlGetHandler, .{
                .summary = "GraphQL endpoint",
                .include_in_schema = false,
            });
        }
    }
}

pub fn clearRegistrationsForTesting() void {
    const allocator = std.heap.page_allocator;
    registrations_lock.lock();
    defer registrations_lock.unlock();

    for (registrations.items) |entry| {
        allocator.free(entry.endpoint);
    }
    registrations.deinit(allocator);
    registrations = .empty;
}

fn graphQlPostHandler(req: *Request, allocator: std.mem.Allocator) !Response {
    const reg = findRegistration(req.path) orelse return Response.text("not found").withStatus(.not_found);

    const content_type = req.header("content-type") orelse "";
    if (startsWithMediaType(content_type, "application/graphql")) {
        return reg.executor(req.body, req.queryParam("operationName"), null, req, allocator);
    }

    if (!startsWithMediaType(content_type, "application/json")) {
        return Response.text("unsupported media type").withStatus(.unsupported_media_type);
    }

    const payload = std.json.parseFromSlice(std.json.Value, allocator, req.body, .{}) catch {
        return Response.text("invalid graphql payload").withStatus(.bad_request);
    };
    defer payload.deinit();

    const root = payload.value;
    if (root != .object) {
        return Response.text("invalid graphql payload").withStatus(.bad_request);
    }

    const query_val = root.object.get("query") orelse return Response.text("query is required").withStatus(.bad_request);
    if (query_val != .string) return Response.text("query must be string").withStatus(.bad_request);
    const query = query_val.string;

    const operation_name: ?[]const u8 = blk: {
        const op = root.object.get("operationName") orelse break :blk null;
        if (op == .string) break :blk op.string;
        break :blk null;
    };

    var owned_variables_json: ?[]u8 = null;
    defer if (owned_variables_json) |vars| allocator.free(vars);

    const variables_json: ?[]const u8 = blk: {
        const vars = root.object.get("variables") orelse break :blk null;
        const encoded = std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(vars, .{})}) catch {
            return Response.text("invalid variables").withStatus(.bad_request);
        };
        owned_variables_json = encoded;
        break :blk encoded;
    };

    return reg.executor(query, operation_name, variables_json, req, allocator);
}

fn graphQlGetHandler(req: *Request, allocator: std.mem.Allocator) !Response {
    const reg = findRegistration(req.path) orelse return Response.text("not found").withStatus(.not_found);

    if (req.queryParam("query")) |query| {
        return reg.executor(
            query,
            req.queryParam("operationName"),
            req.queryParam("variables"),
            req,
            allocator,
        );
    }

    if (!reg.options.playground) {
        return Response.text("query is required").withStatus(.bad_request);
    }

    const page = try std.fmt.allocPrint(
        allocator,
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>GraphQL</title></head>" ++
            "<body><h1>GraphQL Playground</h1><p>POST queries to <code>{s}</code>.</p></body></html>",
        .{reg.endpoint},
    );

    return .{
        .status = .ok,
        .body = page,
        .content_type = "text/html; charset=utf-8",
        .owned_body = page,
    };
}

fn normalizeExecutor(executor: anytype) GraphQlExecutor {
    const T = @TypeOf(executor);
    if (T == GraphQlExecutor) return executor;
    if (@typeInfo(T) == .@"fn") {
        const ptr: GraphQlExecutor = &executor;
        return ptr;
    }
    @compileError(
        "GraphQL executor must be fn([]const u8, ?[]const u8, ?[]const u8, *Request, std.mem.Allocator) !Response",
    );
}

fn registerEndpoint(endpoint: []const u8, executor: GraphQlExecutor, options: GraphQlOptions) !void {
    const allocator = std.heap.page_allocator;

    registrations_lock.lock();
    defer registrations_lock.unlock();

    for (registrations.items) |*entry| {
        if (!std.mem.eql(u8, entry.endpoint, endpoint)) continue;
        entry.executor = executor;
        entry.options = options;
        return;
    }

    const owned_endpoint = try allocator.dupe(u8, endpoint);
    errdefer allocator.free(owned_endpoint);

    try registrations.append(allocator, .{
        .endpoint = owned_endpoint,
        .executor = executor,
        .options = options,
    });
}

fn findRegistration(path: []const u8) ?Registration {
    registrations_lock.lock();
    defer registrations_lock.unlock();

    for (registrations.items) |entry| {
        if (std.mem.eql(u8, entry.endpoint, path)) return entry;
    }
    return null;
}

fn startsWithMediaType(content_type: []const u8, media_type: []const u8) bool {
    const token = mediaTypeToken(content_type);
    return std.ascii.eqlIgnoreCase(token, media_type);
}

fn mediaTypeToken(content_type: []const u8) []const u8 {
    const semi = std.mem.indexOfScalar(u8, content_type, ';') orelse content_type.len;
    return std.mem.trim(u8, content_type[0..semi], " \t");
}

test "graphql mount supports json post payload and playground get" {
    clearRegistrationsForTesting();
    defer clearRegistrationsForTesting();

    var app = try core.App.init(std.testing.allocator, .{
        .title = "graphql",
        .version = "0.0.1",
    });
    defer app.deinit();

    const Exec = struct {
        fn run(
            query: []const u8,
            operation_name: ?[]const u8,
            variables_json: ?[]const u8,
            req: *Request,
            allocator: std.mem.Allocator,
        ) !Response {
            _ = req;
            return Response.json(allocator, .{
                .query = query,
                .operation_name = operation_name orelse "",
                .variables = variables_json orelse "",
            });
        }
    };

    try mountGraphQl(&app, "/graphql", Exec.run, .{});

    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = "application/json" },
    };

    const body =
        \\{"query":"query Ping { ping }","operationName":"Ping","variables":{"region":"us"}}
    ;
    var post_res = try app.dispatchSyntheticWithHeaders(.POST, "/graphql", body, &headers);
    defer post_res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, post_res.status);
    try std.testing.expect(std.mem.indexOf(u8, post_res.body, "\"query\":\"query Ping { ping }\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, post_res.body, "\"operation_name\":\"Ping\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, post_res.body, "\"variables\":\"{\\\"region\\\":\\\"us\\\"}\"") != null);

    var get_res = try app.dispatchSynthetic(.GET, "/graphql", "");
    defer get_res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, get_res.status);
    try std.testing.expectEqualStrings("text/html; charset=utf-8", get_res.content_type);
    try std.testing.expect(std.mem.indexOf(u8, get_res.body, "GraphQL Playground") != null);
}
