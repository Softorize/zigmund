const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: how-to/custom-request-and-route/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "how-to/custom-request-and-route/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/custom-request-and-route", placeholder, .{
        .summary = "Parity stub for how-to/custom-request-and-route/",
        .tags = &.{"parity", "how-to"},
    });
}
