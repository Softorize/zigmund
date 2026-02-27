const std = @import("std");
const zigmund = @import("zigmund");

fn readMetadata(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .name = "zigmund",
        .docs = "/docs",
        .openapi = "/openapi.json",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/metadata", readMetadata, .{
        .name = "tutorial_metadata",
        .summary = "Read API metadata",
        .description = "Demonstrates metadata, tags, and operation IDs in route configuration.",
        .tags = &.{ "parity", "tutorial", "metadata" },
        .operation_id = "tutorial_read_metadata",
    });
}
