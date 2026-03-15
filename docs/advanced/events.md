# Events

Register startup and shutdown hooks that run when the application starts and stops. Use these for initialization tasks (database connections, cache warming) and cleanup (resource release, graceful shutdown).

## Overview

Zigmund supports application lifecycle events through `app.onStartup()` and `app.onShutdown()`. Startup hooks run after the application is initialized but before it begins accepting requests. Shutdown hooks run when the application is shutting down, after it stops accepting new requests.

This is the Zig equivalent of FastAPI's `@app.on_event("startup")` and `@app.on_event("shutdown")` decorators.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

var startup_called = std.atomic.Value(bool).init(false);
var shutdown_called = std.atomic.Value(bool).init(false);

fn onStartup() void {
    startup_called.store(true, .release);
    std.log.info("[events example] startup hook executed", .{});
}

fn onShutdown() void {
    shutdown_called.store(true, .release);
    std.log.info("[events example] shutdown hook executed", .{});
}

fn lifecycleStatus(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .startup_executed = startup_called.load(.acquire),
        .shutdown_executed = shutdown_called.load(.acquire),
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.onStartup(onStartup);
    try app.onShutdown(onShutdown);

    try app.get("/lifecycle", lifecycleStatus, .{
        .summary = "Check startup and shutdown lifecycle hook status",
    });
}
```

## How It Works

### 1. Registering Startup Hooks

Use `app.onStartup()` to register a function that runs when the application starts:

```zig
try app.onStartup(onStartup);
```

The hook function signature is:

```zig
fn onStartup() void
```

Startup hooks are called in registration order. They run after `App.init()` completes but before the server begins accepting requests.

Common uses for startup hooks:
- Initialize database connection pools.
- Warm caches or preload data.
- Log application startup.
- Validate configuration.

### 2. Registering Shutdown Hooks

Use `app.onShutdown()` to register a function that runs when the application shuts down:

```zig
try app.onShutdown(onShutdown);
```

Shutdown hooks run when the application receives a shutdown signal or `app.deinit()` is called. They execute in registration order.

Common uses for shutdown hooks:
- Close database connections.
- Flush log buffers.
- Release external resources.
- Send graceful shutdown notifications.

### 3. Thread Safety

Since startup and shutdown hooks may interact with shared state, use atomic operations for any state that is also accessed by request handlers:

```zig
var startup_called = std.atomic.Value(bool).init(false);

fn onStartup() void {
    startup_called.store(true, .release);
}
```

### 4. Multiple Hooks

You can register multiple startup and shutdown hooks. They execute in the order they are registered:

```zig
try app.onStartup(initDatabase);
try app.onStartup(warmCache);
try app.onStartup(logStartup);

try app.onShutdown(flushLogs);
try app.onShutdown(closeDatabase);
```

## Key Points

- `app.onStartup()` registers hooks that run before the server accepts requests.
- `app.onShutdown()` registers hooks that run during application shutdown.
- Multiple hooks can be registered; they execute in registration order.
- Use atomic operations for shared state between hooks and handlers.
- Startup hooks are the right place for one-time initialization (database pools, caches, configuration validation).
- Shutdown hooks are the right place for cleanup (closing connections, flushing buffers).

## See Also

- [Testing Events](testing-events.md) -- test startup and shutdown hooks with `TestClient`.
- [Middleware](middleware.md) -- per-request hooks instead of lifecycle hooks.
- [Settings](settings.md) -- load configuration that startup hooks might depend on.
