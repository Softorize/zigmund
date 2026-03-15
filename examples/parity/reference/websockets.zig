const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/websockets/";

/// Describes the WebSocket API since ws handlers cannot return HTTP responses.
fn websocketInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .registration = "app.websocket(path, handler, WebSocketRouteOptions)",
        .handler_signature = "fn(conn: *Connection, req: *Request, allocator: Allocator) !void",
        .connection_api = .{
            .sendText = "conn.sendText(text) - send a text frame",
            .sendBinary = "conn.sendBinary(payload) - send a binary frame",
            .receiveSmall = "conn.receiveSmall() - receive next message",
            .close = "conn.close() - close the connection",
            .closeWithCode = "conn.closeWithCode(code, reason) - close with status code",
            .ping = "conn.ping(payload) - send a ping frame",
            .subprotocol = "conn.subprotocol() - negotiated subprotocol",
        },
        .route_options = .{
            .idle_timeout_ms = "connection idle timeout",
            .auto_pong = "default true - auto respond to pings",
            .max_message_bytes = "maximum message size",
            .subprotocols = "list of supported subprotocols",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/websockets", websocketInfo, .{
        .summary = "WebSocket connection API and route options",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_websockets_overview",
    });
}
