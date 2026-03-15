const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/dependencies/";

const CommonQueryParams = struct {
    q: ?[]const u8,
    skip: u32,
    limit: u32,
};

fn commonParamsProvider(req: *zigmund.Request) CommonQueryParams {
    const q = req.queryParam("q");
    const skip_raw = req.queryParam("skip");
    const limit_raw = req.queryParam("limit");
    return .{
        .q = q,
        .skip = if (skip_raw) |s| std.fmt.parseInt(u32, s, 10) catch 0 else 0,
        .limit = if (limit_raw) |l| std.fmt.parseInt(u32, l, 10) catch 100 else 100,
    };
}

fn readItems(
    commons: zigmund.Depends(commonParamsProvider, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const params = commons.value.?;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .q = params.q,
        .skip = params.skip,
        .limit = params.limit,
    });
}

fn readUsers(
    commons: zigmund.Depends(commonParamsProvider, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const params = commons.value.?;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .route = "users",
        .q = params.q,
        .skip = params.skip,
        .limit = params.limit,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/dependencies/items", readItems, .{
        .summary = "Read items with common query dependency",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_deps_read_items",
    });
    try app.get("/tutorial/dependencies/users", readUsers, .{
        .summary = "Read users with same common query dependency",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_deps_read_users",
    });
}
