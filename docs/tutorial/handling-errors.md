# Handling Errors

Return meaningful error responses using Zig error unions and custom exception handlers.

## Overview

In any real API, things go wrong: a requested item does not exist, a user lacks permissions, or an upstream service is down. Zigmund leverages Zig's built-in error union system to handle these cases. Your handler can return an error at any point, and Zigmund will catch it. If you have registered an exception handler for that error set, it runs and produces a proper HTTP response. Otherwise, Zigmund returns a generic 500 error.

This pattern replaces the try/except blocks and HTTPException raises you would use in FastAPI, giving you compile-time guarantees that all error paths are accounted for.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

// 1. Define a custom error set.
const InventoryError = error{ItemUnavailable};

// 2. Handler that may return an error.
fn readInventoryItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // Return an error when item_id is 0 (simulating "not found").
    if (item_id.value.? == 0) return InventoryError.ItemUnavailable;

    return zigmund.Response.json(allocator, .{
        .item_id = item_id.value.?,
        .available = true,
    });
}

// 3. Exception handler that converts the error into an HTTP response.
fn inventoryErrorHandler(
    req: *zigmund.Request,
    err: anyerror,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    _ = err;
    var response = try zigmund.Response.json(allocator, .{
        .detail = "Item is unavailable",
    });
    return response.withStatus(.not_found);
}

// 4. Register the handler for the InventoryError error set.
// app.addExceptionHandler(InventoryError, inventoryErrorHandler)
// app.get("/items/{item_id}", readInventoryItem, .{})
```

### Request examples

```bash
# Successful request
curl http://127.0.0.1:8000/items/42
# {"item_id": 42, "available": true}

# Error case -- item_id is 0
curl http://127.0.0.1:8000/items/0
# HTTP 404: {"detail": "Item is unavailable"}
```

## How It Works

### 1. Define an error set

Zig's `error` keyword creates a named set of error values:

```zig
const InventoryError = error{ItemUnavailable};
```

You can include multiple error values:

```zig
const InventoryError = error{
    ItemUnavailable,
    ItemExpired,
    InsufficientStock,
};
```

Each value is a distinct error that can be returned from any function whose return type includes `!` (error union).

### 2. Return errors from handlers

Because the handler return type is `!zigmund.Response` (an error union), you can return any error at any point:

```zig
fn readInventoryItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    if (item_id.value.? == 0) return InventoryError.ItemUnavailable;
    // Normal response path...
}
```

This is similar to raising an exception in Python, but it is a first-class part of the type system. The compiler tracks which errors a function can return and ensures they are handled.

### 3. Write an exception handler

An exception handler is a function with this signature:

```zig
fn handler(
    req: *zigmund.Request,
    err: anyerror,
    allocator: std.mem.Allocator,
) !zigmund.Response
```

| Parameter   | Description                                              |
|-------------|----------------------------------------------------------|
| `req`       | The original request (useful for logging or context).    |
| `err`       | The error value that was returned.                       |
| `allocator` | Per-request allocator for building the response.         |

The handler must return a `Response`. This is where you set the status code, construct an error body, and add any headers the client needs.

### 4. Register with addExceptionHandler

Call `app.addExceptionHandler` before registering routes. The first argument is the error set type, the second is the handler function:

```zig
try app.addExceptionHandler(InventoryError, inventoryErrorHandler);
```

When any handler returns an error that belongs to `InventoryError`, Zigmund calls `inventoryErrorHandler` instead of sending a generic 500 response.

### 5. Multiple exception handlers

You can register handlers for different error sets. Each one handles its own set of errors:

```zig
try app.addExceptionHandler(InventoryError, inventoryErrorHandler);
try app.addExceptionHandler(AuthError, authErrorHandler);
try app.addExceptionHandler(ValidationError, validationErrorHandler);
```

### 6. The err parameter

The `err` parameter is typed as `anyerror`, which means you can match on it if your error set contains multiple values:

```zig
fn inventoryErrorHandler(
    req: *zigmund.Request,
    err: anyerror,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    const message: []const u8 = if (err == error.ItemExpired)
        "Item has expired"
    else
        "Item is unavailable";

    var response = try zigmund.Response.json(allocator, .{ .detail = message });
    return response.withStatus(.not_found);
}
```

## Key Points

- Zigmund uses Zig's native error unions (`!`) for error handling. There is no exception class hierarchy.
- Define error sets with `const MyError = error{...}` to create domain-specific error categories.
- Handlers return errors with a plain `return` statement: `return MyError.SomethingWrong;`.
- Register exception handlers with `app.addExceptionHandler(ErrorSet, handlerFn)` to convert errors into HTTP responses.
- Unhandled errors produce a generic 500 Internal Server Error.
- The `err` parameter in exception handlers is `anyerror`, allowing you to branch on specific error values within the set.

## See Also

- [Response Status Code](response-status-code.md) -- setting status codes on normal responses.
- [First Steps](first-steps.md) -- the basic handler return type (`!zigmund.Response`).
- [Path Parameters](path-parameters.md) -- path parameter validation that may produce errors.
