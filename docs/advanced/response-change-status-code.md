# Response Change Status Code

Dynamically change the HTTP status code of a response based on runtime logic. A single handler can return different status codes depending on the outcome of the request.

## Overview

Many endpoints need to return different status codes depending on what happens at runtime. A PUT endpoint might return 200 OK if an item was updated or 201 Created if it was newly created. A GET endpoint might return 200 OK for a found item or 404 Not Found otherwise. Zigmund's `.withStatus()` method on `Response` lets you set the status code conditionally within the handler.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn createOrUpdate(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const id = item_id.value.?;
    // Simulate: even IDs are existing items (200), odd IDs are new (201 Created)
    if (id % 2 == 0) {
        return zigmund.Response.json(allocator, .{
            .item_id = id,
            .action = "updated",
        });
    }
    return (try zigmund.Response.json(allocator, .{
        .item_id = id,
        .action = "created",
    })).withStatus(.created);
}

fn conditionalNotFound(
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
        .name = "Found item",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.put("/items/{item_id}", createOrUpdate, .{
        .summary = "Create or update item with dynamic status code",
        .responses = &.{
            .{ .status_code = .created, .description = "Item created" },
        },
    });
    try app.get("/items/{item_id}", conditionalNotFound, .{
        .summary = "Get item or return 404 dynamically",
        .responses = &.{
            .{ .status_code = .not_found, .description = "Item not found" },
        },
    });
}
```

## How It Works

### 1. Default Status Code

When you return a response without calling `.withStatus()`, Zigmund uses the default status code for the HTTP method (typically 200 OK):

```zig
return zigmund.Response.json(allocator, .{
    .item_id = id,
    .action = "updated",
});
// Status: 200 OK
```

### 2. Overriding with .withStatus()

Chain `.withStatus()` to change the status code:

```zig
return (try zigmund.Response.json(allocator, .{
    .item_id = id,
    .action = "created",
})).withStatus(.created);
// Status: 201 Created
```

Note the parentheses around the `try` expression. Since `.withStatus()` is chained, you need to wrap the `try` to ensure proper error handling before the method call.

### 3. Conditional Status Codes

Use standard Zig control flow to decide which status code to return:

```zig
if (id == 0) {
    return (try zigmund.Response.json(allocator, .{
        .detail = "Item not found",
    })).withStatus(.not_found);
}
return zigmund.Response.json(allocator, .{
    .item_id = id,
    .name = "Found item",
});
```

### 4. Documenting Multiple Status Codes

When a handler can return different status codes, document them in the route options using `responses`:

```zig
try app.put("/items/{item_id}", createOrUpdate, .{
    .responses = &.{
        .{ .status_code = .created, .description = "Item created" },
    },
});
```

This ensures the OpenAPI spec accurately reflects all possible outcomes.

## Key Points

- `.withStatus()` overrides the response status code and can be chained onto any response constructor.
- The default status code is 200 OK when `.withStatus()` is not called.
- Use standard Zig `if`/`switch` statements to decide the status code at runtime.
- Wrap `try` in parentheses when chaining `.withStatus()` on a fallible response constructor.
- Always document alternative status codes in route options using the `responses` field.

## See Also

- [Additional Status Codes](additional-status-codes.md) -- set the default status code for a route.
- [Additional Responses](additional-responses.md) -- document multiple response types.
- [Response Directly](response-directly.md) -- return responses without a response model.
