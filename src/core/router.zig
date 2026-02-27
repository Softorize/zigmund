const std = @import("std");
const types = @import("types.zig");
const injector = @import("injector.zig");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const websocket = @import("../runtime/websocket.zig");

pub const HttpHandler = *const fn (*Request, std.mem.Allocator) anyerror!Response;
pub const WebSocketHandler = *const fn (*websocket.Connection, *Request, std.mem.Allocator) anyerror!void;

pub const HttpRoute = struct {
    method: types.RouteMethod,
    path: []const u8,
    handler: HttpHandler,
    options: types.StoredRouteOptions,
};

pub const WebSocketRoute = struct {
    path: []const u8,
    handler: WebSocketHandler,
    options: types.WebSocketRouteOptions,
    injected_dependencies: []const types.DependencySpec = &.{},
};

pub const Router = struct {
    allocator: std.mem.Allocator,
    http_routes: std.ArrayListUnmanaged(HttpRoute) = .empty,
    websocket_routes: std.ArrayListUnmanaged(WebSocketRoute) = .empty,

    pub fn init(allocator: std.mem.Allocator) Router {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Router) void {
        for (self.http_routes.items) |route| {
            self.allocator.free(route.path);
        }
        self.http_routes.deinit(self.allocator);

        for (self.websocket_routes.items) |route| {
            self.allocator.free(route.path);
        }
        self.websocket_routes.deinit(self.allocator);
    }

    pub fn addHttpRoute(
        self: *Router,
        method: types.RouteMethod,
        path: []const u8,
        handler: anytype,
        opts: types.RouteOptions,
    ) !void {
        const canonical = try canonicalizePath(path);
        const owned_path = try self.allocator.dupe(u8, canonical);
        errdefer self.allocator.free(owned_path);

        var stored_opts = types.storeRouteOptions(opts);
        stored_opts.injected_dependencies = injector.deriveOpenApiDependencies(handler);
        stored_opts.injected_parameters = injector.deriveOpenApiParameters(handler);
        stored_opts.injected_request_bodies = injector.deriveOpenApiRequestBodies(handler);
        try self.http_routes.append(self.allocator, .{
            .method = method,
            .path = owned_path,
            .handler = normalizeHttpHandler(handler),
            .options = stored_opts,
        });
    }

    pub fn addHttpRouteStored(
        self: *Router,
        method: types.RouteMethod,
        path: []const u8,
        handler: HttpHandler,
        opts: types.StoredRouteOptions,
    ) !void {
        const canonical = try canonicalizePath(path);
        const owned_path = try self.allocator.dupe(u8, canonical);
        errdefer self.allocator.free(owned_path);

        try self.http_routes.append(self.allocator, .{
            .method = method,
            .path = owned_path,
            .handler = handler,
            .options = opts,
        });
    }

    pub fn addWebSocketRoute(self: *Router, path: []const u8, handler: anytype, opts: types.WebSocketRouteOptions) !void {
        const canonical = try canonicalizePath(path);
        const owned_path = try self.allocator.dupe(u8, canonical);
        errdefer self.allocator.free(owned_path);

        try self.websocket_routes.append(self.allocator, .{
            .path = owned_path,
            .handler = normalizeWebSocketHandler(handler),
            .options = opts,
            .injected_dependencies = injector.deriveOpenApiDependencies(handler),
        });
    }

    pub fn addWebSocketRouteStored(
        self: *Router,
        path: []const u8,
        handler: WebSocketHandler,
        opts: types.WebSocketRouteOptions,
        injected_dependencies: []const types.DependencySpec,
    ) !void {
        const canonical = try canonicalizePath(path);
        const owned_path = try self.allocator.dupe(u8, canonical);
        errdefer self.allocator.free(owned_path);

        try self.websocket_routes.append(self.allocator, .{
            .path = owned_path,
            .handler = handler,
            .options = opts,
            .injected_dependencies = injected_dependencies,
        });
    }

    pub fn httpRoutes(self: *const Router) []const HttpRoute {
        return self.http_routes.items;
    }

    pub fn websocketRoutes(self: *const Router) []const WebSocketRoute {
        return self.websocket_routes.items;
    }

    pub fn findHttp(self: *const Router, request: *Request) !?*const HttpRoute {
        const route_method = types.RouteMethod.fromHttpMethod(request.method) orelse return null;

        for (self.http_routes.items) |*route| {
            request.path_params.clearRetainingCapacity();
            if (route.method != route_method) continue;
            if (try matchPath(route.path, request.path, request)) {
                return route;
            }
        }

        request.path_params.clearRetainingCapacity();
        return null;
    }

    pub fn findWebSocket(self: *const Router, path: []const u8, request: *Request) !?*const WebSocketRoute {
        for (self.websocket_routes.items) |*route| {
            request.path_params.clearRetainingCapacity();
            if (try matchPath(route.path, path, request)) {
                return route;
            }
        }

        request.path_params.clearRetainingCapacity();
        return null;
    }

    fn canonicalizePath(path: []const u8) ![]const u8 {
        if (path.len == 0 or path[0] != '/') return error.InvalidPath;

        var end = path.len;
        while (end > 1 and path[end - 1] == '/') {
            end -= 1;
        }
        return path[0..end];
    }

    fn trimSlashes(path: []const u8) []const u8 {
        var start: usize = 0;
        var end = path.len;

        while (start < end and path[start] == '/') start += 1;
        while (end > start and path[end - 1] == '/') end -= 1;

        return path[start..end];
    }

    const Segment = struct {
        value: []const u8,
        start: usize,
        end: usize,
    };

    const ParamKind = enum {
        single,
        path,
    };

    const ParamSpec = struct {
        name: []const u8,
        kind: ParamKind,
    };

    fn isParamSegment(segment: []const u8) bool {
        return segment.len >= 3 and segment[0] == '{' and segment[segment.len - 1] == '}';
    }

    fn parseParamSegment(segment: []const u8) ?ParamSpec {
        if (!isParamSegment(segment)) return null;

        const inner = std.mem.trim(u8, segment[1 .. segment.len - 1], " \t");
        if (inner.len == 0) return null;

        if (std.mem.indexOfScalar(u8, inner, ':')) |colon_idx| {
            const name = std.mem.trim(u8, inner[0..colon_idx], " \t");
            if (name.len == 0) return null;

            const converter = std.mem.trim(u8, inner[colon_idx + 1 ..], " \t");
            if (std.mem.eql(u8, converter, "path")) {
                return .{
                    .name = name,
                    .kind = .path,
                };
            }

            return .{
                .name = name,
                .kind = .single,
            };
        }

        return .{
            .name = inner,
            .kind = .single,
        };
    }

    fn nextSegment(path: []const u8, idx: *usize) ?Segment {
        if (idx.* >= path.len) return null;

        const start = idx.*;
        var end = start;
        while (end < path.len and path[end] != '/') : (end += 1) {}

        idx.* = if (end < path.len) end + 1 else end;
        return .{
            .value = path[start..end],
            .start = start,
            .end = end,
        };
    }

    fn matchPath(pattern: []const u8, concrete: []const u8, request: *Request) !bool {
        const pattern_trimmed = trimSlashes(pattern);
        const concrete_trimmed = trimSlashes(concrete);

        var pattern_idx: usize = 0;
        var concrete_idx: usize = 0;

        while (true) {
            const pattern_seg = nextSegment(pattern_trimmed, &pattern_idx);
            const concrete_seg = nextSegment(concrete_trimmed, &concrete_idx);

            if (pattern_seg == null and concrete_seg == null) return true;
            if (pattern_seg == null or concrete_seg == null) return false;

            const p = pattern_seg.?;
            const c = concrete_seg.?;

            if (parseParamSegment(p.value)) |param| {
                switch (param.kind) {
                    .single => {
                        try request.setPathParam(param.name, c.value);
                        continue;
                    },
                    .path => {
                        var probe_idx = pattern_idx;
                        const has_more_pattern_segments = nextSegment(pattern_trimmed, &probe_idx) != null;
                        if (has_more_pattern_segments) return false;

                        const remaining = concrete_trimmed[c.start..];
                        try request.setPathParam(param.name, remaining);
                        return true;
                    },
                }
            }

            if (!std.mem.eql(u8, p.value, c.value)) return false;
        }
    }

    fn normalizeHttpHandler(handler: anytype) HttpHandler {
        const T = @TypeOf(handler);
        if (T == HttpHandler) return handler;
        if (@typeInfo(T) == .@"fn") {
            if (comptime isDirectHttpHandlerType(T)) {
                const ptr: HttpHandler = &handler;
                return ptr;
            }
            return injector.bindHttpHandler(handler);
        }
        @compileError("HTTP handler must be fn(*Request, std.mem.Allocator) !Response");
    }

    fn normalizeWebSocketHandler(handler: anytype) WebSocketHandler {
        const T = @TypeOf(handler);
        if (T == WebSocketHandler) return handler;
        if (@typeInfo(T) == .@"fn") {
            if (comptime isDirectWebSocketHandlerType(T)) {
                const ptr: WebSocketHandler = &handler;
                return ptr;
            }
            if (comptime isLegacyWebSocketHandlerType(T)) {
                return adaptLegacyWebSocketHandler(handler);
            }
            return injector.bindWebSocketHandler(handler);
        }
        @compileError(
            "WebSocket handler must be fn(*websocket.Connection, *Request, std.mem.Allocator) !void or fn(*websocket.Connection, std.mem.Allocator) !void",
        );
    }

    fn adaptLegacyWebSocketHandler(comptime handler: anytype) WebSocketHandler {
        const Legacy = struct {
            fn run(conn: *websocket.Connection, req: *Request, allocator: std.mem.Allocator) anyerror!void {
                _ = req;
                return @call(.auto, handler, .{ conn, allocator });
            }
        };
        return Legacy.run;
    }

    fn isDirectWebSocketHandlerType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 3) return false;
        if (info.params[0].type != *websocket.Connection) return false;
        if (info.params[1].type != *Request) return false;
        if (info.params[2].type != std.mem.Allocator) return false;
        if (info.return_type == null) return false;

        const ret = info.return_type.?;
        if (@typeInfo(ret) == .error_union) {
            return @typeInfo(ret).error_union.payload == void;
        }
        return ret == void;
    }

    fn isLegacyWebSocketHandlerType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 2) return false;
        if (info.params[0].type != *websocket.Connection) return false;
        if (info.params[1].type != std.mem.Allocator) return false;
        if (info.return_type == null) return false;

        const ret = info.return_type.?;
        if (@typeInfo(ret) == .error_union) {
            return @typeInfo(ret).error_union.payload == void;
        }
        return ret == void;
    }

    fn isDirectHttpHandlerType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 2) return false;
        if (info.params[0].type != *Request) return false;
        if (info.params[1].type != std.mem.Allocator) return false;
        if (info.return_type == null) return false;

        const ret = info.return_type.?;
        if (@typeInfo(ret) == .error_union) {
            return @typeInfo(ret).error_union.payload == Response;
        }
        return ret == Response;
    }
};

test "path params are captured" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const H = struct {
        fn handler(req: *Request, allocator: std.mem.Allocator) !Response {
            _ = req;
            _ = allocator;
            return Response.text("ok");
        }
    };

    try router.addHttpRoute(.GET, "/items/{item_id}", H.handler, .{});

    var req = try Request.initSynthetic(std.testing.allocator, .GET, "/items/abc", "");
    defer req.deinit();

    const matched = try router.findHttp(&req);
    try std.testing.expect(matched != null);
    try std.testing.expectEqualStrings("abc", req.param("item_id").?);
}

test "path converter captures trailing slash-delimited segments" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const H = struct {
        fn handler(req: *Request, allocator: std.mem.Allocator) !Response {
            _ = req;
            _ = allocator;
            return Response.text("ok");
        }
    };

    try router.addHttpRoute(.GET, "/files/{file_path:path}", H.handler, .{});

    var req = try Request.initSynthetic(std.testing.allocator, .GET, "/files/css/app/site.css", "");
    defer req.deinit();

    const matched = try router.findHttp(&req);
    try std.testing.expect(matched != null);
    try std.testing.expectEqualStrings("css/app/site.css", req.param("file_path").?);
}
