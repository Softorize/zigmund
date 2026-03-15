# Middleware

Register request and response hooks that run before and after every handler. Middleware enables cross-cutting concerns like logging, metrics, timing, authentication, and header injection.

## Overview

Middleware in Zigmund consists of named hooks that intercept requests and responses at the application level. A middleware can have a `request_hook` (runs before the handler), a `response_hook` (runs after the handler), or both. Middleware is registered via `app.addMiddleware()` and applies to all routes.

This is the Zig equivalent of FastAPI's `@app.middleware("http")` decorator.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

var request_count = std.atomic.Value(u64).init(0);

fn requestCounter(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    _ = req;
    _ = allocator;
    _ = request_count.fetchAdd(1, .monotonic);
}

fn responseTimer(_: *zigmund.Request, response: *zigmund.Response, allocator: std.mem.Allocator) !void {
    try response.setHeader(allocator, "x-process-time", "0");
}

fn middlewareStatus(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .total_requests = request_count.load(.monotonic),
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addMiddleware(zigmund.App.Middleware{
        .name = "request-counter",
        .request_hook = requestCounter,
    });
    try app.addMiddleware(zigmund.App.Middleware{
        .name = "response-timer",
        .response_hook = responseTimer,
    });

    try app.get("/status", middlewareStatus, .{
        .summary = "Show middleware request counter",
    });
}
```

## How It Works

### 1. Middleware Structure

A middleware is defined as a `zigmund.App.Middleware` struct with a required `name` and optional hooks:

```zig
zigmund.App.Middleware{
    .name = "request-counter",
    .request_hook = requestCounter,   // runs before handler
    .response_hook = responseTimer,   // runs after handler
}
```

You can provide just a request hook, just a response hook, or both.

### 2. Request Hooks

A request hook runs before the route handler. Its signature is:

```zig
fn requestHook(req: *zigmund.Request, allocator: std.mem.Allocator) !void
```

Use cases:
- Logging incoming requests.
- Incrementing request counters.
- Validating authentication tokens.
- Adding or modifying request headers.

If a request hook returns an error, the handler is not called and an appropriate error response is returned.

### 3. Response Hooks

A response hook runs after the route handler has produced a response. Its signature is:

```zig
fn responseHook(req: *zigmund.Request, response: *zigmund.Response, allocator: std.mem.Allocator) !void
```

The hook receives a mutable pointer to the response, allowing it to:
- Add or modify response headers.
- Log response details.
- Record timing information.
- Modify response bodies (though this is rarely recommended).

### 4. Registration

Register middleware with `app.addMiddleware()`:

```zig
try app.addMiddleware(zigmund.App.Middleware{
    .name = "my-middleware",
    .request_hook = myRequestHook,
    .response_hook = myResponseHook,
});
```

Middleware executes in the order it is registered. Request hooks run in registration order; response hooks also run in registration order (after the handler completes).

### 5. Thread Safety

Since middleware hooks may be called concurrently by multiple worker threads, any shared mutable state must use atomic operations or other synchronization primitives:

```zig
var request_count = std.atomic.Value(u64).init(0);

fn requestCounter(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    _ = req;
    _ = allocator;
    _ = request_count.fetchAdd(1, .monotonic);
}
```

## Key Points

- Middleware is registered globally via `app.addMiddleware()` and applies to all routes.
- Request hooks run before handlers; response hooks run after.
- Each middleware must have a unique `name` for identification.
- Middleware executes in registration order.
- Shared mutable state in middleware must be thread-safe (use `std.atomic` or mutexes).
- Middleware hooks can modify both the request (in request hooks) and the response (in response hooks).

## See Also

- [Response Headers](response-headers.md) -- add headers in individual handlers instead of middleware.
- [Advanced Dependencies](advanced-dependencies.md) -- per-route injection as an alternative to global middleware.
- [Events](events.md) -- startup/shutdown hooks for application lifecycle.
