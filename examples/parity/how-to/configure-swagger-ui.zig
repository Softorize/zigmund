const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: how-to/configure-swagger-ui/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "how-to/configure-swagger-ui/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/configure-swagger-ui", placeholder, .{
        .summary = "Parity stub for how-to/configure-swagger-ui/",
        .tags = &.{"parity", "how-to"},
    });
}
