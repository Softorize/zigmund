# Additional Responses

Document multiple possible response types for a single endpoint in the OpenAPI specification. This allows API consumers to understand all the response shapes an endpoint may return.

## Overview

A single endpoint often returns different response shapes depending on the outcome. For example, a GET endpoint might return a 200 with item data or a 404 with an error message. Zigmund lets you declare these additional responses in the route options via the `responses` field, which generates the corresponding entries in the OpenAPI spec.

This is the Zig equivalent of FastAPI's `responses` parameter in route decorators.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn getItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const id = item_id.value.?;
    if (id == 0) {
        return (zigmund.Response.json(allocator, .{
            .message = "Item not found",
        }) catch unreachable).withStatus(.not_found);
    }
    return zigmund.Response.json(allocator, .{
        .item_id = id,
        .name = "Widget",
        .description = "A useful widget",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/items/{item_id}", getItem, .{
        .summary = "Get item with additional response specifications",
        .responses = &.{
            .{ .status_code = .not_found, .description = "Item not found" },
            .{ .status_code = .bad_request, .description = "Invalid item ID" },
        },
    });
}
```

## How It Works

### 1. Declaring Additional Responses

The `responses` field in route options accepts a slice of response descriptors. Each descriptor specifies a status code and a description:

```zig
.responses = &.{
    .{ .status_code = .not_found, .description = "Item not found" },
    .{ .status_code = .bad_request, .description = "Invalid item ID" },
},
```

These entries appear in the OpenAPI specification under the operation's `responses` section alongside the default 200 response. API documentation tools (Swagger UI, ReDoc) will display all declared responses.

### 2. Returning Different Status Codes in the Handler

The handler itself decides which response to return at runtime. Use `.withStatus()` to set a non-default status code:

```zig
if (id == 0) {
    return (try zigmund.Response.json(allocator, .{
        .message = "Item not found",
    })).withStatus(.not_found);
}
```

The `responses` declaration in route options is purely for documentation. Zigmund does not enforce that the handler only returns the declared status codes -- it is the handler's responsibility to match the documented behavior.

### 3. Default Response

The default (primary) response is always included in the OpenAPI spec based on the route's `status_code` option (which defaults to `.ok` / 200). The `responses` field adds entries beyond this default.

## Key Points

- The `responses` field documents additional response types in the OpenAPI spec without affecting runtime behavior.
- Each response entry requires a `status_code` and a `description`.
- The handler is responsible for actually returning the correct status code using `.withStatus()`.
- The default success response (200 OK) is always included automatically.
- This feature is essential for generating accurate API client code and comprehensive documentation.

## See Also

- [Additional Status Codes](additional-status-codes.md) -- set the default status code for a route.
- [Response Change Status Code](response-change-status-code.md) -- dynamically change the status code in a handler.
- [Path Operation Advanced Configuration](path-operation-advanced-configuration.md) -- other advanced route options.
