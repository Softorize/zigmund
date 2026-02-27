const std = @import("std");
const zigmund = @import("zigmund");

const Item = struct {
    id: u64,
};

fn itemHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .id = @as(u64, 1) });
}

fn wsHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = conn;
    _ = allocator;
}

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, idx, needle)) |pos| {
        count += 1;
        idx = pos + needle.len;
    }
    return count;
}

test "openapi emits components refs and stable default operation ids" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-components-opid",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/items/{item_id}", itemHandler, .{
        .response_model = Item,
    });
    try app.websocket("/ws/{room_id}", wsHandler, .{
        .allowed_origins = &.{"https://allowed.example"},
        .subprotocols = &.{"chat.v1"},
        .require_subprotocol = true,
        .ping_interval_ms = 5_000,
        .pong_timeout_ms = 2_000,
        .max_message_bytes = 4096,
        .max_pending_messages = 64,
        .send_timeout_ms = 250,
    });

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"operationId\":\"get_items_item_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"operationId\":\"websocket_ws_room_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"allowedOrigins\":[\"https://allowed.example\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"subprotocols\":[\"chat.v1\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"requireSubprotocol\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"pingIntervalMs\":5000") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"pongTimeoutMs\":2000") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"maxMessageBytes\":4096") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"maxPendingMessages\":64") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"sendTimeoutMs\":250") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"components\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"schemas\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"$ref\":\"#/components/schemas/") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"id\":{\"type\":\"integer\",\"format\":\"int64\"}") != null);
}

test "openapi deduplicates repeated operation ids across operation kinds" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-opid-dedupe",
        .version = "0.0.1",
        .webhooks = &.{.{
            .name = "pet.updated",
            .method = .POST,
            .operation_id = "shared_operation",
            .response_status = .ok,
        }},
    });
    defer app.deinit();

    try app.get("/alpha", itemHandler, .{
        .operation_id = "shared_operation",
        .openapi_callbacks = &.{.{
            .name = "pet_callback",
            .expression = "{$request.body#/callback_url}",
            .method = .POST,
            .operation_id = "shared_operation",
            .response_status = .ok,
        }},
    });
    try app.post("/beta", itemHandler, .{
        .operation_id = "shared_operation",
    });
    try app.websocket("/ws/alpha", wsHandler, .{
        .operation_id = "shared_operation",
    });

    const doc = try app.openapi();

    try std.testing.expectEqual(@as(usize, 1), countOccurrences(doc, "\"operationId\":\"shared_operation\""));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(doc, "\"operationId\":\"shared_operation_2\""));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(doc, "\"operationId\":\"shared_operation_3\""));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(doc, "\"operationId\":\"shared_operation_4\""));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(doc, "\"operationId\":\"shared_operation_5\""));
}
