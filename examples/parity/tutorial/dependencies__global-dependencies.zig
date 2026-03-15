const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/dependencies/global-dependencies/";

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
    const token = req.dependency("global_verify_token");
    const key = req.dependency("global_verify_key");
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .items = &[_][]const u8{ "Portal Gun", "Plumbus" },
        .token = token,
        .key = key,
    });
}

fn readUsers(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const token = req.dependency("global_verify_token");
    const key = req.dependency("global_verify_key");
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .users = &[_][]const u8{ "Rick", "Morty" },
        .token = token,
        .key = key,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addDependency("global_verify_token", verifyTokenResolver);
    try app.addDependency("global_verify_key", verifyKeyResolver);

    try app.get("/tutorial/dependencies__global-dependencies/items", readItems, .{
        .summary = "Read items with global app-level dependencies",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_deps_global_items",
        .dependencies = &.{
            .{ .name = "global_verify_token" },
            .{ .name = "global_verify_key" },
        },
    });
    try app.get("/tutorial/dependencies__global-dependencies/users", readUsers, .{
        .summary = "Read users with global app-level dependencies",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_deps_global_users",
        .dependencies = &.{
            .{ .name = "global_verify_token" },
            .{ .name = "global_verify_key" },
        },
    });
}
