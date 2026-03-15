const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/apirouter/";

/// Demonstrates Router.init, addHttpRoute, and App.includeRouter.
fn listWidgets(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .widgets = &.{
            .{ .id = 1, .name = "Sprocket" },
            .{ .id = 2, .name = "Gizmo" },
        },
    });
}

fn getWidget(
    widget_id: zigmund.Path(u32, .{ .alias = "widget_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .widget_id = widget_id.value.?,
        .name = "Sprocket",
    });
}

fn createWidget(
    body: zigmund.Body(struct { name: []const u8 }, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    var response = try zigmund.Response.json(allocator, .{
        .page = source_page,
        .name = body.value.?.name,
        .created = true,
    });
    response.status = .created;
    return response;
}

pub fn buildExample(app: *zigmund.App) !void {
    // Create a sub-router and register routes on it
    var router = zigmund.Router.init(app.allocator);
    try router.addHttpRoute(.GET, "/", listWidgets, .{
        .summary = "List widgets via Router",
        .tags = &.{ "parity", "reference", "widgets" },
        .operation_id = "ref_apirouter_list",
    });
    try router.addHttpRoute(.GET, "/{widget_id}", getWidget, .{
        .summary = "Get widget by ID via Router",
        .tags = &.{ "parity", "reference", "widgets" },
        .operation_id = "ref_apirouter_get",
    });
    try router.addHttpRoute(.POST, "/", createWidget, .{
        .summary = "Create widget via Router",
        .tags = &.{ "parity", "reference", "widgets" },
        .operation_id = "ref_apirouter_create",
    });

    // Include the sub-router under a prefix
    try app.includeRouter("/reference/apirouter/widgets", &router, .{
        .tags = &.{ "parity", "reference" },
    });
}
