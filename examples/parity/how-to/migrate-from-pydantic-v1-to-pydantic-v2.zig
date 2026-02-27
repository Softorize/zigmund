const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: how-to/migrate-from-pydantic-v1-to-pydantic-v2/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "how-to/migrate-from-pydantic-v1-to-pydantic-v2/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/migrate-from-pydantic-v1-to-pydantic-v2", placeholder, .{
        .summary = "Parity stub for how-to/migrate-from-pydantic-v1-to-pydantic-v2/",
        .tags = &.{"parity", "how-to"},
    });
}
