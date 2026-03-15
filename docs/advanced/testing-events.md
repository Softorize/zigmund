# Testing Events

Test startup and shutdown lifecycle hooks using `TestClient`. The test client's `start()` and `close()` methods trigger the application's lifecycle hooks, enabling verification of initialization and cleanup behavior.

## Overview

Lifecycle hooks (startup and shutdown) often perform critical initialization and cleanup. Testing them ensures that database connections are opened, caches are warmed, and resources are properly released. Zigmund's `TestClient` provides `start()` and `close()` methods that trigger these hooks without starting a real network server.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// Demonstrates lifecycle event testing. The TestClient.start() and
/// TestClient.close() methods trigger the app's startup and shutdown
/// hooks, allowing verification of lifecycle behavior in tests.

var startup_counter: u32 = 0;
var shutdown_counter: u32 = 0;

fn onStartup() anyerror!void {
    startup_counter += 1;
}

fn onShutdown() anyerror!void {
    shutdown_counter += 1;
}

fn lifecycleStatus(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .startup_count = startup_counter,
        .shutdown_count = shutdown_counter,
        .message = "Lifecycle hooks track startup and shutdown events",
    });
}

/// Example test usage:
///
///   var client = zigmund.TestClient.init(std.testing.allocator, &app);
///   defer client.deinit();
///
///   try client.start();   // triggers onStartup hook
///   // ... run test requests ...
///   try client.close();   // triggers onShutdown hook

pub fn buildExample(app: *zigmund.App) !void {
    try app.onStartup(onStartup);
    try app.onShutdown(onShutdown);

    try app.get("/lifecycle", lifecycleStatus, .{
        .summary = "Lifecycle event testing with startup and shutdown hooks",
    });
}
```

## How It Works

### 1. TestClient Lifecycle Methods

The `TestClient` provides two methods that correspond to the application lifecycle:

```zig
var client = zigmund.TestClient.init(std.testing.allocator, &app);
defer client.deinit();

try client.start();   // Triggers all registered startup hooks
// ... make test requests ...
try client.close();   // Triggers all registered shutdown hooks
```

### 2. Verifying Startup Hooks

After calling `client.start()`, you can verify that startup hooks executed correctly by checking their side effects:

```zig
test "startup hook executes" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "Test", .version = "1.0",
    });
    defer app.deinit();

    startup_counter = 0;  // Reset
    try app.onStartup(onStartup);

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    try client.start();
    // startup_counter is now 1
}
```

### 3. Verifying Shutdown Hooks

After calling `client.close()`, verify that shutdown hooks executed:

```zig
try client.close();
// shutdown_counter is now 1
```

### 4. Testing Order of Execution

If multiple hooks are registered, `start()` calls them in registration order and `close()` does the same for shutdown hooks:

```zig
try app.onStartup(firstStartup);
try app.onStartup(secondStartup);
// client.start() calls firstStartup, then secondStartup
```

### 5. Error Handling in Hooks

Lifecycle hooks can return `anyerror!void`. If a hook returns an error, it propagates through `client.start()` or `client.close()`, allowing your test to detect initialization or cleanup failures:

```zig
fn failingStartup() anyerror!void {
    return error.DatabaseConnectionFailed;
}

test "startup failure is detected" {
    try app.onStartup(failingStartup);
    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    // client.start() returns the error from failingStartup
    try std.testing.expectError(error.DatabaseConnectionFailed, client.start());
}
```

## Key Points

- `TestClient.start()` triggers all registered startup hooks in order.
- `TestClient.close()` triggers all registered shutdown hooks in order.
- Test hooks by checking their side effects (counters, flags, state changes).
- Hook errors propagate through `start()` and `close()`, enabling failure detection in tests.
- Always reset shared state between tests to avoid inter-test contamination.
- Use `defer client.deinit()` to ensure proper cleanup even if assertions fail.

## See Also

- [Events](events.md) -- register startup and shutdown hooks.
- [Testing Dependencies](testing-dependencies.md) -- override dependencies in tests.
- [Async Tests](async-tests.md) -- integration testing with `TestClient`.
