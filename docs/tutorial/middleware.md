# Middleware

Middleware lets you run logic before and after every request, without modifying individual route handlers. Common uses include logging, timing, adding response headers, and injecting per-request state.

## Overview

A Zigmund middleware consists of up to two hooks:

- **Request hook** -- runs before the route handler. It can inspect or modify the request, set dependency values, or short-circuit the request by returning an error.
- **Response hook** -- runs after the handler produces a response. It can inspect or modify the response, add headers, or perform cleanup.

Both hooks are optional. You can define a middleware with only a request hook, only a response hook, or both.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn requestMiddleware(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try req.setDependencyValue("middleware_stage", "request");
}

fn responseMiddleware(
    req: *zigmund.Request,
    response: *zigmund.Response,
    allocator: std.mem.Allocator,
) !void {
    _ = req;
    try response.setHeader(allocator, "x-middleware", "enabled");
}

fn readMiddlewareState(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .stage = req.dependency("middleware_stage") orelse "",
    });
}
```

Register the middleware and route:

```zig
try app.addMiddleware(zigmund.Middleware{
    .name = "tutorial_middleware",
    .request_hook = requestMiddleware,
    .response_hook = responseMiddleware,
});

try app.get("/status", readMiddlewareState, .{});
```

## How It Works

1. **Registration.** `app.addMiddleware()` adds the middleware to the application's middleware stack. Middleware runs in the order it is registered.
2. **Request phase.** When a request arrives, Zigmund calls each middleware's `request_hook` in registration order. In this example, `requestMiddleware` stores a value (`"request"`) in the request's dependency store using `req.setDependencyValue()`.
3. **Handler execution.** The route handler runs after all request hooks complete. It can retrieve middleware-injected values with `req.dependency()`.
4. **Response phase.** After the handler produces a response, Zigmund calls each middleware's `response_hook` in registration order. Here, `responseMiddleware` adds a custom `x-middleware` header to the response.

## Key Points

- **Request hook signature:** `fn(req: *zigmund.Request, allocator: std.mem.Allocator) !void`. Receives the mutable request and an allocator.
- **Response hook signature:** `fn(req: *zigmund.Request, response: *zigmund.Response, allocator: std.mem.Allocator) !void`. Receives both the request and the mutable response.
- **Ordering matters.** Middleware hooks run in the order they are registered with `addMiddleware`. If middleware A is registered before middleware B, A's request hook runs first, and A's response hook also runs first.
- **Dependency bridging.** Use `req.setDependencyValue()` in a request hook and `req.dependency()` in the handler to pass data from middleware to handlers without coupling them.
- **Error handling.** If a request hook returns an error, subsequent hooks and the handler are not called. The error is converted to an appropriate HTTP error response.
- **Each hook is optional.** Set either `request_hook` or `response_hook` to `null` if you only need one phase.

## See Also

- [CORS](cors.md) -- A built-in middleware for Cross-Origin Resource Sharing.
- [Dependencies](dependencies.md) -- The dependency injection system, which middleware can feed into.
- [Handling Errors](handling-errors.md) -- Customizing error responses that middleware errors produce.
