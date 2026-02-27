const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: how-to/graphql/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "how-to/graphql/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/graphql", placeholder, .{
        .summary = "Parity stub for how-to/graphql/",
        .tags = &.{"parity", "how-to"},
    });
}
