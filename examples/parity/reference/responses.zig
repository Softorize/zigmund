const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/responses/";

/// Demonstrates ResponseSpec for declaring additional OpenAPI responses.
fn getItemWithResponses(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    if (item_id.value.? == 0) {
        return (try zigmund.Response.json(allocator, .{
            .detail = "Item not found",
        })).withStatus(.not_found);
    }
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .id = item_id.value.?,
        .name = "Widget",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/responses/items/{item_id}", getItemWithResponses, .{
        .summary = "ResponseSpec declares additional OpenAPI response codes",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_responses_get_item",
        .responses = &.{
            .{ .status_code = .not_found, .description = "Item not found" },
            .{ .status_code = .unprocessable_content, .description = "Validation error" },
        },
    });
}
