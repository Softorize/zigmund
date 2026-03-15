const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/testing-events/";

/// Demonstrates lifecycle event testing. The TestClient.start() and
/// TestClient.close() methods trigger the app's startup and shutdown
/// hooks, allowing verification of lifecycle behavior in tests.

var startup_counter: u32 = 0;
var shutdown_counter: u32 = 0;

fn onStartup() anyerror!void {
    startup_counter += 1;
}

fn onShutdown() anyerror!void {
    shutdown_counter += 1;
}

fn lifecycleStatus(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .startup_count = startup_counter,
        .shutdown_count = shutdown_counter,
        .message = "Lifecycle hooks track startup and shutdown events",
    });
}

/// Example test usage:
///
///   var client = zigmund.TestClient.init(std.testing.allocator, &app);
///   defer client.deinit();
///
///   try client.start();   // triggers onStartup hook
///   // ... run test requests ...
///   try client.close();   // triggers onShutdown hook

pub fn buildExample(app: *zigmund.App) !void {
    try app.onStartup(onStartup);
    try app.onShutdown(onShutdown);

    try app.get("/advanced/testing-events", lifecycleStatus, .{
        .summary = "Lifecycle event testing with startup and shutdown hooks",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_testing_events",
    });
}
