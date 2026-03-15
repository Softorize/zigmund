const std = @import("std");
const zigmund = @import("zigmund");

fn rootPathHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .path = req.path,
    });
}

test "root_path serves http routes and docs beneath the configured public prefix" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "root-path",
        .version = "0.0.1",
        .root_path = "/api",
    });
    defer app.deinit();

    try app.get("/items", rootPathHandler, .{});

    var item_res = try app.dispatchSynthetic(.GET, "/api/items", "");
    defer item_res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, item_res.status);
    try std.testing.expect(std.mem.indexOf(u8, item_res.body, "\"path\":\"/items\"") != null);

    var docs_res = try app.dispatchSynthetic(.GET, "/api/docs", "");
    defer docs_res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, docs_res.status);
    try std.testing.expect(std.mem.indexOf(u8, docs_res.body, "\"/api/openapi.json\"") != null);

    var openapi_res = try app.dispatchSynthetic(.GET, "/api/openapi.json", "");
    defer openapi_res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, openapi_res.status);
    try std.testing.expect(std.mem.indexOf(u8, openapi_res.body, "\"/items\"") != null);
}
