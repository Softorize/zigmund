const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/dependencies/classes-as-dependencies/";

const CommonQueryParams = struct {
    q: ?[]const u8,
    skip: u32,
    limit: u32,
};

fn commonParamsProvider(req: *zigmund.Request) CommonQueryParams {
    const skip_raw = req.queryParam("skip");
    const limit_raw = req.queryParam("limit");
    return .{
        .q = req.queryParam("q"),
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
        .provider = "CommonQueryParams",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/dependencies__classes-as-dependencies", readItems, .{
        .summary = "Struct-based dependency provider (callable class equivalent)",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_deps_classes_as_dependencies",
    });
}
