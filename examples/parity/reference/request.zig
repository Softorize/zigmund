const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/request/";

/// Demonstrates the Request public API: headers, path/query params, body, and state.
fn requestInspector(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    // req.method, req.path, req.query -- basic request properties
    // req.header(name) -- read a single header
    // req.param(name) -- read a path parameter
    // req.queryParam(name) -- read a query parameter
    const user_agent = req.header("user-agent") orelse "unknown";
    const search = req.queryParam("q");

    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .method = @tagName(req.method),
        .path = req.path,
        .query_string = req.query,
        .user_agent = user_agent,
        .search = search,
        .api = .{
            .headers = "req.header(name) -> ?[]const u8",
            .path_params = "req.param(name) -> ?[]const u8",
            .query_params = "req.queryParam(name) -> ?[]const u8",
            .body = "req.body (raw bytes), req.bodyJsonLeaky(T), req.formAsLeaky(T)",
            .state = "req.stateAs(T, key), req.setStateBorrowed(key, val)",
        },
    });
}

fn requestWithPathParam(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .item_id = item_id.value.?,
        .content_type = req.header("content-type"),
        .request_id = req.request_id,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/request", requestInspector, .{
        .summary = "Request API: headers, query params, method, path",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_request_inspector",
    });
    try app.get("/reference/request/items/{item_id}", requestWithPathParam, .{
        .summary = "Request API: path params and content-type header",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_request_path_param",
    });
}
