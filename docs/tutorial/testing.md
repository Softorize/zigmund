# Testing

Zigmund includes a built-in `TestClient` that lets you write integration tests against your application without starting a real HTTP server. Tests run in-process, making them fast and deterministic.

## Overview

The `TestClient` simulates HTTP requests against your application's route handlers. It constructs a request, runs it through the full middleware and dependency resolution pipeline, and returns the response. You can then assert on status codes, response bodies, and headers.

Because no network socket is opened, tests execute in milliseconds and can run in parallel without port conflicts.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn ping(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .ping = "pong",
    });
}

fn echoBody(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .body = req.body,
    });
}
```

Register routes and write tests:

```zig
var app = try zigmund.App.init(.{});
try app.get("/ping", ping, .{});
try app.post("/echo", echoBody, .{});

// Create a test client
var client = app.testClient();

// Test a GET request
const get_response = try client.get("/ping");
try std.testing.expectEqual(get_response.status, .ok);
// Parse and assert on the JSON body

// Test a POST request with a body
const post_response = try client.post("/echo", .{
    .body = "{\"message\": \"hello\"}",
    .content_type = "application/json",
});
try std.testing.expectEqual(post_response.status, .ok);
```

## How It Works

1. **Initialize the app.** Create your `zigmund.App` and register routes, middleware, and dependencies exactly as you would in production.
2. **Create the client.** `app.testClient()` returns a `TestClient` bound to the application. No server is started.
3. **Send requests.** Use `client.get()`, `client.post()`, `client.put()`, `client.patch()`, or `client.delete()` to simulate HTTP requests. Each method takes a path and optional request options (body, headers, content type).
4. **Assert on responses.** The returned response contains `.status`, `.body`, and `.headers`. Use Zig's standard `std.testing` assertions to verify correctness.

## Key Points

- **Full pipeline execution.** The `TestClient` runs requests through the complete middleware stack, dependency resolution, and route matching, just like a real request. This means your tests cover middleware behavior and dependency injection.
- **No network overhead.** Because requests are dispatched in-process, tests are extremely fast and do not require port allocation or cleanup.
- **Zig test integration.** Write tests in `test` blocks alongside your application code or in dedicated test files. Run them with `zig build test`.
- **Request options.** The `client.post()` and similar methods accept an options struct where you can set `.body`, `.content_type`, and `.headers` to simulate different request payloads.
- **JSON assertions.** Parse the response `.body` with `std.json` to assert on specific fields in the response payload.

## Example Test Block

```zig
test "ping endpoint returns pong" {
    var app = try zigmund.App.init(.{});
    try app.get("/ping", ping, .{});

    var client = app.testClient();
    const response = try client.get("/ping");

    try std.testing.expectEqual(response.status, .ok);
}

test "echo endpoint returns posted body" {
    var app = try zigmund.App.init(.{});
    try app.post("/echo", echoBody, .{});

    var client = app.testClient();
    const response = try client.post("/echo", .{
        .body = "{\"key\": \"value\"}",
        .content_type = "application/json",
    });

    try std.testing.expectEqual(response.status, .ok);
}
```

## See Also

- [First Steps](first-steps.md) -- Setting up a basic application to test.
- [Dependencies](dependencies.md) -- Testing handlers that depend on injected providers.
- [Middleware](middleware.md) -- Verifying middleware behavior in tests.
