const std = @import("std");
const zigmund = @import("zigmund");

var ws_cleanup_calls: usize = 0;
var ws_last_close_code: ?u16 = null;
var ws_pong_timeout_seen: bool = false;
var ws_backpressure_seen: bool = false;

fn echoHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = allocator;

    while (true) {
        const msg = conn.receiveSmall() catch |err| switch (err) {
            error.ConnectionClosed => return,
            else => return err,
        };

        switch (msg.opcode) {
            .text => try conn.sendText(msg.data),
            .binary => try conn.sendBinary(msg.data),
            .ping => try conn.sendText("pong"),
            else => return,
        }
    }
}

fn textOnlyHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = allocator;

    while (true) {
        const msg = conn.receiveSmall() catch |err| switch (err) {
            error.ConnectionClosed => return,
            else => return err,
        };

        if (msg.opcode == .text) {
            try conn.sendText(msg.data);
        }
    }
}

fn idleWaitHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = allocator;
    _ = try conn.receiveSmall();
}

fn subprotocolEchoHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try conn.sendText(conn.subprotocol() orelse "");
}

fn closeCodeCaptureHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = allocator;

    while (true) {
        _ = conn.receiveSmall() catch |err| switch (err) {
            error.ConnectionClosed => {
                ws_last_close_code = conn.lastCloseCode();
                return;
            },
            else => return err,
        };
    }
}

fn heartbeatAwaitPongHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = allocator;

    while (true) {
        const msg = conn.receiveSmall() catch |err| switch (err) {
            error.ConnectionClosed => return,
            else => return err,
        };

        if (msg.opcode == .pong) {
            try conn.sendText("heartbeat-ok");
            return;
        }
    }
}

fn heartbeatTimeoutHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = allocator;
    while (true) {
        _ = conn.receiveSmall() catch |err| switch (err) {
            error.PongTimeout => {
                ws_pong_timeout_seen = true;
                ws_last_close_code = conn.lastCloseCode();
                return;
            },
            error.ConnectionClosed => return,
            else => return err,
        };
    }
}

fn maxMessageCaptureHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = allocator;
    while (true) {
        _ = conn.receiveSmall() catch |err| switch (err) {
            error.MessageTooBig => {
                ws_last_close_code = conn.lastCloseCode();
                return;
            },
            error.ConnectionClosed => return,
            else => return err,
        };
    }
}

fn slowReceiveHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.Thread.sleep(120 * std.time.ns_per_ms);
    _ = conn.receiveSmall() catch |err| switch (err) {
        error.ConnectionClosed => return,
        else => return err,
    };
}

fn burstSendBackpressureHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try conn.sendText("one");
    conn.sendText("two") catch |err| switch (err) {
        error.Backpressure => {
            ws_backpressure_seen = true;
            return;
        },
        else => return err,
    };
}

fn requestAwareWsHandler(
    conn: *zigmund.runtime.websocket.Connection,
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !void {
    _ = allocator;
    const item_id = req.param("item_id") orelse "";
    const trace = req.header("x-trace-id") orelse "";
    try conn.sendText(if (trace.len != 0) trace else item_id);
}

fn wsAuthDependency(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;

    const bearer = zigmund.HTTPBearer{};
    const creds = (try bearer.resolve(req)) orelse return null;
    try zigmund.security.setGrantedScopesRaw(req, req.header("x-scopes") orelse "");
    return creds.credentials;
}

fn cleanupDependency(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    return "connected";
}

fn cleanupCallback(req: *zigmund.Request, key: []const u8, value: []const u8, allocator: std.mem.Allocator) !void {
    _ = req;
    _ = key;
    _ = value;
    _ = allocator;
    ws_cleanup_calls += 1;
}

test "testclient websocket session can send and receive in-process" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-testclient",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var session = try client.websocketConnect("/ws");
    defer session.deinit();

    try session.sendText("hello");
    const msg = try session.receiveSmall();
    try std.testing.expectEqual(.text, msg.opcode);
    try std.testing.expectEqualStrings("hello", msg.data);
}

test "websocket handler can read request path params and headers" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-request-aware",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws/items/{item_id}", requestAwareWsHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var with_header = try client.websocketConnectWithHeaders("/ws/items/42", &.{
        .{ .name = "x-trace-id", .value = "trace-abc" },
    });
    defer with_header.deinit();
    const traced = try with_header.receiveSmall();
    try std.testing.expectEqual(.text, traced.opcode);
    try std.testing.expectEqualStrings("trace-abc", traced.data);

    var from_path = try client.websocketConnect("/ws/items/99");
    defer from_path.deinit();
    const fallback = try from_path.receiveSmall();
    try std.testing.expectEqual(.text, fallback.opcode);
    try std.testing.expectEqualStrings("99", fallback.data);
}

test "testclient websocket connect enforces dependency auth scopes" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-testclient-security",
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

    try app.websocket("/ws-protected", echoHandler, .{
        .dependencies = &.{.{
            .name = "ws_auth",
            .scopes = &.{"chat:write"},
        }},
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    try std.testing.expectError(error.Unauthorized, client.websocketConnect("/ws-protected"));

    try std.testing.expectError(
        error.InsufficientScope,
        client.websocketConnectWithHeaders("/ws-protected", &.{
            .{ .name = "authorization", .value = "Bearer token-a" },
            .{ .name = "x-scopes", .value = "chat:read" },
        }),
    );

    var session = try client.websocketConnectWithHeaders("/ws-protected", &.{
        .{ .name = "authorization", .value = "Bearer token-b" },
        .{ .name = "x-scopes", .value = "chat:read chat:write" },
    });
    defer session.deinit();

    try session.sendText("ok");
    const msg = try session.receiveSmall();
    try std.testing.expectEqual(.text, msg.opcode);
    try std.testing.expectEqualStrings("ok", msg.data);
    try std.testing.expect(session.handlerError() == null);
}

test "testclient websocket session triggers dependency cleanup on close" {
    ws_cleanup_calls = 0;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-cleanup",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependencyWithCleanup("ws_dep", cleanupDependency, cleanupCallback);
    try app.websocket("/ws-cleanup", echoHandler, .{
        .dependencies = &.{.{ .name = "ws_dep" }},
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var session = try client.websocketConnect("/ws-cleanup");
    session.close();
    session.deinit();

    try std.testing.expectEqual(@as(usize, 1), ws_cleanup_calls);
}

test "testclient websocket receive timeout and close code handling" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-timeout-close",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws-timeout", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var session = try client.websocketConnect("/ws-timeout");
    defer session.deinit();

    try std.testing.expectError(error.Timeout, session.receiveSmallWithTimeout(25));

    try session.closeWithCode(1001, "going-away");
    try std.testing.expect(session.handlerError() == null);
}

test "websocket route idle timeout surfaces timeout in handler lifecycle" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-idle-timeout",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws-idle", idleWaitHandler, .{
        .idle_timeout_ms = 25,
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var session = try client.websocketConnect("/ws-idle");
    defer session.deinit();

    var attempts: usize = 0;
    while (attempts < 20 and session.handlerError() == null) : (attempts += 1) {
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    try std.testing.expect(session.handlerError() != null);
    try std.testing.expectEqualStrings("Timeout", @errorName(session.handlerError().?));
}

test "websocket auto_pong can be disabled per route" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-auto-pong",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws-auto", textOnlyHandler, .{});
    try app.websocket("/ws-no-auto", textOnlyHandler, .{
        .auto_pong = false,
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var auto_session = try client.websocketConnect("/ws-auto");
    defer auto_session.deinit();
    try auto_session.ping("hb");
    const pong = try auto_session.receiveSmallWithTimeout(100);
    try std.testing.expectEqual(.pong, pong.opcode);
    try std.testing.expectEqualStrings("hb", pong.data);

    var no_auto_session = try client.websocketConnect("/ws-no-auto");
    defer no_auto_session.deinit();
    try no_auto_session.ping("hb");
    try std.testing.expectError(error.Timeout, no_auto_session.receiveSmallWithTimeout(40));
}

test "testclient websocket enforces origin and subprotocol handshake policies" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-handshake-policies",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws-origin", textOnlyHandler, .{
        .allowed_origins = &.{"https://allowed.example"},
    });
    try app.websocket("/ws-subprotocol", subprotocolEchoHandler, .{
        .subprotocols = &.{ "chat.v2", "chat.v1" },
        .require_subprotocol = true,
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    try std.testing.expectError(error.WebSocketOriginForbidden, client.websocketConnect("/ws-origin"));
    try std.testing.expectError(
        error.WebSocketOriginForbidden,
        client.websocketConnectWithHeaders("/ws-origin", &.{
            .{ .name = "origin", .value = "https://denied.example" },
        }),
    );

    var origin_session = try client.websocketConnectWithHeaders("/ws-origin", &.{
        .{ .name = "origin", .value = "https://allowed.example" },
    });
    origin_session.close();
    origin_session.deinit();

    try std.testing.expectError(
        error.WebSocketSubprotocolRequired,
        client.websocketConnect("/ws-subprotocol"),
    );
    try std.testing.expectError(
        error.WebSocketSubprotocolRequired,
        client.websocketConnectWithHeaders("/ws-subprotocol", &.{
            .{ .name = "sec-websocket-protocol", .value = "other.v1" },
        }),
    );

    var subprotocol_session = try client.websocketConnectWithHeaders("/ws-subprotocol", &.{
        .{ .name = "sec-websocket-protocol", .value = "other.v1, chat.v1" },
    });
    defer subprotocol_session.deinit();

    try std.testing.expectEqualStrings("chat.v1", subprotocol_session.subprotocol().?);
    const msg = try subprotocol_session.receiveSmall();
    try std.testing.expectEqual(.text, msg.opcode);
    try std.testing.expectEqualStrings("chat.v1", msg.data);
}

test "testclient websocket close code is visible to handler and client session" {
    ws_last_close_code = null;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-close-codes",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws-close-codes", closeCodeCaptureHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var session = try client.websocketConnect("/ws-close-codes");

    try session.closeWithCode(1008, "policy");
    try std.testing.expectEqual(@as(?u16, 1008), session.lastCloseCode());

    session.deinit();
    try std.testing.expectEqual(@as(?u16, 1008), ws_last_close_code);
}

test "websocket ping policy sends heartbeat and accepts pong within timeout" {
    ws_pong_timeout_seen = false;
    ws_last_close_code = null;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-heartbeat-ok",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws-heartbeat-ok", heartbeatAwaitPongHandler, .{
        .ping_interval_ms = 20,
        .pong_timeout_ms = 80,
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var session = try client.websocketConnect("/ws-heartbeat-ok");
    defer session.deinit();

    const ping = try session.receiveSmallWithTimeout(120);
    try std.testing.expectEqual(.ping, ping.opcode);

    const ack = try session.receiveSmallWithTimeout(120);
    try std.testing.expectEqual(.text, ack.opcode);
    try std.testing.expectEqualStrings("heartbeat-ok", ack.data);
    try std.testing.expect(!ws_pong_timeout_seen);
}

test "websocket ping policy closes connection when pong timeout elapses" {
    ws_pong_timeout_seen = false;
    ws_last_close_code = null;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-heartbeat-timeout",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws-heartbeat-timeout", heartbeatTimeoutHandler, .{
        .auto_pong = false,
        .ping_interval_ms = 20,
        .pong_timeout_ms = 40,
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var session = try client.websocketConnect("/ws-heartbeat-timeout");
    defer session.deinit();

    const ping = try session.receiveSmallWithTimeout(120);
    try std.testing.expectEqual(.ping, ping.opcode);

    try std.testing.expectError(error.ConnectionClosed, session.receiveSmallWithTimeout(180));
    try std.testing.expectEqual(@as(?u16, 1011), session.lastCloseCode());

    var attempts: usize = 0;
    while (attempts < 30 and !ws_pong_timeout_seen) : (attempts += 1) {
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    try std.testing.expect(ws_pong_timeout_seen);
    try std.testing.expectEqual(@as(?u16, 1011), ws_last_close_code);
}

test "websocket max_message_bytes closes connection with 1009" {
    ws_last_close_code = null;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-max-message",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws-max-message", maxMessageCaptureHandler, .{
        .max_message_bytes = 4,
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var session = try client.websocketConnect("/ws-max-message");
    defer session.deinit();

    try session.sendText("0123456789");
    try std.testing.expectError(error.ConnectionClosed, session.receiveSmallWithTimeout(200));
    try std.testing.expectEqual(@as(?u16, 1009), session.lastCloseCode());

    var attempts: usize = 0;
    while (attempts < 30 and ws_last_close_code == null) : (attempts += 1) {
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
    try std.testing.expectEqual(@as(?u16, 1009), ws_last_close_code);
}

test "websocket queue limit applies backpressure to client sends" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-client-backpressure",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws-client-backpressure", slowReceiveHandler, .{
        .max_pending_messages = 1,
        .send_timeout_ms = 20,
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var session = try client.websocketConnect("/ws-client-backpressure");
    defer session.deinit();

    try session.sendText("first");
    try std.testing.expectError(error.Backpressure, session.sendText("second"));
}

test "websocket queue limit applies backpressure to server sends" {
    ws_backpressure_seen = false;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "ws-server-backpressure",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.websocket("/ws-server-backpressure", burstSendBackpressureHandler, .{
        .max_pending_messages = 1,
        .send_timeout_ms = 20,
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var session = try client.websocketConnect("/ws-server-backpressure");
    defer session.deinit();

    std.Thread.sleep(40 * std.time.ns_per_ms);
    const msg = try session.receiveSmallWithTimeout(200);
    try std.testing.expectEqual(.text, msg.opcode);
    try std.testing.expectEqualStrings("one", msg.data);

    var attempts: usize = 0;
    while (attempts < 30 and !ws_backpressure_seen) : (attempts += 1) {
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
    try std.testing.expect(ws_backpressure_seen);
}
