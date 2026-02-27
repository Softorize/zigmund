const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/security/get-current-user/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/security/get-current-user/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/security__get-current-user", placeholder, .{
        .summary = "Parity stub for tutorial/security/get-current-user/",
        .tags = &.{"parity", "tutorial"},
    });
}
