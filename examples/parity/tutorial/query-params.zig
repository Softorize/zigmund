const std = @import("std");
const zigmund = @import("zigmund");

fn listItems(
    skip: zigmund.Query(u32, .{ .alias = "skip", .required = false }),
    limit: zigmund.Query(u32, .{ .alias = "limit", .required = false }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const resolved_skip = skip.value orelse 0;
    const resolved_limit = limit.value orelse 10;
    return zigmund.Response.json(allocator, .{
        .skip = resolved_skip,
        .limit = resolved_limit,
        .items = .{ "alpha", "beta", "gamma" },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/query-params/items", listItems, .{
        .summary = "List items using query parameters",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_list_items_with_query_params",
    });
}
