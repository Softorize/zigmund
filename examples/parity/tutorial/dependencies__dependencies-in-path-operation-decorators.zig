const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/dependencies/dependencies-in-path-operation-decorators/";

fn verifyTokenResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const token = req.header("x-token") orelse return error.Unauthorized;
    if (std.mem.eql(u8, token, "invalid")) return error.Unauthorized;
    return token;
}

fn verifyKeyResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const key = req.header("x-key") orelse return error.Unauthorized;
    if (std.mem.eql(u8, key, "invalid")) return error.Unauthorized;
    return key;
}

fn readItems(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .items = &[_][]const u8{ "Portal Gun", "Plumbus" },
    });
}

fn readUsers(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .users = &[_][]const u8{ "Rick", "Morty" },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addDependency("verify_token", verifyTokenResolver);
    try app.addDependency("verify_key", verifyKeyResolver);

    try app.get("/tutorial/dependencies__dependencies-in-path-operation-decorators/items", readItems, .{
        .summary = "Read items with route-level dependency verification",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_deps_route_level_items",
        .dependencies = &.{
            .{ .name = "verify_token" },
            .{ .name = "verify_key" },
        },
    });
    try app.get("/tutorial/dependencies__dependencies-in-path-operation-decorators/users", readUsers, .{
        .summary = "Read users with route-level dependency verification",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_deps_route_level_users",
        .dependencies = &.{
            .{ .name = "verify_token" },
            .{ .name = "verify_key" },
        },
    });
}
