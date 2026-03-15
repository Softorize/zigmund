const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/async-tests/";

/// Demonstrates test patterns using TestClient for integration-style testing.
/// Zig does not have async/await like Python, but TestClient provides
/// synchronous request dispatch that exercises the full handler pipeline
/// without starting a network server.

fn getItems(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .items = &[_][]const u8{ "item-a", "item-b", "item-c" },
        .count = @as(u32, 3),
    });
}

fn createItem(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var response = try zigmund.Response.json(allocator, .{
        .page = source_page,
        .created = true,
        .message = "Item created successfully",
    });
    return response.withStatus(.created);
}

/// Example test usage with TestClient:
///
///   var app = try zigmund.App.init(std.testing.allocator, .{
///       .title = "Test", .version = "1.0",
///   });
///   defer app.deinit();
///   try buildExample(&app);
///
///   var client = zigmund.TestClient.init(std.testing.allocator, &app);
///   defer client.deinit();
///
///   // GET request
///   var get_resp = try client.get("/advanced/async-tests/items");
///   defer get_resp.deinit(std.testing.allocator);
///   // verify get_resp.status == .ok
///
///   // POST request
///   var post_resp = try client.post("/advanced/async-tests/items", "{}");
///   defer post_resp.deinit(std.testing.allocator);
///   // verify post_resp.status == .created

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/async-tests/items", getItems, .{
        .summary = "List items for TestClient integration testing",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_async_tests_list",
    });

    try app.post("/advanced/async-tests/items", createItem, .{
        .summary = "Create item for TestClient integration testing",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_async_tests_create",
    });
}
