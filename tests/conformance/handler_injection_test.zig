const std = @import("std");
const zigmund = @import("zigmund");

const BodyModel = struct {
    name: []const u8,
};

fn authProvider(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const token = req.queryParam("token") orelse return null;
    if (std.mem.eql(u8, token, "secret")) {
        try zigmund.security.setGrantedScopes(req, &.{"items:read"});
        return "alice";
    }
    return null;
}

fn injectedHandler(
    item: zigmund.Path(u32, .{ .alias = "item_id" }),
    page: zigmund.Query(u8, .{ .alias = "page" }),
    body: zigmund.Body(BodyModel, .{}),
    auth: zigmund.Security(authProvider, &.{"items:read"}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .item_id = item.value.?,
        .page = page.value.?,
        .name = body.value.?.name,
        .user = auth.value.?,
    });
}

test "typed handler argument injection" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "inject",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/items/{item_id}", injectedHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var unauthorized = try client.post("/items/7?page=3", "{\"name\":\"bolt\"}");
    defer unauthorized.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unauthorized, unauthorized.status);

    var ok = try client.post("/items/7?page=3&token=secret", "{\"name\":\"bolt\"}");
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok.status);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"item_id\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"page\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"name\":\"bolt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"user\":\"alice\"") != null);

    var bad_path = try client.post("/items/abc?page=3&token=secret", "{\"name\":\"bolt\"}");
    defer bad_path.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, bad_path.status);
    try std.testing.expect(std.mem.indexOf(u8, bad_path.body, "\"loc\":[\"path\",\"item_id\"]") != null);
}
