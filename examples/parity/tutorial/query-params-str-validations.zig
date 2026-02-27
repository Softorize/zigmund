const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/query-params-str-validations/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/query-params-str-validations/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/query-params-str-validations", placeholder, .{
        .summary = "Parity stub for tutorial/query-params-str-validations/",
        .tags = &.{"parity", "tutorial"},
    });
}
