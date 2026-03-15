# Additional Status Codes

Return HTTP status codes other than the default 200 OK. Zigmund supports setting both the default status code for a route and dynamically changing the status code within a handler.

## Overview

Not every endpoint should return 200 OK. A POST that creates a resource should return 201 Created. A DELETE that removes a resource should return 204 No Content. A background task might return 202 Accepted. Zigmund provides two mechanisms for this: the `status_code` route option sets the documented default, and `.withStatus()` on a `Response` overrides the status code at runtime.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn createItem(allocator: std.mem.Allocator) !zigmund.Response {
    return (try zigmund.Response.json(allocator, .{
        .name = "New item",
        .status = "created",
    })).withStatus(.created);
}

fn deleteItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
) zigmund.Response {
    _ = item_id;
    return zigmund.Response.text("").withStatus(.no_content);
}

fn updateItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const id = item_id.value.?;
    if (id == 0) {
        return (try zigmund.Response.json(allocator, .{
            .detail = "Item not found",
        })).withStatus(.not_found);
    }
    return zigmund.Response.json(allocator, .{
        .item_id = id,
        .name = "Updated item",
    });
}

fn acceptedTask(allocator: std.mem.Allocator) !zigmund.Response {
    return (try zigmund.Response.json(allocator, .{
        .task_id = "abc-123",
        .status = "processing",
    })).withStatus(.accepted);
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/items", createItem, .{
        .summary = "Create an item with 201 Created status",
        .status_code = .created,
    });
    try app.delete("/items/{item_id}", deleteItem, .{
        .summary = "Delete an item with 204 No Content status",
        .status_code = .no_content,
    });
    try app.put("/items/{item_id}", updateItem, .{
        .summary = "Update an item or return 404",
        .responses = &.{
            .{ .status_code = .not_found, .description = "Item not found" },
        },
    });
    try app.post("/tasks", acceptedTask, .{
        .summary = "Start a background task with 202 Accepted",
        .status_code = .accepted,
    });
}
```

## How It Works

### 1. Setting the Default Status Code

The `status_code` field in route options tells the OpenAPI spec what the primary success status code is:

```zig
try app.post("/items", createItem, .{
    .status_code = .created,  // 201
});
```

This affects the OpenAPI documentation. Swagger UI and ReDoc will show 201 as the expected success response instead of 200.

### 2. Using .withStatus() at Runtime

In the handler, chain `.withStatus()` onto the response to set the actual HTTP status code:

```zig
return (try zigmund.Response.json(allocator, .{
    .name = "New item",
})).withStatus(.created);
```

Common status codes:

| Enum Value       | HTTP Code | Typical Use                        |
|------------------|-----------|------------------------------------|
| `.ok`            | 200       | Successful GET, PUT, PATCH         |
| `.created`       | 201       | Successful POST that creates       |
| `.accepted`      | 202       | Request accepted for processing    |
| `.no_content`    | 204       | Successful DELETE with no body     |
| `.not_found`     | 404       | Resource does not exist            |
| `.bad_request`   | 400       | Invalid input                      |

### 3. Combining with Additional Responses

Use the `responses` field to document error cases alongside the primary status code:

```zig
try app.put("/items/{item_id}", updateItem, .{
    .responses = &.{
        .{ .status_code = .not_found, .description = "Item not found" },
    },
});
```

### 4. No-Body Responses

For status codes like 204 No Content, return an empty text response:

```zig
return zigmund.Response.text("").withStatus(.no_content);
```

## Key Points

- Use the `status_code` route option to document the primary success code in OpenAPI.
- Use `.withStatus()` on the response to set the actual HTTP status code at runtime.
- The route option and runtime status are independent -- the route option is for documentation; the handler controls the actual response.
- Empty-body responses (204) can be created with `Response.text("")`.
- Combine `status_code` with `responses` to fully document all possible outcomes.

## See Also

- [Additional Responses](additional-responses.md) -- document multiple response types in OpenAPI.
- [Response Change Status Code](response-change-status-code.md) -- dynamically change the status code based on logic.
- [Response Directly](response-directly.md) -- return responses without a response model.
