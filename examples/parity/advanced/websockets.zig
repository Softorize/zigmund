const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/websockets/";

/// WebSocket chat-style handler: receives text messages and echoes them
/// back with a prefix. Demonstrates app.websocket() registration,
/// Connection.receiveSmall(), and Connection.sendText().
fn chatHandler(conn: *zigmund.runtime.websocket.Connection, _: *zigmund.Request, _: std.mem.Allocator) anyerror!void {
    // Send a welcome message on connect
    try conn.sendText("connected");

    while (true) {
        const msg = conn.receiveSmall() catch |err| switch (err) {
            error.ConnectionClosed => return,
            error.Timeout => continue,
            else => return err,
        };

        if (msg.opcode == .text) {
            // Echo with prefix
            var buf: [256]u8 = undefined;
            const reply = std.fmt.bufPrint(&buf, "echo: {s}", .{msg.data}) catch msg.data;
            try conn.sendText(reply);
        }
    }
}

fn websocketInfo(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "WebSocket echo server — connect at /advanced/websockets/ws",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/websockets", websocketInfo, .{
        .summary = "WebSocket route info endpoint",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_websockets_info",
    });

    try app.websocket("/advanced/websockets/ws", chatHandler, .{
        .summary = "WebSocket echo handler with message prefix",
        .idle_timeout_ms = 30_000,
        .max_message_bytes = 4096,
    });
}
