# Schema Examples

Add request and response examples to your OpenAPI schema so that documentation tools display realistic, copy-pasteable payloads alongside your endpoint definitions.

## Overview

Well-documented APIs include examples that show consumers exactly what to send and what to expect back. Zigmund supports OpenAPI's `examples` feature through the `.openapi_request_examples` and `.openapi_response_examples` route configuration options. Each example has a name, a summary, and a raw JSON value. These appear in Swagger UI's "Example Value" dropdown and in Redoc's example panels.

Examples are purely documentation -- they do not affect runtime behavior or validation. They complement the schema (which describes the shape) with concrete values (which show a realistic instance).

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

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
```

## How It Works

1. **Define the body model.** The `Item` struct describes the request body shape. The `Body` wrapper's `.description` option adds a human-readable description to the OpenAPI request body.

2. **Add request examples.** `.openapi_request_examples` takes a list of example objects. Each has:
   - `.name` -- A unique key used to identify the example in the dropdown.
   - `.summary` -- A short description displayed to the user.
   - `.value_json` -- The raw JSON string representing a complete, valid request body. Zig's `\\` multiline string syntax is convenient for inline JSON.

3. **Add response examples.** `.openapi_response_examples` is grouped by status code. Each status code entry contains its own list of examples, following the same `.name` / `.summary` / `.value_json` structure. This grouping allows you to show different example responses for `200`, `400`, `404`, etc.

4. **Multiple examples per direction.** The request has two examples ("normal" and "converted"), letting documentation tools present a dropdown so consumers can switch between scenarios. The response has one example for the `200 OK` case.

5. **Runtime behavior is unchanged.** Examples are injected into the OpenAPI JSON schema only. They do not affect validation, serialization, or any runtime logic.

## Key Points

- Use `\\` (Zig multiline string literals) for inline JSON to avoid escaping quotes. Each line of the multiline string becomes part of the JSON value.
- Example names must be unique within their scope (per-endpoint, per-direction). They serve as keys in the OpenAPI `examples` map.
- Response examples are keyed by status code. You can provide different examples for `200`, `400`, `422`, etc., aligning with the `.responses` entries in [Path Operation Configuration](path-operation-configuration.md).
- Swagger UI displays examples in a dropdown when multiple are defined. Redoc shows them inline or in tabs.
- Combining `.openapi_request_examples` with the `Body` wrapper's `.description` produces comprehensive documentation: a schema describing the shape, a description explaining the purpose, and examples showing real payloads.
- Examples are not validated against the schema at build time. Ensure they match your struct definitions manually, or they may confuse consumers.

## See Also

- [Path Operation Configuration](path-operation-configuration.md) -- The full set of route configuration options, including `.responses` for additional status codes.
- [API Metadata and Tags](metadata.md) -- API-level documentation settings.
- [Extra Models](extra-models.md) -- Separate input/output models to document different request and response shapes.
- [Request Body](request-body.md) -- Basics of parsing JSON request bodies with the `Body` wrapper.
