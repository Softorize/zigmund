const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/dependencies/sub-dependencies/";

const QueryExtract = struct {
    q: ?[]const u8,
    last_query: ?[]const u8,
};

fn queryExtractor(req: *zigmund.Request) QueryExtract {
    return .{
        .q = req.queryParam("q"),
        .last_query = null,
    };
}

const SubQueryExtract = struct {
    q: ?[]const u8,
    last_query: ?[]const u8,
    description: []const u8,
};

fn subQueryExtractor(
    base: zigmund.Depends(queryExtractor, .{}),
) SubQueryExtract {
    const base_val = base.value.?;
    return .{
        .q = base_val.q,
        .last_query = base_val.last_query,
        .description = if (base_val.q != null) "query provided" else "no query",
    };
}

fn readQuery(
    sub: zigmund.Depends(subQueryExtractor, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const result = sub.value.?;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .q = result.q,
        .last_query = result.last_query,
        .description = result.description,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/dependencies__sub-dependencies", readQuery, .{
        .summary = "Chained sub-dependencies resolved in order",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_deps_sub_dependencies",
    });
}
