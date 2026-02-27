const std = @import("std");
const zigmund = @import("zigmund");

fn searchItems(
    q: zigmund.Query([]const u8, .{
        .alias = "q",
        .required = false,
        .min_length = 3,
        .max_length = 50,
        .pattern = "^[A-Za-z0-9 _-]+$",
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .query = q.value,
        .matched = .{ "alpha", "beta" },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/query-params-str-validations/search", searchItems, .{
        .summary = "Validate string query params",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_validate_string_query_params",
    });
}
