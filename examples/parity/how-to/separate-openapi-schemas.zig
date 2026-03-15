const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/separate-openapi-schemas/";

/// Demonstrates using separate types for request body and response model.
/// By using different Zig structs for input (Body) and output (response_model),
/// OpenAPI generates distinct schemas for each, giving fine-grained control
/// over what clients send vs. what they receive.
///
/// **Recommended**: Use different struct types for input and output (shown below
/// with CreateItemRequest and ItemResponse).
///
/// **Dual-use**: When the same struct type is used for both Body(T) and
/// response_model = T, the generator automatically emits T_Input and T_Output
/// schemas in the OpenAPI spec so that code generators produce distinct classes.

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

/// Dual-use type: same struct for both input and output.
/// The generator will emit SharedItem_Input and SharedItem_Output schemas.
const SharedItem = struct {
    name: []const u8,
    price: f64,
    active: bool = true,
};

fn updateSharedItem(
    body: zigmund.Body(SharedItem, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const input = body.value.?;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .name = input.name,
        .price = input.price,
        .active = input.active,
    });
}

fn schemaInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "Separate input/output schemas for OpenAPI",
        .input_schema = "CreateItemRequest: name, description?, price, tax?",
        .output_schema = "ItemResponse: id, name, description?, price, tax?, price_with_tax",
        .dual_use_note = "SharedItem used as both Body and response_model emits SharedItem_Input and SharedItem_Output",
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

    try app.put("/how-to/separate-openapi-schemas/shared", updateSharedItem, .{
        .summary = "Update shared item (dual-use type produces Input/Output schemas)",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_separate_schemas_shared_item",
        .response_model = SharedItem,
    });
}
