const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/header-params/";

fn readItems(
    user_agent: zigmund.Header([]const u8, .{ .alias = "user-agent" }),
    accept: zigmund.Header(?[]const u8, .{ .alias = "accept" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .user_agent = user_agent.value.?,
        .accept = accept.value.? orelse "not provided",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/header-params", readItems, .{
        .summary = "Extract header parameters with typed markers",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_read_items_with_headers",
    });
}
