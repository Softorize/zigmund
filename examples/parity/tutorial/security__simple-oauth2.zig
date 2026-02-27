const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/security/simple-oauth2/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/security/simple-oauth2/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/security__simple-oauth2", placeholder, .{
        .summary = "Parity stub for tutorial/security/simple-oauth2/",
        .tags = &.{"parity", "tutorial"},
    });
}
