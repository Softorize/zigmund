const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/sub-applications/";

fn subappHome(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .app = "subapp",
        .message = "This route is served by a mounted sub-application",
    });
}

fn subappItems(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .app = "subapp",
        .items = &[_][]const u8{ "item-a", "item-b", "item-c" },
    });
}

fn mainAppInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .app = "main",
        .message = "This is the main application; subapp is mounted at /advanced/sub-applications/v2",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Register the main app route
    try app.get("/advanced/sub-applications", mainAppInfo, .{
        .summary = "Main application info with mounted sub-app",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_sub_applications_main",
    });

    // Register sub-app routes directly under the sub-application prefix.
    // In a full deployment you would create a separate App and call app.mount(),
    // but since parity examples share a single App instance we register the
    // sub-app routes on the parent directly under the desired prefix.
    try app.get("/advanced/sub-applications/v2", subappHome, .{
        .summary = "Sub-application home",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_sub_applications_v2_home",
    });
    try app.get("/advanced/sub-applications/v2/items", subappItems, .{
        .summary = "Sub-application items list",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_sub_applications_v2_items",
    });
}
