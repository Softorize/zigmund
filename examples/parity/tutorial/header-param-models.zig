const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/header-param-models/";

const HeaderContext = struct {
    trace_id: []const u8,
    request_source: ?[]const u8 = null,
};

fn implemented(
    headers: zigmund.Header(HeaderContext, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .headers = headers.value.?,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/header-param-models", implemented, .{
        .summary = "Parity implementation for tutorial/header-param-models/",
        .tags = &.{ "parity", "tutorial" },
    });
}
