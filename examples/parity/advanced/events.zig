const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/events/";

var startup_called = std.atomic.Value(bool).init(false);
var shutdown_called = std.atomic.Value(bool).init(false);

fn onStartup() void {
    startup_called.store(true, .release);
    std.log.info("[events example] startup hook executed", .{});
}

fn onShutdown() void {
    shutdown_called.store(true, .release);
    std.log.info("[events example] shutdown hook executed", .{});
}

fn lifecycleStatus(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .startup_executed = startup_called.load(.acquire),
        .shutdown_executed = shutdown_called.load(.acquire),
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.onStartup(onStartup);
    try app.onShutdown(onShutdown);

    try app.get("/advanced/events", lifecycleStatus, .{
        .summary = "Check startup and shutdown lifecycle hook status",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_events_lifecycle_status",
    });
}
