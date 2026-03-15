const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/schema-extra-example/";

const Item = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
    tax: ?f64 = null,
};

fn createItem(
    body: zigmund.Body(Item, .{ .description = "Item to create with pricing info" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const item = body.value.?;
    return zigmund.Response.json(allocator, .{
        .name = item.name,
        .description = item.description orelse "No description",
        .price = item.price,
        .tax = item.tax,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/schema-extra-example/items", createItem, .{
        .summary = "Create item with OpenAPI request/response examples",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_schema_extra_example_create_item",
        .openapi_request_examples = &.{
            .{
                .name = "normal",
                .summary = "A normal item",
                .value_json =
                \\{"name":"Foo","description":"A very nice item","price":35.4,"tax":3.2}
                ,
            },
            .{
                .name = "converted",
                .summary = "An item with automatic tax conversion",
                .value_json =
                \\{"name":"Bar","price":62.0,"tax":null}
                ,
            },
        },
        .openapi_response_examples = &.{
            .{
                .status_code = .ok,
                .examples = &.{
                    .{
                        .name = "normal_response",
                        .summary = "Response for a normal item",
                        .value_json =
                        \\{"name":"Foo","description":"A very nice item","price":35.4,"tax":3.2}
                        ,
                    },
                },
            },
        },
    });
}
