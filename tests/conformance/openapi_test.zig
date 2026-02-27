const std = @import("std");
const zigmund = @import("zigmund");

fn helloHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .hello = true });
}

test "openapi document includes registered path and method" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "API",
        .version = "1.0.0",
        .servers = &.{"http://localhost:8000"},
    });
    defer app.deinit();

    try app.get("/hello/{item_id}", helloHandler, .{
        .summary = "Hello",
        .tags = &.{"greeting"},
        .dependencies = &.{.{ .name = "auth" }},
        .responses = &.{.{ .status_code = .created, .description = "Created" }},
        .response_model = []const u8,
    });

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/hello/{item_id}\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"get\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"openapi\":\"3.1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"tags\":[\"greeting\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"x-zigmund-dependencies\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"parameters\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"201\"") != null);
}
