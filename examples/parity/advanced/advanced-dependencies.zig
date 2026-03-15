const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/advanced-dependencies/";

// --- Base dependency: provides a common query parameter ---
fn commonPagination(
    skip: zigmund.Query(u32, .{ .alias = "skip", .description = "Number of items to skip", .required = false }),
    limit: zigmund.Query(u32, .{ .alias = "limit", .description = "Max items to return", .required = false }),
    allocator: std.mem.Allocator,
) ![]const u8 {
    const s = skip.value orelse 0;
    const l = limit.value orelse 10;
    return std.fmt.allocPrint(allocator, "skip={d}&limit={d}", .{ s, l });
}

// --- Second dependency: depends on the first (nested pattern) ---
fn dbSession(req: *zigmund.Request) []const u8 {
    _ = req;
    return "active-db-session";
}

fn readItems(
    pagination: zigmund.Depends(commonPagination, .{}),
    db: zigmund.Depends(dbSession, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .pagination = pagination.value.?,
        .db_session = db.value.?,
    });
}

fn readItemsSingle(
    pagination: zigmund.Depends(commonPagination, .{ .use_cache = true }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .pagination = pagination.value.?,
        .cached = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/advanced-dependencies/items", readItems, .{
        .summary = "Read items with nested dependency injection",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_deps_read_items",
    });
    try app.get("/advanced/advanced-dependencies/items-cached", readItemsSingle, .{
        .summary = "Read items with cached dependency",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_deps_read_items_cached",
    });
}
