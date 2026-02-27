const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: how-to/authentication-error-status-code/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "how-to/authentication-error-status-code/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/authentication-error-status-code", placeholder, .{
        .summary = "Parity stub for how-to/authentication-error-status-code/",
        .tags = &.{"parity", "how-to"},
    });
}
