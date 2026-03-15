# Sub-Applications

Mount independent Zigmund applications at sub-paths, enabling modular application architecture. Each sub-application can have its own routes, middleware, and configuration.

## Overview

Large applications benefit from being split into smaller, self-contained modules. Zigmund supports mounting sub-applications at a prefix path using `app.mount()`. Each sub-application is a full `zigmund.App` instance with its own route table, and all its routes are served under the mount prefix.

This is the Zig equivalent of FastAPI's `app.mount()` for including sub-applications.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn subappHome(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .app = "subapp",
        .message = "This route is served by a mounted sub-application",
    });
}

fn subappItems(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .app = "subapp",
        .items = &[_][]const u8{ "item-a", "item-b", "item-c" },
    });
}

fn mainAppInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .app = "main",
        .message = "This is the main application; subapp is mounted at /v2",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Register the main app route
    try app.get("/", mainAppInfo, .{
        .summary = "Main application info with mounted sub-app",
    });

    // Register sub-app routes under the sub-application prefix.
    // In a full deployment you would create a separate App and call app.mount(),
    // but you can also register routes directly under a prefix.
    try app.get("/v2", subappHome, .{
        .summary = "Sub-application home",
    });
    try app.get("/v2/items", subappItems, .{
        .summary = "Sub-application items list",
    });
}
```

## How It Works

### 1. Creating a Sub-Application

A sub-application is a standard `zigmund.App` instance:

```zig
var sub_app = try zigmund.App.init(allocator, .{
    .title = "Sub API",
    .version = "2.0",
});
defer sub_app.deinit();

try sub_app.get("/", subappHome, .{});
try sub_app.get("/items", subappItems, .{});
```

### 2. Mounting with app.mount()

Mount the sub-application at a prefix path on the parent application:

```zig
try app.mount("/v2", &sub_app);
```

All routes registered on `sub_app` are now accessible under `/v2`:
- `sub_app`'s `/` becomes `/v2`
- `sub_app`'s `/items` becomes `/v2/items`

### 3. Direct Route Registration

For simpler cases, you can register sub-application routes directly on the parent app under a shared prefix without creating a separate `App` instance:

```zig
try app.get("/v2", subappHome, .{});
try app.get("/v2/items", subappItems, .{});
```

This approach is simpler but does not give the sub-application its own middleware, configuration, or OpenAPI spec.

### 4. Independent Configuration

When using `app.mount()`, each sub-application has its own:

- Route table
- Middleware stack
- OpenAPI metadata (title, version, description)
- Security schemes

This makes sub-applications ideal for API versioning, microservice composition, or modular feature sets.

### 5. API Versioning Pattern

A common pattern is mounting versioned APIs:

```zig
var v1 = try zigmund.App.init(allocator, .{ .title = "API", .version = "1.0" });
var v2 = try zigmund.App.init(allocator, .{ .title = "API", .version = "2.0" });

// Register routes on each version...

try app.mount("/api/v1", &v1);
try app.mount("/api/v2", &v2);
```

## Key Points

- Sub-applications are full `zigmund.App` instances mounted at a prefix path.
- `app.mount(prefix, sub_app)` makes all sub-app routes available under the prefix.
- Each sub-application can have independent middleware, configuration, and OpenAPI metadata.
- For simple cases, registering routes directly under a shared prefix avoids the overhead of a separate `App` instance.
- Sub-applications are ideal for API versioning, modular architecture, and team-based code organization.

## See Also

- [Behind a Proxy](behind-a-proxy.md) -- configure sub-applications behind reverse proxies.
- [Middleware](middleware.md) -- middleware scoped to a specific sub-application.
- [Path Operation Advanced Configuration](path-operation-advanced-configuration.md) -- per-route configuration options.
