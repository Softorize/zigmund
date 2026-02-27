const std = @import("std");
const zigmund = @import("zigmund");

fn graphqlExecutor(
    query: []const u8,
    operation_name: ?[]const u8,
    variables_json: ?[]const u8,
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .query = query,
        .operation = operation_name orelse "",
        .variables = variables_json orelse "",
    });
}

fn graphqlInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .graphql_endpoint = "/how-to/graphql",
        .playground = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try zigmund.mountGraphQl(app, "/how-to/graphql", graphqlExecutor, .{
        .allow_get = true,
        .playground = true,
    });

    try app.get("/how-to/graphql/info", graphqlInfo, .{
        .summary = "GraphQL integration setup details",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "how_to_graphql_info",
    });
}
