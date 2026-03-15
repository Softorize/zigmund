const std = @import("std");
const zigmund = @import("zigmund");

// -- Types used only as input (Body) --
const CreateItemRequest = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
};

// -- Types used only as output (response_model) --
const ItemResponse = struct {
    id: u32,
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
    price_with_tax: f64,
};

// -- Type used in BOTH input and output positions (dual-use) --
const SharedItem = struct {
    name: []const u8,
    price: f64,
    active: bool = true,
};

fn createItemHandler(
    body: zigmund.Body(CreateItemRequest, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const input = body.value.?;
    return zigmund.Response.json(allocator, .{
        .id = @as(u32, 1),
        .name = input.name,
        .description = input.description,
        .price = input.price,
        .price_with_tax = input.price * 1.1,
    });
}

fn dualUseHandler(
    body: zigmund.Body(SharedItem, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = body;
    return zigmund.Response.json(allocator, .{
        .name = "test",
        .price = @as(f64, 9.99),
        .active = true,
    });
}

fn listHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .items = &[_]u8{},
    });
}

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, idx, needle)) |pos| {
        count += 1;
        idx = pos + needle.len;
    }
    return count;
}

test "different input and output types produce separate schemas" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "separate-schemas-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/items", createItemHandler, .{
        .summary = "Create an item",
        .response_model = ItemResponse,
        .status_code = .created,
    });

    try app.get("/items", listHandler, .{
        .summary = "List items",
        .response_model = ItemResponse,
    });

    const doc = try app.openapi();

    // Verify both paths exist
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/items\"") != null);

    // The response model schema should appear in components/schemas
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"schemas\"") != null);

    // CreateItemRequest is not a response_model, so it should NOT appear in schemas.
    // It appears as an inline request body schema under requestBodies.
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"requestBodies\"") != null);

    // The ItemResponse schema should contain its specific fields
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"price_with_tax\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"id\"") != null);

    // The request body should contain CreateItemRequest fields
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"price\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\"") != null);

    // The schemas section should reference ItemResponse (the type name includes
    // the module path, so we check for the struct name portion)
    try std.testing.expect(std.mem.indexOf(u8, doc, "ItemResponse") != null);
}

test "same type in both body and response_model produces Input/Output schemas" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "dual-use-schema-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/shared", dualUseHandler, .{
        .summary = "Dual-use type endpoint",
        .response_model = SharedItem,
    });

    const doc = try app.openapi();

    // When the same type is used for both Body and response_model,
    // the generator should emit separate Input and Output schemas.
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"schemas\"") != null);

    // Should have _Output and _Input suffixed schema names
    try std.testing.expect(std.mem.indexOf(u8, doc, "_Output") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "_Input") != null);

    // Both schemas should contain the SharedItem fields
    try std.testing.expect(countOccurrences(doc, "\"name\"") >= 2);
    try std.testing.expect(countOccurrences(doc, "\"price\"") >= 2);
    try std.testing.expect(countOccurrences(doc, "\"active\"") >= 2);

    // The response should reference the _Output schema
    try std.testing.expect(std.mem.indexOf(u8, doc, "_Output") != null);
}

test "non-dual-use response models keep original name" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "non-dual-use-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    // Only response_model, no Body — should NOT get _Output suffix
    try app.get("/items", listHandler, .{
        .summary = "List items",
        .response_model = ItemResponse,
    });

    const doc = try app.openapi();

    // Should have the schema without suffix
    try std.testing.expect(std.mem.indexOf(u8, doc, "ItemResponse") != null);

    // Should NOT have _Output or _Input suffixes
    try std.testing.expectEqual(@as(usize, 0), countOccurrences(doc, "_Output"));
    try std.testing.expectEqual(@as(usize, 0), countOccurrences(doc, "_Input"));
}
