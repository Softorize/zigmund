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

fn richScalarHandler(
    next: zigmund.Query(std.Uri, .{ .alias = "next" }),
    ip: zigmund.Query(std.net.Ip4Address, .{ .alias = "ip" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    var host_buf: [64]u8 = undefined;
    var ip_buf: [64]u8 = undefined;
    return zigmund.Response.json(allocator, .{
        .host = try next.value.?.getHost(&host_buf),
        .ip = try std.fmt.bufPrint(&ip_buf, "{f}", .{ip.value.?}),
    });
}

test "typed handler injection supports uri and ip query parameters" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "inject-rich-scalars",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/resolve", richScalarHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var ok = try client.get("/resolve?next=https%3A%2F%2Fexample.com%2Fitems&ip=127.0.0.1");
    defer ok.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, ok.status);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"host\":\"example.com\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"ip\":\"127.0.0.1:0\"") != null);

    var bad = try client.get("/resolve?next=http%3A%2F%2F%5B%3A%3A1&ip=127.0.0.1");
    defer bad.deinit(std.testing.allocator);

    try std.testing.expectEqual(.unprocessable_entity, bad.status);
    try std.testing.expect(std.mem.indexOf(u8, bad.body, "\"loc\":[\"query\",\"next\"]") != null);
}
