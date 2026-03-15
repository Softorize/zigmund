const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/bigger-applications/";

fn listItems(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .items = &.{
            .{ .id = 1, .name = "Portal Gun" },
            .{ .id = 2, .name = "Plumbus" },
        },
    });
}

fn readItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .id = item_id.value.?,
        .name = "Portal Gun",
    });
}

fn listUsers(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .users = &.{
            .{ .id = 1, .username = "rick" },
            .{ .id = 2, .username = "morty" },
        },
    });
}

fn readUser(
    user_id: zigmund.Path(u32, .{ .alias = "user_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .id = user_id.value.?,
        .username = "rick",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Build an items sub-router
    var items_router = zigmund.Router.init(app.allocator);
    try items_router.addHttpRoute(.GET, "/", listItems, .{
        .summary = "List all items",
        .tags = &.{ "parity", "tutorial", "items" },
        .operation_id = "tutorial_bigger_apps_list_items",
    });
    try items_router.addHttpRoute(.GET, "/{item_id}", readItem, .{
        .summary = "Read a single item",
        .tags = &.{ "parity", "tutorial", "items" },
        .operation_id = "tutorial_bigger_apps_read_item",
    });

    // Build a users sub-router
    var users_router = zigmund.Router.init(app.allocator);
    try users_router.addHttpRoute(.GET, "/", listUsers, .{
        .summary = "List all users",
        .tags = &.{ "parity", "tutorial", "users" },
        .operation_id = "tutorial_bigger_apps_list_users",
    });
    try users_router.addHttpRoute(.GET, "/{user_id}", readUser, .{
        .summary = "Read a single user",
        .tags = &.{ "parity", "tutorial", "users" },
        .operation_id = "tutorial_bigger_apps_read_user",
    });

    // Mount sub-routers under prefixes
    try app.includeRouter("/tutorial/bigger-applications/items", &items_router, .{
        .tags = &.{ "parity", "tutorial" },
    });
    try app.includeRouter("/tutorial/bigger-applications/users", &users_router, .{
        .tags = &.{ "parity", "tutorial" },
    });
}
