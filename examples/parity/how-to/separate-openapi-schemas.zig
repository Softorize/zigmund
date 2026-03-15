const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/separate-openapi-schemas/";

/// Demonstrates using separate types for request body and response model.
/// By using different Zig structs for input (Body) and output (response_model),
/// OpenAPI generates distinct schemas for each, giving fine-grained control
/// over what clients send vs. what they receive.

const CreateItemRequest = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
    tax: ?f64 = null,
};

const ItemResponse = struct {
    id: u32,
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
    tax: ?f64 = null,
    price_with_tax: f64,
};

fn createItem(
    body: zigmund.Body(CreateItemRequest, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const input = body.value.?;
    const tax = input.tax orelse 0.0;
    return (try zigmund.Response.json(allocator, .{
        .page = source_page,
        .id = @as(u32, 1),
        .name = input.name,
        .description = input.description,
        .price = input.price,
        .tax = input.tax,
        .price_with_tax = input.price + tax,
    })).withStatus(.created);
}

fn schemaInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "Separate input/output schemas for OpenAPI",
        .input_schema = "CreateItemRequest: name, description?, price, tax?",
        .output_schema = "ItemResponse: id, name, description?, price, tax?, price_with_tax",
        .note = "OpenAPI generates distinct schemas for Body(T) and response_model",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/separate-openapi-schemas", schemaInfo, .{
        .summary = "Separate input/output OpenAPI schemas overview",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_separate_schemas_info",
    });

    try app.post("/how-to/separate-openapi-schemas/items", createItem, .{
        .summary = "Create item with separate request/response schemas",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_separate_schemas_create_item",
        .response_model = ItemResponse,
        .status_code = .created,
    });
}
