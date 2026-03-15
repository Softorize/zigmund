const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/testing-websockets/";

/// Demonstrates WebSocket testing using TestClient.websocketConnect().
/// The test client creates an in-memory duplex connection that exercises
/// the full WebSocket handler without a real network socket.

fn echoHandler(conn: *zigmund.runtime.websocket.Connection, _: *zigmund.Request, _: std.mem.Allocator) anyerror!void {
    while (true) {
        const msg = conn.receiveSmall() catch |err| switch (err) {
            error.ConnectionClosed => return,
            else => return err,
        };

        switch (msg.opcode) {
            .text => try conn.sendText(msg.data),
            .binary => try conn.sendBinary(msg.data),
            else => {},
        }
    }
}

fn wsTestInfo(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "WebSocket echo server for testing — connect at /advanced/testing-websockets/ws",
    });
}

/// Example test usage:
///
///   var client = zigmund.TestClient.init(std.testing.allocator, &app);
///   defer client.deinit();
///
///   var ws = try client.websocketConnect("/advanced/testing-websockets/ws");
///   defer ws.deinit();
///
///   try ws.sendText("hello");
///   const reply = try ws.receiveSmall();
///   // reply.data == "hello", reply.opcode == .text

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/testing-websockets", wsTestInfo, .{
        .summary = "WebSocket testing info endpoint",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_testing_websockets_info",
    });

    try app.websocket("/advanced/testing-websockets/ws", echoHandler, .{
        .summary = "WebSocket echo handler for TestClient testing",
    });
}
