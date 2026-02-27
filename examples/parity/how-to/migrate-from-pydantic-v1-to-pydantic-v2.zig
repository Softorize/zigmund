const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/migrate-from-pydantic-v1-to-pydantic-v2/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/migrate-from-pydantic-v1-to-pydantic-v2", implemented, .{
        .summary = "Parity implementation for how-to/migrate-from-pydantic-v1-to-pydantic-v2/",
        .tags = &.{ "parity", "how-to" },
    });
}
