const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/parameters/";

/// Demonstrates Query, Path, Header, Cookie, and Body parameter markers.
fn parameterDemo(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    q: zigmund.Query([]const u8, .{ .description = "Search query" }),
    x_token: zigmund.Header([]const u8, .{ .alias = "x-token", .description = "Auth token header" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .path_param = item_id.value.?,
        .query_param = q.value.?,
        .header_param = x_token.value.?,
        .markers = .{
            .Path = "zigmund.Path(T, PathOptions) - extract from URL path",
            .Query = "zigmund.Query(T, QueryOptions) - extract from query string",
            .Header = "zigmund.Header(T, HeaderOptions) - extract from request headers",
            .Cookie = "zigmund.Cookie(T, CookieOptions) - extract from cookies",
            .Body = "zigmund.Body(T, BodyOptions) - extract from JSON body",
        },
    });
}

const CreatePayload = struct {
    name: []const u8,
    price: f64,
};

fn bodyParamDemo(
    body: zigmund.Body(CreatePayload, .{ .description = "JSON body with name and price" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const payload = body.value.?;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .name = payload.name,
        .price = payload.price,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/parameters/items/{item_id}", parameterDemo, .{
        .summary = "Query, Path, and Header parameter markers",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_parameters_demo",
    });
    try app.post("/reference/parameters/items", bodyParamDemo, .{
        .summary = "Body parameter marker with struct extraction",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_parameters_body",
    });
}
