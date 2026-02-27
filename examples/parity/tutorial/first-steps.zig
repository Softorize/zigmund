const std = @import("std");
const zigmund = @import("zigmund");

fn root(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .message = "Hello World" });
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    var app = try zigmund.App.init(gpa.allocator(), .{
        .title = "Parity Tutorial",
        .version = "0.1.0",
    });
    defer app.deinit();

    try app.get("/", root, .{
        .summary = "First Steps",
    });

    try app.serve(.{});
}
