const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/json-base64-bytes/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/json-base64-bytes/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/json-base64-bytes", placeholder, .{
        .summary = "Parity stub for advanced/json-base64-bytes/",
        .tags = &.{"parity", "advanced"},
    });
}
