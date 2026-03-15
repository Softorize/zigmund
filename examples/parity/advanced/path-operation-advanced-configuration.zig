const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/path-operation-advanced-configuration/";

/// Demonstrates advanced route configuration options:
/// - include_in_schema: controls OpenAPI visibility
/// - deprecated: marks the route as deprecated in docs
/// - operation_id: custom OpenAPI operation identifier
/// - response_model: typed response schema generation
/// - status_code: custom default status code

const ItemResponse = struct {
    name: []const u8,
    price: f64,
    in_stock: bool = true,
};

fn getItem(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .name = "Widget",
        .price = 9.99,
        .in_stock = true,
    });
}

fn deprecatedItem(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .name = "Old Widget",
        .price = 4.99,
        .deprecated = true,
    });
}

fn internalEndpoint(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "This endpoint is hidden from the OpenAPI schema",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Standard route with response_model and custom operation_id
    try app.get("/advanced/path-operation-advanced-configuration", getItem, .{
        .summary = "Advanced route with response model and custom operation ID",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_get_item_configured",
        .response_model = ItemResponse,
    });

    // Deprecated route — shown in docs with strikethrough
    try app.get("/advanced/path-operation-advanced-configuration/old", deprecatedItem, .{
        .summary = "Deprecated item endpoint",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_deprecated_item",
        .deprecated = true,
    });

    // Internal route hidden from OpenAPI schema
    try app.get("/advanced/path-operation-advanced-configuration/internal", internalEndpoint, .{
        .summary = "Internal endpoint excluded from schema",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_internal_hidden",
        .include_in_schema = false,
    });
}
