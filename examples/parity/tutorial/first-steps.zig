const std = @import("std");
const zigmund = @import("zigmund");

fn root(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .message = "Hello World" });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/", root, .{
        .summary = "First Steps",
        .tags = &.{ "parity", "tutorial" },
    });
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    var app = try zigmund.App.init(gpa.allocator(), .{
        .title = "Parity Tutorial",
        .version = "0.1.0",
    });
    defer app.deinit();

    try buildExample(&app);

    try app.serve(.{});
}
