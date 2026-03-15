const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/query-param-models/";

const QueryFilters = struct {
    q: ?[]const u8 = null,
    limit: u32 = 10,
    tags: []const []const u8 = &.{},
};

fn implemented(
    filters: zigmund.Query(QueryFilters, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .filters = filters.value.?,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/query-param-models", implemented, .{
        .summary = "Parity implementation for tutorial/query-param-models/",
        .tags = &.{ "parity", "tutorial" },
    });
}
