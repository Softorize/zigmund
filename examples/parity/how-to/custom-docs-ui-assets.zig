const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: how-to/custom-docs-ui-assets/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "how-to/custom-docs-ui-assets/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/custom-docs-ui-assets", placeholder, .{
        .summary = "Parity stub for how-to/custom-docs-ui-assets/",
        .tags = &.{"parity", "how-to"},
    });
}
