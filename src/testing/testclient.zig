const std = @import("std");
const App = @import("../core/app.zig").App;
const router_mod = @import("../core/router.zig");
const types = @import("../core/types.zig");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const websocket = @import("../runtime/websocket.zig");

pub const TestClient = struct {
    allocator: std.mem.Allocator,
    app: *App,
    cookies: std.ArrayListUnmanaged(CookieEntry) = .empty,
    lifespan_started: bool = false,

    const CookieEntry = struct {
        name: []u8,
        value: []u8,
    };

    const EffectiveHeaders = struct {
        headers: []const std.http.Header,
        owned_cookie_header: ?[]u8 = null,
        owned_headers: ?[]std.http.Header = null,

        fn deinit(self: *EffectiveHeaders, allocator: std.mem.Allocator) void {
            if (self.owned_cookie_header) |cookie_header| allocator.free(cookie_header);
            if (self.owned_headers) |merged| allocator.free(merged);
            self.* = .{ .headers = &.{} };
        }
    };

    const RuntimeDependencies = struct {
        items: []const types.DependencySpec,
        owned: bool = false,
    };

    const WebSocketSessionState = struct {
        allocator: std.mem.Allocator,
        handler: router_mod.WebSocketHandler,
        req: Request,
        duplex: websocket.TestDuplex,
        client_conn: websocket.Connection,
        idle_timeout_ms: ?u64 = null,
        auto_pong: bool = true,
        ping_interval_ms: ?u64 = null,
        pong_timeout_ms: ?u64 = null,
        max_message_bytes: ?usize = null,
        max_pending_messages: ?usize = null,
        send_timeout_ms: ?u64 = null,
        negotiated_subprotocol: ?[]const u8 = null,
        thread: std.Thread,
        thread_err: ?anyerror = null,
        joined: bool = false,
        closed: bool = false,
    };

    pub const WebSocketSession = struct {
        allocator: std.mem.Allocator,
        state: *WebSocketSessionState,

        pub fn sendText(self: *WebSocketSession, payload: []const u8) !void {
            try self.state.client_conn.sendText(payload);
        }

        pub fn sendBinary(self: *WebSocketSession, payload: []const u8) !void {
            try self.state.client_conn.sendBinary(payload);
        }

        pub fn ping(self: *WebSocketSession, payload: []const u8) !void {
            try self.state.client_conn.ping(payload);
        }

        pub fn receiveSmall(self: *WebSocketSession) !websocket.Connection.Message {
            return self.state.client_conn.receiveSmall();
        }

        pub fn receiveSmallWithTimeout(self: *WebSocketSession, timeout_ms: u64) !websocket.Connection.Message {
            return self.state.client_conn.receiveSmallWithTimeout(timeout_ms);
        }

        pub fn subprotocol(self: *const WebSocketSession) ?[]const u8 {
            return self.state.client_conn.subprotocol();
        }

        pub fn lastCloseCode(self: *const WebSocketSession) ?u16 {
            return self.state.client_conn.lastCloseCode();
        }

        pub fn close(self: *WebSocketSession) void {
            if (self.state.closed) return;
            self.state.closed = true;
            _ = self.state.client_conn.closeWithCode(1000, "") catch |err| {
                std.log.debug("WebSocket close failed: {s}", .{@errorName(err)});
            };
            self.state.duplex.close();
        }

        pub fn closeWithCode(self: *WebSocketSession, code: u16, reason: []const u8) !void {
            if (self.state.closed) return;
            self.state.closed = true;
            try self.state.client_conn.closeWithCode(code, reason);
            self.state.duplex.close();
        }

        pub fn handlerError(self: *const WebSocketSession) ?anyerror {
            return self.state.thread_err;
        }

        pub fn deinit(self: *WebSocketSession) void {
            self.close();
            if (!self.state.joined) {
                self.state.thread.join();
                self.state.joined = true;
            }

            self.state.client_conn.deinit(self.allocator);
            self.state.req.deinit();
            self.state.duplex.deinit();
            self.allocator.destroy(self.state);
        }
    };

    pub fn init(allocator: std.mem.Allocator, app: *App) TestClient {
        return .{
            .allocator = allocator,
            .app = app,
        };
    }

    pub fn deinit(self: *TestClient) void {
        self.close() catch |err| {
            std.log.err("test client shutdown lifecycle failed: {s}", .{@errorName(err)});
        };
        self.clearCookies();
        self.cookies.deinit(self.allocator);
    }

    pub fn start(self: *TestClient) !void {
        if (self.lifespan_started) return;
        try self.app.runStartupHooksOnly();
        self.lifespan_started = true;
    }

    pub fn close(self: *TestClient) !void {
        if (!self.lifespan_started) return;
        try self.app.runShutdownHooksOnly();
        self.lifespan_started = false;
    }

    pub fn request(self: *TestClient, method: std.http.Method, target: []const u8, body: []const u8) !Response {
        return self.requestWithHeaders(method, target, body, &.{});
    }

    pub fn requestWithHeaders(
        self: *TestClient,
        method: std.http.Method,
        target: []const u8,
        body: []const u8,
        headers: []const std.http.Header,
    ) !Response {
        try self.start();
        if (headers.len == 0 and self.cookies.items.len == 0) {
            var direct = try self.app.dispatchSynthetic(method, target, body);
            self.applySetCookieHeaders(&direct) catch |err| {
                direct.deinit(self.allocator);
                return err;
            };
            return direct;
        }

        var effective = try self.effectiveHeaders(headers);
        defer effective.deinit(self.allocator);

        var response = try self.app.dispatchSyntheticWithHeaders(method, target, body, effective.headers);
        self.applySetCookieHeaders(&response) catch |err| {
            response.deinit(self.allocator);
            return err;
        };
        return response;
    }

    pub fn websocketConnect(self: *TestClient, target: []const u8) !WebSocketSession {
        return self.websocketConnectWithHeaders(target, &.{});
    }

    pub fn websocketConnectWithHeaders(
        self: *TestClient,
        target: []const u8,
        headers: []const std.http.Header,
    ) !WebSocketSession {
        try self.start();
        var effective = try self.effectiveHeaders(headers);
        defer effective.deinit(self.allocator);

        var req = try Request.initSyntheticWithHeaders(self.allocator, .GET, target, "", effective.headers);
        var req_moved_to_state = false;
        defer if (!req_moved_to_state) req.deinit();
        defer if (!req_moved_to_state) req.runDependencyCleanups(self.allocator) catch |err| {
            std.log.err("dependency cleanup failed: {s}", .{@errorName(err)});
        };

        const ws_route = try self.app.router.findWebSocket(req.path, &req) orelse return error.WebSocketRouteNotFound;

        const runtime_deps = try self.buildRuntimeDependencies(
            ws_route.options.dependencies,
            ws_route.injected_dependencies,
        );
        defer if (runtime_deps.owned) self.allocator.free(runtime_deps.items);

        try self.app.dependency_registry.runRouteDependencies(&req, runtime_deps.items, self.allocator);

        if (!isWebSocketOriginAllowed(req.header("origin"), ws_route.options.allowed_origins)) {
            return error.WebSocketOriginForbidden;
        }

        const selected_subprotocol = selectWebSocketSubprotocol(
            req.header("sec-websocket-protocol"),
            ws_route.options.subprotocols,
        );
        if (ws_route.options.subprotocols.len > 0 and
            ws_route.options.require_subprotocol and
            selected_subprotocol == null)
        {
            return error.WebSocketSubprotocolRequired;
        }

        const state = try self.allocator.create(WebSocketSessionState);
        errdefer self.allocator.destroy(state);

        state.* = .{
            .allocator = self.allocator,
            .handler = ws_route.handler,
            .req = req,
            .duplex = websocket.TestDuplex.init(self.allocator),
            .client_conn = undefined,
            .idle_timeout_ms = ws_route.options.idle_timeout_ms,
            .auto_pong = ws_route.options.auto_pong,
            .ping_interval_ms = ws_route.options.ping_interval_ms,
            .pong_timeout_ms = ws_route.options.pong_timeout_ms,
            .max_message_bytes = ws_route.options.max_message_bytes,
            .max_pending_messages = ws_route.options.max_pending_messages,
            .send_timeout_ms = ws_route.options.send_timeout_ms,
            .negotiated_subprotocol = selected_subprotocol,
            .thread = undefined,
        };
        req_moved_to_state = true;

        state.duplex.setMaxPendingMessages(ws_route.options.max_pending_messages);
        state.client_conn = websocket.Connection.initTest(state.duplex.clientEndpoint());
        state.client_conn.setAutoPong(ws_route.options.auto_pong);
        state.client_conn.setSendTimeoutMs(ws_route.options.send_timeout_ms);
        state.client_conn.setNegotiatedSubprotocol(selected_subprotocol);
        errdefer {
            state.duplex.close();
            state.req.runDependencyCleanups(self.allocator) catch |err| {
                std.log.err("dependency cleanup failed: {s}", .{@errorName(err)});
            };
            state.client_conn.deinit(self.allocator);
            state.req.deinit();
            state.duplex.deinit();
            self.allocator.destroy(state);
        }

        state.thread = try std.Thread.spawn(.{}, runWebSocketSession, .{state});

        return .{
            .allocator = self.allocator,
            .state = state,
        };
    }

    pub fn get(self: *TestClient, target: []const u8) !Response {
        return self.request(.GET, target, "");
    }

    pub fn post(self: *TestClient, target: []const u8, body: []const u8) !Response {
        return self.request(.POST, target, body);
    }

    pub fn postWithHeaders(self: *TestClient, target: []const u8, body: []const u8, headers: []const std.http.Header) !Response {
        return self.requestWithHeaders(.POST, target, body, headers);
    }

    pub fn clearCookies(self: *TestClient) void {
        for (self.cookies.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.value);
        }
        self.cookies.clearRetainingCapacity();
    }

    pub fn cookie(self: *const TestClient, name: []const u8) ?[]const u8 {
        for (self.cookies.items) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.value;
        }
        return null;
    }

    fn runWebSocketSession(state: *WebSocketSessionState) void {
        defer state.duplex.close();
        defer state.req.runDependencyCleanups(state.allocator) catch |err| {
            std.log.err("dependency cleanup failed: {s}", .{@errorName(err)});
        };

        var server_conn = websocket.Connection.initTest(state.duplex.serverEndpoint());
        server_conn.setIdleTimeoutMs(state.idle_timeout_ms);
        server_conn.setAutoPong(state.auto_pong);
        server_conn.setPingPolicy(state.ping_interval_ms, state.pong_timeout_ms);
        server_conn.setMaxMessageBytes(state.max_message_bytes);
        server_conn.setSendTimeoutMs(state.send_timeout_ms);
        server_conn.setNegotiatedSubprotocol(state.negotiated_subprotocol);
        defer server_conn.deinit(state.allocator);

        state.handler(&server_conn, &state.req, state.allocator) catch |err| {
            if (err != error.ConnectionClosed) {
                state.thread_err = err;
                std.log.warn("test websocket handler failed: {s}", .{@errorName(err)});
            }
        };
    }

    fn buildRuntimeDependencies(
        self: *TestClient,
        route_dependencies: []const types.DependencySpec,
        injected_dependencies: []const types.DependencySpec,
    ) !RuntimeDependencies {
        var injected_registered_count: usize = 0;
        for (injected_dependencies) |dep| {
            if (self.app.dependency_registry.lookup(dep.name) != null) injected_registered_count += 1;
        }

        if (injected_registered_count == 0) {
            return .{
                .items = route_dependencies,
                .owned = false,
            };
        }

        if (route_dependencies.len == 0 and injected_registered_count == injected_dependencies.len) {
            return .{
                .items = injected_dependencies,
                .owned = false,
            };
        }

        const count = route_dependencies.len + injected_registered_count;
        if (count == 0) {
            return .{
                .items = &.{},
                .owned = false,
            };
        }

        const merged = try self.allocator.alloc(types.DependencySpec, count);
        var idx: usize = 0;

        for (route_dependencies) |dep| {
            merged[idx] = dep;
            idx += 1;
        }

        for (injected_dependencies) |dep| {
            if (self.app.dependency_registry.lookup(dep.name) == null) continue;
            merged[idx] = dep;
            idx += 1;
        }

        return .{
            .items = merged,
            .owned = true,
        };
    }

    fn effectiveHeaders(self: *TestClient, headers: []const std.http.Header) !EffectiveHeaders {
        var effective: EffectiveHeaders = .{ .headers = headers };

        if (!hasHeader(headers, "cookie")) {
            if (try self.buildCookieHeader()) |cookie_header| {
                effective.owned_cookie_header = cookie_header;
                const merged = try self.allocator.alloc(std.http.Header, headers.len + 1);
                @memcpy(merged[0..headers.len], headers);
                merged[headers.len] = .{
                    .name = "cookie",
                    .value = cookie_header,
                };
                effective.owned_headers = merged;
                effective.headers = merged;
            }
        }

        return effective;
    }

    fn hasHeader(headers: []const std.http.Header, name: []const u8) bool {
        for (headers) |hdr| {
            if (std.ascii.eqlIgnoreCase(hdr.name, name)) return true;
        }
        return false;
    }

    fn isWebSocketOriginAllowed(origin_header: ?[]const u8, allowed_origins: []const []const u8) bool {
        if (allowed_origins.len == 0) return true;

        const origin = std.mem.trim(u8, origin_header orelse return false, " \t");
        if (origin.len == 0) return false;

        for (allowed_origins) |item| {
            const allowed = std.mem.trim(u8, item, " \t");
            if (allowed.len == 0) continue;
            if (std.mem.eql(u8, allowed, "*")) return true;
            if (std.ascii.eqlIgnoreCase(allowed, origin)) return true;
        }

        return false;
    }

    fn selectWebSocketSubprotocol(
        offered_header: ?[]const u8,
        supported_subprotocols: []const []const u8,
    ) ?[]const u8 {
        if (supported_subprotocols.len == 0) return null;
        const offered = offered_header orelse return null;

        var offered_tokens = std.mem.splitScalar(u8, offered, ',');
        while (offered_tokens.next()) |token_raw| {
            const token = std.mem.trim(u8, token_raw, " \t");
            if (token.len == 0) continue;

            for (supported_subprotocols) |supported_raw| {
                const supported = std.mem.trim(u8, supported_raw, " \t");
                if (supported.len == 0) continue;
                if (std.mem.eql(u8, token, supported)) return supported;
            }
        }

        return null;
    }

    fn buildCookieHeader(self: *const TestClient) !?[]u8 {
        if (self.cookies.items.len == 0) return null;

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);

        var writer = out.writer(self.allocator);
        for (self.cookies.items, 0..) |entry, idx| {
            if (idx != 0) try writer.writeAll("; ");
            try writer.print("{s}={s}", .{ entry.name, entry.value });
        }
        return try out.toOwnedSlice(self.allocator);
    }

    fn applySetCookieHeaders(self: *TestClient, response: *const Response) !void {
        for (response.headers.items) |hdr| {
            if (!std.ascii.eqlIgnoreCase(hdr.name, "set-cookie")) continue;
            try self.applySetCookieHeader(hdr.value);
        }
    }

    fn applySetCookieHeader(self: *TestClient, header_value: []const u8) !void {
        var segments = std.mem.splitScalar(u8, header_value, ';');
        const first = std.mem.trim(u8, segments.next() orelse return, " \t");
        if (first.len == 0) return;

        const eq_idx = std.mem.indexOfScalar(u8, first, '=') orelse return;
        const cookie_name = std.mem.trim(u8, first[0..eq_idx], " \t");
        const cookie_value = std.mem.trim(u8, first[eq_idx + 1 ..], " \t");
        if (cookie_name.len == 0) return;

        var delete_cookie = false;
        while (segments.next()) |segment| {
            const trimmed = std.mem.trim(u8, segment, " \t");
            if (trimmed.len == 0) continue;

            if (std.mem.startsWith(u8, trimmed, "Max-Age=") or std.mem.startsWith(u8, trimmed, "max-age=")) {
                const value = std.mem.trim(u8, trimmed[8..], " \t");
                const max_age = std.fmt.parseInt(i64, value, 10) catch 1;
                if (max_age <= 0) {
                    delete_cookie = true;
                }
                continue;
            }

            if (std.mem.startsWith(u8, trimmed, "Expires=") or std.mem.startsWith(u8, trimmed, "expires=")) {
                const value = std.mem.trim(u8, trimmed[8..], " \t");
                if (std.mem.startsWith(u8, value, "Thu, 01 Jan 1970")) {
                    delete_cookie = true;
                }
            }
        }

        if (delete_cookie) {
            self.removeCookie(cookie_name);
            return;
        }

        try self.upsertCookie(cookie_name, cookie_value);
    }

    fn removeCookie(self: *TestClient, name: []const u8) void {
        var idx: usize = 0;
        while (idx < self.cookies.items.len) : (idx += 1) {
            const entry = self.cookies.items[idx];
            if (!std.mem.eql(u8, entry.name, name)) continue;

            self.allocator.free(entry.name);
            self.allocator.free(entry.value);
            _ = self.cookies.swapRemove(idx);
            return;
        }
    }

    fn upsertCookie(self: *TestClient, name: []const u8, value: []const u8) !void {
        for (self.cookies.items) |*entry| {
            if (!std.mem.eql(u8, entry.name, name)) continue;
            const owned_value = try self.allocator.dupe(u8, value);
            self.allocator.free(entry.value);
            entry.value = owned_value;
            return;
        }

        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        try self.cookies.append(self.allocator, .{
            .name = owned_name,
            .value = owned_value,
        });
    }
};
