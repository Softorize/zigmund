const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/openapi-webhooks/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/openapi-webhooks/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/openapi-webhooks", placeholder, .{
        .summary = "Parity stub for advanced/openapi-webhooks/",
        .tags = &.{"parity", "advanced"},
    });
}
