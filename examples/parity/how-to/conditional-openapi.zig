const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: how-to/conditional-openapi/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "how-to/conditional-openapi/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/conditional-openapi", placeholder, .{
        .summary = "Parity stub for how-to/conditional-openapi/",
        .tags = &.{"parity", "how-to"},
    });
}
