# Error Handling in Zigmund

Error handling is one of the areas where Zig and Python differ most
fundamentally. Python uses exceptions -- objects thrown at runtime that unwind
the call stack until a matching `except` block catches them. Zig uses **error
unions** -- a type-level mechanism where functions declare the errors they can
return as part of their return type. There is no hidden control flow, no stack
unwinding, and no performance penalty for code that does not produce errors.

Zigmund bridges these two models by providing exception handlers that map Zig
errors to HTTP responses, following patterns that will feel familiar to FastAPI
developers.

---

## Error Unions: `!zigmund.Response`

In Zig, a function that can fail returns an **error union**. The `!` syntax is
shorthand for an error union where the error set is inferred:

```zig
fn handler(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{ .ok = true });
}
```

The return type `!zigmund.Response` means "either a `Response` on success, or an
error value on failure." This is conceptually similar to Python's approach of
either returning a value or raising an exception, but with a critical difference:
the error is part of the type system and must be handled explicitly by every
caller.

### Comparison with Python

```python
# Python -- exceptions are invisible in the type signature
def handler():
    if not found:
        raise HTTPException(status_code=404, detail="Not found")
    return {"ok": True}
```

```zig
// Zig -- errors are visible in the return type
fn handler(allocator: std.mem.Allocator) !zigmund.Response {
    if (!found) {
        return error.NotFound;
    }
    return zigmund.Response.json(allocator, .{ .ok = true });
}
```

In the Python version, nothing in the function signature tells you it can raise
`HTTPException`. In the Zig version, the `!` in the return type makes it
explicit that this function can return an error.

---

## Custom Error Sets

Zig lets you define named error sets to categorize the errors your application
can produce:

```zig
const InventoryError = error{ItemUnavailable};
```

This declares an error set with a single member, `ItemUnavailable`. You can
have multiple members:

```zig
const UserError = error{
    UserNotFound,
    EmailAlreadyExists,
    InvalidCredentials,
};
```

Error sets are types. You can use them in error unions to specify exactly which
errors a function can return:

```zig
fn findUser(id: u32) UserError!User {
    // Can only return UserNotFound, EmailAlreadyExists, or InvalidCredentials
}
```

When using `!` (inferred error set), the compiler figures out the error set
automatically from all possible error paths in the function body.

---

## Returning Errors from Handlers

To return an error from a handler, use the `return` keyword with an error value:

```zig
const InventoryError = error{ItemUnavailable};

fn readInventoryItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    if (item_id.value.? == 0) {
        return InventoryError.ItemUnavailable;
    }

    return zigmund.Response.json(allocator, .{
        .item_id = item_id.value.?,
        .available = true,
    });
}
```

When a handler returns an error, Zigmund checks its registered exception
handlers for one that matches the error set. If no handler matches, the
framework returns a generic 500 Internal Server Error response.

---

## Exception Handlers

Exception handlers in Zigmund work similarly to FastAPI's exception handlers.
You register a function that will be called when a specific error set is
returned from a handler:

```zig
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

pub fn buildExample(app: *zigmund.App) !void {
    try app.addExceptionHandler(InventoryError, inventoryErrorHandler);
    try app.get("/items/{item_id}", readInventoryItem, .{});
}
```

### How `addExceptionHandler` works

The `addExceptionHandler` method takes two arguments:

1. **An error set type** -- tells Zigmund which errors this handler covers. The
   framework extracts the error names at compile time and matches against them
   at runtime.
2. **A handler function** -- called when a matching error is returned. It
   receives the request, the error value, and an allocator, and must return a
   `Response`.

The handler function signature is:

```zig
fn(req: *zigmund.Request, err: anyerror, allocator: std.mem.Allocator) !zigmund.Response
```

### Comparison with FastAPI

```python
# FastAPI
class ItemUnavailableError(Exception):
    pass

@app.exception_handler(ItemUnavailableError)
async def item_unavailable_handler(request: Request, exc: ItemUnavailableError):
    return JSONResponse(
        status_code=404,
        content={"detail": "Item is unavailable"},
    )
```

```zig
// Zigmund
const InventoryError = error{ItemUnavailable};

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

// In setup:
try app.addExceptionHandler(InventoryError, inventoryErrorHandler);
```

The pattern is structurally identical. Define an error type, write a handler
that converts it to a response, and register the association.

---

## HTTPException

For cases where you want to return an HTTP error directly without registering a
custom exception handler, Zigmund provides `HTTPException`. This is a struct
(not an error value) that carries a status code and detail message:

```zig
pub const HTTPException = struct {
    status_code: std.http.Status,
    detail: []const u8,
    headers: []const std.http.Header = &.{},
};
```

You can use HTTPException in exception handlers or anywhere you need to
construct a structured error response. This mirrors FastAPI's `HTTPException`:

```python
# FastAPI
from fastapi import HTTPException
raise HTTPException(status_code=404, detail="Item not found")
```

---

## ProblemDetail: RFC 7807 Responses

For structured error responses that follow the RFC 7807 "Problem Details for
HTTP APIs" standard, Zigmund provides the `ProblemDetail` struct and convenience
functions:

```zig
pub const ProblemDetail = struct {
    type_uri: []const u8 = "about:blank",
    title: []const u8,
    status: u16,
    detail: ?[]const u8 = null,
    instance: ?[]const u8 = null,
};
```

Use `problemResponse` to create a response from a `ProblemDetail`:

```zig
fn handler(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.problemResponse(allocator, .{
        .title = "Not Found",
        .status = 404,
        .detail = "The requested item does not exist",
        .instance = "/items/42",
    });
}
```

This produces a response with:
- Status code: 404
- Content-Type: `application/problem+json`
- Body:
```json
{
    "type": "about:blank",
    "title": "Not Found",
    "status": 404,
    "detail": "The requested item does not exist",
    "instance": "/items/42"
}
```

### Convenience constructors

Zigmund provides shorthand functions for common HTTP error statuses:

```zig
// 404 Not Found
return zigmund.problemNotFound(allocator, "Resource not found");

// 400 Bad Request
return zigmund.problemBadRequest(allocator, "Invalid input");

// 401 Unauthorized
return zigmund.problemUnauthorized(allocator, "Authentication required");

// 403 Forbidden
return zigmund.problemForbidden(allocator, "Access denied");

// 409 Conflict
return zigmund.problemConflict(allocator, "Resource already exists");

// 422 Unprocessable Entity
return zigmund.problemUnprocessableEntity(allocator, "Validation failed");

// 500 Internal Server Error
return zigmund.problemInternalServerError(allocator, "Something went wrong");
```

Each of these accepts an allocator and an optional detail string (pass `null`
for no detail).

### Comparison with FastAPI

FastAPI does not have built-in RFC 7807 support. You would typically implement
it manually or use a library. In Zigmund, it is built into the framework:

```python
# FastAPI -- manual RFC 7807
from fastapi.responses import JSONResponse

@app.exception_handler(NotFoundException)
async def not_found_handler(request, exc):
    return JSONResponse(
        status_code=404,
        content={
            "type": "about:blank",
            "title": "Not Found",
            "status": 404,
            "detail": str(exc),
        },
        media_type="application/problem+json",
    )
```

```zig
// Zigmund -- built-in RFC 7807
fn notFoundHandler(
    req: *zigmund.Request,
    err: anyerror,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    _ = err;
    return zigmund.problemNotFound(allocator, "Resource not found");
}
```

---

## Error Propagation with `try`

The `try` keyword in Zig is shorthand for "if this returns an error, return
that error from the current function." It replaces Python's pattern of letting
exceptions propagate up the call stack:

```zig
fn handler(allocator: std.mem.Allocator) !zigmund.Response {
    // If Response.json fails (e.g., out of memory), the error
    // propagates to the caller automatically.
    return try zigmund.Response.json(allocator, .{ .ok = true });
}
```

Without `try`, you would need to handle the error explicitly:

```zig
fn handler(allocator: std.mem.Allocator) !zigmund.Response {
    const response = zigmund.Response.json(allocator, .{ .ok = true }) catch |err| {
        // Handle the error...
        return err;
    };
    return response;
}
```

`try` is equivalent to the above `catch |err| { return err; }` pattern. It is
used pervasively in Zigmund handlers:

```zig
fn createItem(
    item: zigmund.Body(ItemPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const payload = item.value.?;

    // `try` propagates any serialisation error
    return try zigmund.Response.json(allocator, .{
        .name = payload.name,
        .price = payload.price,
    });
}
```

### Comparison with Python

In Python, exceptions propagate automatically unless caught:

```python
def handler():
    # If json.dumps fails, the exception propagates automatically
    return JSONResponse(content={"ok": True})
```

In Zig, error propagation is always explicit. The `try` keyword makes it
concise, but you always see where errors can escape:

```zig
fn handler(allocator: std.mem.Allocator) !zigmund.Response {
    // `try` makes propagation explicit and visible
    return try zigmund.Response.json(allocator, .{ .ok = true });
}
```

---

## Putting It All Together

Here is a complete example showing multiple error handling patterns:

```zig
const std = @import("std");
const zigmund = @import("zigmund");

// 1. Define custom error sets
const ItemError = error{
    ItemNotFound,
    ItemOutOfStock,
};

const AuthError = error{
    InvalidToken,
    TokenExpired,
};

// 2. Write handlers that return errors
fn getItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    if (item_id.value.? == 0) {
        return ItemError.ItemNotFound;
    }
    if (item_id.value.? == 999) {
        return ItemError.ItemOutOfStock;
    }
    return try zigmund.Response.json(allocator, .{
        .id = item_id.value.?,
        .name = "Widget",
    });
}

// 3. Write exception handlers
fn itemErrorHandler(
    req: *zigmund.Request,
    err: anyerror,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    return switch (err) {
        error.ItemNotFound => zigmund.problemNotFound(allocator, "Item not found"),
        error.ItemOutOfStock => zigmund.problemConflict(allocator, "Item is out of stock"),
        else => zigmund.problemInternalServerError(allocator, null),
    };
}

fn authErrorHandler(
    req: *zigmund.Request,
    err: anyerror,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    _ = err;
    return zigmund.problemUnauthorized(allocator, "Invalid or expired token");
}

// 4. Register everything
pub fn setup(app: *zigmund.App) !void {
    try app.addExceptionHandler(ItemError, itemErrorHandler);
    try app.addExceptionHandler(AuthError, authErrorHandler);
    try app.get("/items/{item_id}", getItem, .{});
}
```

---

## Summary

| Concept | Python / FastAPI | Zig / Zigmund |
|---------|-----------------|---------------|
| Error mechanism | Exceptions (raise / except) | Error unions (`!T`, return error) |
| Error visibility | Not in type signature | Part of the return type |
| Error propagation | Automatic (bubbles up) | Explicit (`try` keyword) |
| Custom errors | Exception classes | Error sets (`error{Name}`) |
| Error-to-HTTP mapping | `@app.exception_handler` | `app.addExceptionHandler` |
| Quick HTTP errors | `raise HTTPException(...)` | `HTTPException` struct |
| Structured errors | Manual JSON | `ProblemDetail` (RFC 7807) |
| Performance cost | Stack unwinding, object creation | Zero cost for non-error path |

Zig's error handling model eliminates an entire class of bugs -- unhandled
exceptions, missing error checks, and silent failures -- by making every error
path visible in the type system. Zigmund builds on this foundation by providing
familiar patterns for mapping application errors to HTTP responses.
