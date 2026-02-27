const std = @import("std");
const zigmund = @import("zigmund");

const ServeThreadCtx = struct {
    app: *zigmund.App,
    cfg: zigmund.ServerConfig,
    serve_error: ?anyerror = null,
};

const AuditCapture = struct {
    mutex: std.Thread.Mutex = .{},
    actions: std.ArrayListUnmanaged([]u8) = .empty,

    fn deinit(self: *AuditCapture, allocator: std.mem.Allocator) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.actions.items) |action| allocator.free(action);
        self.actions.deinit(allocator);
    }

    fn containsAction(self: *const AuditCapture, action: []const u8) bool {
        for (self.actions.items) |item| {
            if (std.mem.eql(u8, item, action)) return true;
        }
        return false;
    }
};

var active_audit_capture: ?*AuditCapture = null;

fn websocketAuditSink(event: zigmund.App.AuditEvent, allocator: std.mem.Allocator) !void {
    const capture = active_audit_capture orelse return;
    const owned_action = try allocator.dupe(u8, event.action);
    errdefer allocator.free(owned_action);

    capture.mutex.lock();
    defer capture.mutex.unlock();
    try capture.actions.append(allocator, owned_action);
}

fn serveThread(ctx: *ServeThreadCtx) void {
    ctx.app.serve(ctx.cfg) catch |err| {
        ctx.serve_error = err;
    };
}

fn reservePort() !u16 {
    const address = try std.net.Address.resolveIp("127.0.0.1", 0);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();
    return listener.listen_address.getPort();
}

fn connectWithRetry(address: std.net.Address) !std.net.Stream {
    var attempt: usize = 0;
    while (attempt < 20) : (attempt += 1) {
        const stream = std.net.tcpConnectToAddress(address) catch |err| {
            if (attempt + 1 >= 20) return err;
            std.Thread.sleep(50 * std.time.ns_per_ms);
            continue;
        };
        return stream;
    }
    return error.ConnectionFailed;
}

fn waitReadable(fd: std.posix.fd_t, timeout_ms: i32) !bool {
    var pfd = [1]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.IN,
        .revents = undefined,
    }};

    const n = try std.posix.poll(&pfd, timeout_ms);
    if (n == 0) return false;
    return (pfd[0].revents & std.posix.POLL.IN) != 0;
}

fn wsAuthDependency(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;

    const bearer = zigmund.HTTPBearer{};
    const creds = (try bearer.resolve(req)) orelse return null;
    try zigmund.security.setGrantedScopesRaw(req, req.header("x-scopes") orelse "");
    return creds.credentials;
}

fn wsHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try conn.ping("zigmund");
}

fn wsApiKeyUnauthorizedDependency(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    return error.Unauthorized;
}

fn wsApiKeyScopeDependency(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    return error.InsufficientScope;
}

fn wsUnauthorizedResponseHandler(req: *const zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var response = zigmund.Response.text("ws custom unauthorized").withStatus(.unauthorized);
    try response.setHeader(allocator, "x-auth-handler", "ws-unauthorized");
    return response;
}

fn wsInsufficientScopeResponseHandler(req: *const zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var response = zigmund.Response.text("ws custom insufficient").withStatus(.forbidden);
    try response.setHeader(allocator, "x-auth-handler", "ws-insufficient");
    return response;
}

fn sendWebSocketUpgrade(
    address: std.net.Address,
    target: []const u8,
    extra_headers: []const std.http.Header,
) ![]u8 {
    var stream = try connectWithRetry(address);
    defer stream.close();

    var request_buf: std.ArrayList(u8) = .empty;
    defer request_buf.deinit(std.testing.allocator);

    var writer = request_buf.writer(std.testing.allocator);
    try writer.print("GET {s} HTTP/1.1\r\n", .{target});
    try writer.writeAll("Host: 127.0.0.1\r\n");
    try writer.writeAll("Upgrade: websocket\r\n");
    try writer.writeAll("Connection: Upgrade\r\n");
    try writer.writeAll("Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n");
    try writer.writeAll("Sec-WebSocket-Version: 13\r\n");

    for (extra_headers) |hdr| {
        try writer.print("{s}: {s}\r\n", .{ hdr.name, hdr.value });
    }

    try writer.writeAll("\r\n");
    try stream.writeAll(request_buf.items);

    const readable = try waitReadable(stream.handle, 2_000);
    if (!readable) return error.ResponseTimeout;

    var read_buf: [4096]u8 = undefined;
    var attempts: usize = 0;
    while (attempts < 5) : (attempts += 1) {
        const n = try stream.read(&read_buf);
        if (n > 0) return std.testing.allocator.dupe(u8, read_buf[0..n]);
        std.Thread.sleep(20 * std.time.ns_per_ms);
    }
    return error.EmptyResponse;
}

fn responseStatusCode(response: []const u8) ?u16 {
    const line_end = std.mem.indexOf(u8, response, "\r\n") orelse return null;
    const line = response[0..line_end];

    var parts = std.mem.tokenizeScalar(u8, line, ' ');
    _ = parts.next() orelse return null;
    const code_text = parts.next() orelse return null;
    return std.fmt.parseInt(u16, code_text, 10) catch null;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var idx: usize = 0;
    while (idx + needle.len <= haystack.len) : (idx += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[idx .. idx + needle.len], needle)) {
            return true;
        }
    }
    return false;
}

test "websocket handshake enforces dependency auth and required scopes" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "websocket-security",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("ws_auth", wsAuthDependency);
    try app.addSecurityScheme("ws_auth", .{
        .oauth2 = .{
            .flows = .{
                .password = .{
                    .token_url = "/token",
                    .scopes = &.{
                        .{ .name = "chat:read" },
                        .{ .name = "chat:write" },
                    },
                },
            },
        },
    });

    try app.websocket("/ws-protected", wsHandler, .{
        .dependencies = &.{.{
            .name = "ws_auth",
            .scopes = &.{"chat:write"},
        }},
    });

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .idle_timeout_ms = 1_000,
        .shutdown_grace_period_ms = 200,
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer {
        app.requestShutdown();
        thread.join();
    }

    const address = try std.net.Address.resolveIp("127.0.0.1", port);

    const unauthorized = try sendWebSocketUpgrade(address, "/ws-protected", &.{});
    defer std.testing.allocator.free(unauthorized);

    try std.testing.expectEqual(@as(?u16, 401), responseStatusCode(unauthorized));
    try std.testing.expect(containsIgnoreCase(unauthorized, "www-authenticate: Bearer"));

    const insufficient = try sendWebSocketUpgrade(address, "/ws-protected", &.{
        .{ .name = "authorization", .value = "Bearer token-a" },
        .{ .name = "x-scopes", .value = "chat:read" },
    });
    defer std.testing.allocator.free(insufficient);

    try std.testing.expectEqual(@as(?u16, 403), responseStatusCode(insufficient));
    try std.testing.expect(containsIgnoreCase(insufficient, "insufficient_scope"));
    try std.testing.expect(containsIgnoreCase(insufficient, "chat:write"));

    const upgraded = try sendWebSocketUpgrade(address, "/ws-protected", &.{
        .{ .name = "authorization", .value = "Bearer token-b" },
        .{ .name = "x-scopes", .value = "chat:read chat:write" },
    });
    defer std.testing.allocator.free(upgraded);

    try std.testing.expectEqual(@as(?u16, 101), responseStatusCode(upgraded));
    try std.testing.expect(containsIgnoreCase(upgraded, "upgrade: websocket"));
}

test "websocket api key auth failures return forbidden without bearer challenge" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "websocket-api-key-security",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("ws_api_key_auth", wsApiKeyUnauthorizedDependency);
    try app.addSecurityScheme("ws_api_key_auth", .{
        .api_key = .{
            .name = "x-api-key",
            .in = .header,
        },
    });
    try app.websocket("/ws-api-key-protected", wsHandler, .{
        .dependencies = &.{.{ .name = "ws_api_key_auth" }},
    });

    try app.addDependency("ws_api_key_scope", wsApiKeyScopeDependency);
    try app.addSecurityScheme("ws_api_key_scope", .{
        .api_key = .{
            .name = "api_key",
            .in = .query,
        },
    });
    try app.websocket("/ws-api-key-scope", wsHandler, .{
        .dependencies = &.{.{
            .name = "ws_api_key_scope",
            .scopes = &.{"admin"},
        }},
    });

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .idle_timeout_ms = 1_000,
        .shutdown_grace_period_ms = 200,
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer {
        app.requestShutdown();
        thread.join();
    }

    const address = try std.net.Address.resolveIp("127.0.0.1", port);

    const unauthorized = try sendWebSocketUpgrade(address, "/ws-api-key-protected", &.{});
    defer std.testing.allocator.free(unauthorized);
    try std.testing.expectEqual(@as(?u16, 403), responseStatusCode(unauthorized));
    try std.testing.expect(!containsIgnoreCase(unauthorized, "www-authenticate:"));

    const insufficient = try sendWebSocketUpgrade(address, "/ws-api-key-scope", &.{});
    defer std.testing.allocator.free(insufficient);
    try std.testing.expectEqual(@as(?u16, 403), responseStatusCode(insufficient));
    try std.testing.expect(!containsIgnoreCase(insufficient, "www-authenticate:"));
}

test "websocket handshake uses custom auth failure handlers when configured" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "websocket-custom-auth-failure",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.setUnauthorizedHandler(wsUnauthorizedResponseHandler);
    app.setInsufficientScopeHandler(wsInsufficientScopeResponseHandler);

    try app.addDependency("ws_auth", wsAuthDependency);
    try app.addSecurityScheme("ws_auth", .{
        .oauth2 = .{
            .flows = .{
                .password = .{
                    .token_url = "/token",
                    .scopes = &.{.{ .name = "chat:write" }},
                },
            },
        },
    });
    try app.websocket("/ws-custom-auth", wsHandler, .{
        .dependencies = &.{.{
            .name = "ws_auth",
            .scopes = &.{"chat:write"},
        }},
    });

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .idle_timeout_ms = 1_000,
        .shutdown_grace_period_ms = 200,
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer {
        app.requestShutdown();
        thread.join();
    }

    const address = try std.net.Address.resolveIp("127.0.0.1", port);

    const unauthorized = try sendWebSocketUpgrade(address, "/ws-custom-auth", &.{});
    defer std.testing.allocator.free(unauthorized);
    try std.testing.expectEqual(@as(?u16, 401), responseStatusCode(unauthorized));
    try std.testing.expect(containsIgnoreCase(unauthorized, "x-auth-handler: ws-unauthorized"));
    try std.testing.expect(std.mem.indexOf(u8, unauthorized, "ws custom unauthorized") != null);
    try std.testing.expect(!containsIgnoreCase(unauthorized, "www-authenticate:"));

    const insufficient = try sendWebSocketUpgrade(address, "/ws-custom-auth", &.{
        .{ .name = "authorization", .value = "Bearer token-a" },
        .{ .name = "x-scopes", .value = "chat:read" },
    });
    defer std.testing.allocator.free(insufficient);
    try std.testing.expectEqual(@as(?u16, 403), responseStatusCode(insufficient));
    try std.testing.expect(containsIgnoreCase(insufficient, "x-auth-handler: ws-insufficient"));
    try std.testing.expect(std.mem.indexOf(u8, insufficient, "ws custom insufficient") != null);
    try std.testing.expect(!containsIgnoreCase(insufficient, "www-authenticate:"));
}

test "websocket handshake enforces route origin allowlist" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "websocket-origin-policy",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws-origin", wsHandler, .{
        .allowed_origins = &.{"https://allowed.example"},
    });

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .idle_timeout_ms = 1_000,
        .shutdown_grace_period_ms = 200,
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer {
        app.requestShutdown();
        thread.join();
    }

    const address = try std.net.Address.resolveIp("127.0.0.1", port);

    const missing_origin = try sendWebSocketUpgrade(address, "/ws-origin", &.{});
    defer std.testing.allocator.free(missing_origin);
    try std.testing.expectEqual(@as(?u16, 403), responseStatusCode(missing_origin));

    const denied_origin = try sendWebSocketUpgrade(address, "/ws-origin", &.{
        .{ .name = "origin", .value = "https://denied.example" },
    });
    defer std.testing.allocator.free(denied_origin);
    try std.testing.expectEqual(@as(?u16, 403), responseStatusCode(denied_origin));

    const allowed_origin = try sendWebSocketUpgrade(address, "/ws-origin", &.{
        .{ .name = "origin", .value = "https://allowed.example" },
    });
    defer std.testing.allocator.free(allowed_origin);
    try std.testing.expectEqual(@as(?u16, 101), responseStatusCode(allowed_origin));
}

test "websocket handshake enforces required subprotocol negotiation" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "websocket-subprotocol-policy",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws-subprotocol", wsHandler, .{
        .subprotocols = &.{ "chat.v2", "chat.v1" },
        .require_subprotocol = true,
    });

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .idle_timeout_ms = 1_000,
        .shutdown_grace_period_ms = 200,
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer {
        app.requestShutdown();
        thread.join();
    }

    const address = try std.net.Address.resolveIp("127.0.0.1", port);

    const missing_protocol = try sendWebSocketUpgrade(address, "/ws-subprotocol", &.{});
    defer std.testing.allocator.free(missing_protocol);
    try std.testing.expectEqual(@as(?u16, 400), responseStatusCode(missing_protocol));

    const unknown_protocol = try sendWebSocketUpgrade(address, "/ws-subprotocol", &.{
        .{ .name = "sec-websocket-protocol", .value = "other.v1" },
    });
    defer std.testing.allocator.free(unknown_protocol);
    try std.testing.expectEqual(@as(?u16, 400), responseStatusCode(unknown_protocol));

    const negotiated = try sendWebSocketUpgrade(address, "/ws-subprotocol", &.{
        .{ .name = "sec-websocket-protocol", .value = "other.v1, chat.v1" },
    });
    defer std.testing.allocator.free(negotiated);
    try std.testing.expectEqual(@as(?u16, 101), responseStatusCode(negotiated));
    try std.testing.expect(containsIgnoreCase(negotiated, "sec-websocket-protocol: chat.v1"));
}

test "websocket handshake emits audit events for auth and policy rejections" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "websocket-audit-events",
        .version = "0.0.1",
    });
    defer app.deinit();

    var capture: AuditCapture = .{};
    defer capture.deinit(std.testing.allocator);
    active_audit_capture = &capture;
    defer active_audit_capture = null;
    app.setAuditSink(websocketAuditSink);

    try app.addDependency("ws_auth", wsAuthDependency);
    try app.addSecurityScheme("ws_auth", .{
        .oauth2 = .{
            .flows = .{
                .password = .{
                    .token_url = "/token",
                    .scopes = &.{
                        .{ .name = "chat:read" },
                        .{ .name = "chat:write" },
                    },
                },
            },
        },
    });

    try app.websocket("/ws-protected", wsHandler, .{
        .dependencies = &.{.{
            .name = "ws_auth",
            .scopes = &.{"chat:write"},
        }},
    });
    try app.websocket("/ws-origin", wsHandler, .{
        .allowed_origins = &.{"https://allowed.example"},
    });
    try app.websocket("/ws-subprotocol", wsHandler, .{
        .subprotocols = &.{ "chat.v2", "chat.v1" },
        .require_subprotocol = true,
    });

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .idle_timeout_ms = 1_000,
        .shutdown_grace_period_ms = 200,
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer {
        app.requestShutdown();
        thread.join();
    }

    const address = try std.net.Address.resolveIp("127.0.0.1", port);

    const unauthorized = try sendWebSocketUpgrade(address, "/ws-protected", &.{});
    defer std.testing.allocator.free(unauthorized);
    try std.testing.expectEqual(@as(?u16, 401), responseStatusCode(unauthorized));

    const insufficient = try sendWebSocketUpgrade(address, "/ws-protected", &.{
        .{ .name = "authorization", .value = "Bearer token-a" },
        .{ .name = "x-scopes", .value = "chat:read" },
    });
    defer std.testing.allocator.free(insufficient);
    try std.testing.expectEqual(@as(?u16, 403), responseStatusCode(insufficient));

    const denied_origin = try sendWebSocketUpgrade(address, "/ws-origin", &.{
        .{ .name = "origin", .value = "https://denied.example" },
    });
    defer std.testing.allocator.free(denied_origin);
    try std.testing.expectEqual(@as(?u16, 403), responseStatusCode(denied_origin));

    const missing_protocol = try sendWebSocketUpgrade(address, "/ws-subprotocol", &.{});
    defer std.testing.allocator.free(missing_protocol);
    try std.testing.expectEqual(@as(?u16, 400), responseStatusCode(missing_protocol));

    capture.mutex.lock();
    defer capture.mutex.unlock();

    try std.testing.expect(capture.containsAction("websocket_unauthorized"));
    try std.testing.expect(capture.containsAction("websocket_insufficient_scope"));
    try std.testing.expect(capture.containsAction("origin_rejected"));
    try std.testing.expect(capture.containsAction("subprotocol_rejected"));
}
