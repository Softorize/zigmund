const std = @import("std");
const zigmund = @import("zigmund");

const QueryModel = struct {
    page: u32 = 1,
    per_page: u32 = 20,
    search: ?[]const u8 = null,
    active: bool = true,
    tags: []const []const u8,
};

fn defaultsHandler(
    query: zigmund.Query(QueryModel, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .has_query = query.value != null,
    });
}

fn examplesHandler(
    item_id: zigmund.Path(u64, .{
        .alias = "item_id",
        .description = "The item identifier",
        .openapi_examples = &.{
            .{
                .name = "first_item",
                .summary = "First item",
                .value_json = "1",
            },
            .{
                .name = "large_item",
                .summary = "Large ID",
                .description = "An item with a large ID",
                .value_json = "9999",
            },
        },
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .item_id = item_id.value,
    });
}

test "openapi schema includes default values from struct fields" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "defaults-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/items", defaultsHandler, .{});

    const doc = try app.openapi();

    // page has default 1
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"page\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"default\":1") != null);

    // per_page has default 20
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"per_page\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"default\":20") != null);

    // active has default true
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"active\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"default\":true") != null);

    // search is ?[]const u8 = null, so default is null
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"search\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"default\":null") != null);

    // tags has no default (required, no default_value_ptr) -- no "default" in its schema
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"tags\"") != null);
}

test "openapi parameter includes custom examples" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "examples-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/items/{item_id}", examplesHandler, .{});

    const doc = try app.openapi();

    // Verify examples are emitted in the parameter
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"examples\":{\"first_item\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"summary\":\"First item\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"value\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"large_item\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"summary\":\"Large ID\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"description\":\"An item with a large ID\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"value\":9999") != null);
}

test "swagger ui includes oauth2 redirect url when configured" {
    const html = try zigmund.docs_ui.renderSwagger(std.testing.allocator, "Test App", "/openapi.json", .{
        .oauth2_redirect_url = "/docs/oauth2-redirect",
    });
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "oauth2RedirectUrl:") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "/docs/oauth2-redirect") != null);
}

test "swagger ui omits oauth2 redirect url when not configured" {
    const html = try zigmund.docs_ui.renderSwagger(std.testing.allocator, "Test App", "/openapi.json", .{});
    defer std.testing.allocator.free(html);

    // When not configured, the oauth2RedirectUrl config line should not appear
    // in the SwaggerUIBundle init block. We check for the specific redirect URL
    // pattern that our config would inject (bundle JS has its own internal refs).
    try std.testing.expect(std.mem.indexOf(u8, html, "/docs/oauth2-redirect") == null);
}
