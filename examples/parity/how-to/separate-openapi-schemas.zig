const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: how-to/separate-openapi-schemas/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "how-to/separate-openapi-schemas/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/separate-openapi-schemas", placeholder, .{
        .summary = "Parity stub for how-to/separate-openapi-schemas/",
        .tags = &.{"parity", "how-to"},
    });
}
