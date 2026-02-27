const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/security/first-steps/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/security/first-steps/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/security__first-steps", placeholder, .{
        .summary = "Parity stub for tutorial/security/first-steps/",
        .tags = &.{"parity", "tutorial"},
    });
}
