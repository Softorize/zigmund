const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: how-to/general/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "how-to/general/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/general", placeholder, .{
        .summary = "Parity stub for how-to/general/",
        .tags = &.{"parity", "how-to"},
    });
}
