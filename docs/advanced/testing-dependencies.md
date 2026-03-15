# Testing Dependencies

Override dependency providers with mock implementations for testing. Zigmund's dependency injection system supports test-time overrides that replace production providers with controlled test values.

## Overview

In production, dependencies might connect to databases, call external APIs, or perform expensive computations. During testing, you want to replace these with fast, predictable mock implementations. Zigmund's `app.overrideDependency()` method lets you swap a named dependency's provider function without changing any handler code.

This is the Zig equivalent of FastAPI's `app.dependency_overrides` dictionary.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// Demonstrates dependency override for testing. A production dependency
/// provides a real value; in tests, overrideDependency replaces it with
/// a mock that returns a fixed test value.

fn productionDbProvider(_: *zigmund.Request, allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    return "production-database-connection";
}

fn getDbInfo(
    db_conn: zigmund.Depends(productionDbProvider, .{ .name = "db_connection" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .db_connection = db_conn.value.?,
        .message = "Retrieved database connection via dependency injection",
    });
}

/// Example test override (used in test blocks or test harness):
///
///   fn mockDbProvider(_: *zigmund.Request, allocator: std.mem.Allocator) ![]const u8 {
///       _ = allocator;
///       return "mock-test-database";
///   }
///
///   try app.overrideDependency("db_connection", mockDbProvider);
///   var client = zigmund.TestClient.init(std.testing.allocator, &app);
///   defer client.deinit();
///   var response = try client.get("/testing-dependencies");
///   // response now contains "mock-test-database" instead of production value

pub fn buildExample(app: *zigmund.App) !void {
    try app.addDependency("db_connection", productionDbProvider);

    try app.get("/db-info", getDbInfo, .{
        .summary = "Dependency injection with test override support",
    });
}
```

## How It Works

### 1. Named Dependencies

Give a dependency a name using the `.name` option in `Depends()` or by registering it with `app.addDependency()`:

```zig
// Named via Depends option
db_conn: zigmund.Depends(productionDbProvider, .{ .name = "db_connection" }),

// Registered globally
try app.addDependency("db_connection", productionDbProvider);
```

The name is the key used to identify the dependency when overriding.

### 2. Overriding in Tests

In your test code, call `app.overrideDependency()` to replace the production provider:

```zig
fn mockDbProvider(_: *zigmund.Request, allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    return "mock-test-database";
}

try app.overrideDependency("db_connection", mockDbProvider);
```

The mock provider must have the same return type as the production provider.

### 3. Full Test Pattern

```zig
test "endpoint uses mock database" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "Test", .version = "1.0",
    });
    defer app.deinit();

    try buildExample(&app);

    // Override the production dependency with a mock
    try app.overrideDependency("db_connection", mockDbProvider);

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var response = try client.get("/db-info");
    defer response.deinit(std.testing.allocator);

    // Verify the mock value is returned
    // response body contains "mock-test-database"
}
```

### 4. Restoring Production Dependencies

Overrides are scoped to the `App` instance. Since tests typically create a fresh `App`, overrides do not leak between tests. If you need to restore the original dependency within a test, call `overrideDependency` again with the production provider.

## Key Points

- Named dependencies can be overridden at test time using `app.overrideDependency()`.
- The mock provider must match the return type of the production provider.
- Overrides affect all handlers that reference the named dependency.
- Each test should create a fresh `App` instance to avoid state leakage between tests.
- This pattern enables testing handlers in isolation without real databases, external APIs, or other infrastructure.

## See Also

- [Advanced Dependencies](advanced-dependencies.md) -- nested and cached dependency patterns.
- [Testing Events](testing-events.md) -- test startup and shutdown lifecycle hooks.
- [Async Tests](async-tests.md) -- integration testing patterns with `TestClient`.
