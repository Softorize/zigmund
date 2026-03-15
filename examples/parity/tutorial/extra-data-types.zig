const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/extra-data-types/";

const TimestampedItem = struct {
    name: []const u8,
    created_epoch: i64,
    duration_seconds: u64,
    weight_grams: f64,
    is_active: bool,
};

fn createItem(
    body: zigmund.Body(TimestampedItem, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const item = body.value.?;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .name = item.name,
        .created_epoch = item.created_epoch,
        .duration_seconds = item.duration_seconds,
        .weight_grams = item.weight_grams,
        .is_active = item.is_active,
    });
}

fn readTimestamp(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    const now: i64 = 1710460800;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .current_epoch = now,
        .description = "Zig uses i64 epoch timestamps, u64 durations, f64 decimals",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/extra-data-types", createItem, .{
        .summary = "Create item with various data types (epoch, duration, decimal, bool)",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_create_typed_item",
    });
    try app.get("/tutorial/extra-data-types/now", readTimestamp, .{
        .summary = "Show Zig native type mappings for extra data types",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_read_timestamp",
    });
}
