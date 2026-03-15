# Async Tests

Integration testing patterns using `TestClient` for synchronous request dispatch that exercises the full handler pipeline without starting a network server.

## Overview

Zig does not have async/await like Python. Instead, Zigmund's `TestClient` provides synchronous methods (`get`, `post`, `put`, `delete`) that dispatch requests through the full handler pipeline -- including middleware, dependency injection, and response construction -- without a network server. This gives you fast, deterministic integration tests.

This is the Zig equivalent of FastAPI's `TestClient` (based on httpx/Starlette), adapted for Zig's synchronous execution model.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn getItems(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .items = &[_][]const u8{ "item-a", "item-b", "item-c" },
        .count = @as(u32, 3),
    });
}

fn createItem(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var response = try zigmund.Response.json(allocator, .{
        .created = true,
        .message = "Item created successfully",
    });
    return response.withStatus(.created);
}

/// Example test usage with TestClient:
///
///   var app = try zigmund.App.init(std.testing.allocator, .{
///       .title = "Test", .version = "1.0",
///   });
///   defer app.deinit();
///   try buildExample(&app);
///
///   var client = zigmund.TestClient.init(std.testing.allocator, &app);
///   defer client.deinit();
///
///   // GET request
///   var get_resp = try client.get("/items");
///   defer get_resp.deinit(std.testing.allocator);
///   // verify get_resp.status == .ok
///
///   // POST request
///   var post_resp = try client.post("/items", "{}");
///   defer post_resp.deinit(std.testing.allocator);
///   // verify post_resp.status == .created

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/items", getItems, .{
        .summary = "List items for TestClient integration testing",
    });

    try app.post("/items", createItem, .{
        .summary = "Create item for TestClient integration testing",
    });
}
```

## How It Works

### 1. Creating a TestClient

Initialize a `TestClient` with a testing allocator and a reference to your app:

```zig
var app = try zigmund.App.init(std.testing.allocator, .{
    .title = "Test App",
    .version = "1.0",
});
defer app.deinit();

// Register routes...
try buildExample(&app);

var client = zigmund.TestClient.init(std.testing.allocator, &app);
defer client.deinit();
```

### 2. Making Requests

The `TestClient` provides methods for each HTTP verb:

```zig
// GET
var get_resp = try client.get("/items");
defer get_resp.deinit(std.testing.allocator);

// POST with body
var post_resp = try client.post("/items", "{\"name\": \"test\"}");
defer post_resp.deinit(std.testing.allocator);
```

Each method returns a response object that must be deinitialized with `defer`.

### 3. Verifying Responses

Check the status code and response body:

```zig
test "GET /items returns 200 with items" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "Test", .version = "1.0",
    });
    defer app.deinit();
    try buildExample(&app);

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var resp = try client.get("/items");
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, resp.status);
}

test "POST /items returns 201 Created" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "Test", .version = "1.0",
    });
    defer app.deinit();
    try buildExample(&app);

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var resp = try client.post("/items", "{}");
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqual(.created, resp.status);
}
```

### 4. Testing the Full Pipeline

`TestClient` exercises the complete request pipeline:

1. Middleware request hooks.
2. Parameter extraction and dependency injection.
3. Handler execution.
4. Middleware response hooks.
5. Response serialization.

This makes `TestClient` tests true integration tests, not unit tests.

### 5. Test Isolation

Each test should create a fresh `App` instance to ensure isolation:

```zig
test "test A" {
    var app = try zigmund.App.init(std.testing.allocator, ...);
    defer app.deinit();
    // ...
}

test "test B" {
    var app = try zigmund.App.init(std.testing.allocator, ...);
    defer app.deinit();
    // ...
}
```

## Key Points

- `TestClient` dispatches requests synchronously through the full handler pipeline.
- No network server is started -- tests run entirely in-process for speed and determinism.
- Always `defer resp.deinit(allocator)` on responses to prevent memory leaks.
- Each test should create a fresh `App` instance for isolation.
- `TestClient` tests exercise middleware, dependencies, and serialization -- making them integration tests.
- Use `std.testing.expectEqual` to verify status codes and `std.testing.expectEqualStrings` for body content.

## See Also

- [Testing Dependencies](testing-dependencies.md) -- override dependencies with mocks.
- [Testing Events](testing-events.md) -- test lifecycle hooks with `TestClient`.
- [Testing WebSockets](testing-websockets.md) -- test WebSocket handlers.
