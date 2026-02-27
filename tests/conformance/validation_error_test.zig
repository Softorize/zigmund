const std = @import("std");
const zigmund = @import("zigmund");

const Payload = struct {
    name: []const u8,
};

fn validateHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const item_id = try req.paramAs(u32, "item_id");
    const active = try req.queryAs(bool, "active");

    var parsed = try req.bodyJson(Payload);
    defer parsed.deinit();

    return zigmund.Response.json(allocator, .{
        .item_id = item_id,
        .active = active,
        .name = parsed.value.name,
    });
}

test "validation errors return FastAPI-style 422 payload" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "validation",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/items/{item_id}", validateHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var bad_path = try client.post("/items/abc?active=true", "{\"name\":\"zig\"}");
    defer bad_path.deinit(std.testing.allocator);

    try std.testing.expectEqual(.unprocessable_entity, bad_path.status);
    try std.testing.expect(std.mem.indexOf(u8, bad_path.body, "\"loc\":[\"path\",\"item_id\"]") != null);

    var bad_body = try client.post("/items/42?active=true", "{not-json");
    defer bad_body.deinit(std.testing.allocator);

    try std.testing.expectEqual(.unprocessable_entity, bad_body.status);
    try std.testing.expect(std.mem.indexOf(u8, bad_body.body, "\"loc\":[\"body\",\"body\"]") != null);
}
