# Dependencies Reference

## Overview

Zigmund's dependency injection system allows routes to declare named dependencies that are resolved before the handler runs. Dependencies can be cached per-request or per-app, can depend on other dependencies (forming a DAG), and support automatic cleanup.

## Depends Marker

### `Depends`

```zig
pub fn Depends(comptime provider: anytype, opts: DependsOptions) type
```

Declares a dependency on a provider function. The provider is called during request dispatch, and its return value is injected into the handler parameter.

The provider function signature must be:

```zig
fn(req: *Request, allocator: std.mem.Allocator) !?[]const u8
```

Or any subset of those parameters.

## DependsOptions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `use_cache` | `bool` | `true` | Cache the resolved value |
| `cache_scope` | `DependsCacheScope` | `.request` | Cache lifetime scope |
| `name` | `?[]const u8` | `null` | Named dependency identifier |
| `depends_on` | `[]const []const u8` | `&.{}` | Names of prerequisite dependencies |
| `cleanup` | `?DependencyCleanupFn` | `null` | Function called after the request to clean up |

## DependsCacheScope

```zig
pub const DependsCacheScope = enum {
    request,  // Cached for the duration of one request
    app,      // Cached for the lifetime of the application
};
```

## DependencySpec

Used in `RouteOptions.dependencies` to declare named dependencies on routes.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `[]const u8` | (required) | Dependency name |
| `required` | `bool` | `true` | Whether the dependency must resolve |
| `use_cache` | `bool` | `true` | Use cached values |
| `cache_scope` | `DependencyCacheScope` | `.request` | Cache scope |
| `depends_on` | `[]const []const u8` | `&.{}` | Prerequisite dependency names |
| `scopes` | `[]const []const u8` | `&.{}` | Required security scopes |

## App-Level Dependency Management

### Registration

```zig
// Register a named dependency
try app.addDependency("auth", authResolver);

// Register with cleanup
try app.addDependencyWithCleanup("db", dbResolver, dbCleanup);
```

### Overrides (for testing)

```zig
// Override a dependency resolver
try app.overrideDependency("db", mockDbResolver);

// Clear a specific override
_ = app.clearDependencyOverride("db");

// Clear all overrides
app.clearDependencyOverrides();
```

## Dependency Graph

Dependencies can declare prerequisites via `depends_on`. The framework resolves them in topological order (prerequisites first). Circular dependencies are detected and result in a `DependencyCycleDetected` error.

## Cleanup Functions

The cleanup function signature is:

```zig
fn cleanup(req: *Request, name: []const u8, value: []const u8, allocator: std.mem.Allocator) !void
```

Cleanup runs after the response is sent, in reverse order of resolution.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn authResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const token = req.header("authorization") orelse return error.Unauthorized;
    return token;
}

fn dbResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    return "db-session-123";
}

fn dbCleanup(req: *zigmund.Request, name: []const u8, value: []const u8, allocator: std.mem.Allocator) !void {
    _ = req;
    _ = name;
    _ = value;
    _ = allocator;
    // Close database connection here
}

pub fn main() !void {
    var app = try zigmund.App.init(allocator, .{ .title = "API", .version = "1.0" });

    try app.addDependency("auth", authResolver);
    try app.addDependencyWithCleanup("db", dbResolver, dbCleanup);

    try app.get("/data", dataHandler, .{
        .dependencies = &.{
            .{ .name = "auth" },
            .{ .name = "db", .depends_on = &.{"auth"} },
        },
    });
}

fn dataHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const db = req.dependency("db").?;
    return zigmund.Response.json(allocator, .{ .session = db });
}
```
