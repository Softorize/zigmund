const std = @import("std");
const zigmund = @import("zigmund");

fn itemHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const id = req.param("item_id") orelse "missing";
    return zigmund.Response.json(allocator, .{ .item_id = id });
}

test "router matches and captures path params" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/items/{item_id}", itemHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/items/42");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"item_id\":\"42\"") != null);
}
