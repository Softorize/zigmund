# Router Reference

## Overview

`Router` (also exported as `APIRouter`) provides a standalone route collection that can be composed into an `App` via `includeRouter`. This enables modular route organization across multiple files.

## Initialization

### `Router.init`

```zig
pub fn init(allocator: std.mem.Allocator) Router
```

Creates a new empty router.

### `Router.deinit`

```zig
pub fn deinit(self: *Router) void
```

Frees all owned route paths and internal storage.

## Methods

### `addHttpRoute`

```zig
pub fn addHttpRoute(
    self: *Router,
    method: RouteMethod,
    path: []const u8,
    handler: anytype,
    opts: RouteOptions,
) !void
```

Registers an HTTP route with the given method, path, handler, and options. The handler can use Zigmund's compile-time injection for typed parameters.

**RouteMethod values:** `.GET`, `.POST`, `.PUT`, `.PATCH`, `.DELETE`, `.OPTIONS`, `.HEAD`, `.TRACE`

### `addWebSocketRoute`

```zig
pub fn addWebSocketRoute(
    self: *Router,
    path: []const u8,
    handler: anytype,
    opts: WebSocketRouteOptions,
) !void
```

Registers a WebSocket route.

### `setDefaultRouteWrapper`

```zig
pub fn setDefaultRouteWrapper(self: *Router, wrapper: anytype) void
```

Sets a wrapper function applied to all routes in this router.

### `httpRoutes`

```zig
pub fn httpRoutes(self: *const Router) []const HttpRoute
```

Returns all registered HTTP routes.

### `websocketRoutes`

```zig
pub fn websocketRoutes(self: *const Router) []const WebSocketRoute
```

Returns all registered WebSocket routes.

## IncludeRouterOptions

Options passed when merging a router into an app via `app.includeRouter`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `tags` | `[]const []const u8` | `&.{}` | Tags to merge with each route's existing tags |
| `dependencies` | `[]const DependencySpec` | `&.{}` | Dependencies to merge with each route |
| `default_response_class` | `?[]const u8` | `null` | Default response class for routes without one |
| `include_in_schema` | `bool` | `true` | Whether to include these routes in OpenAPI |

## RouteOptions

Options for individual route registration.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `?[]const u8` | `null` | Route name |
| `summary` | `?[]const u8` | `null` | Short summary for OpenAPI |
| `description` | `?[]const u8` | `null` | Detailed description for OpenAPI |
| `tags` | `[]const []const u8` | `&.{}` | OpenAPI tags |
| `status_code` | `?std.http.Status` | `null` | Default success status code |
| `include_in_schema` | `bool` | `true` | Include in OpenAPI spec |
| `response_model` | `?type` | `null` | Response model type for OpenAPI |
| `deprecated` | `bool` | `false` | Mark as deprecated in OpenAPI |
| `operation_id` | `?[]const u8` | `null` | Unique OpenAPI operation ID |
| `dependencies` | `[]const DependencySpec` | `&.{}` | Route-level dependencies |
| `responses` | `[]const ResponseSpec` | `&.{}` | Additional response specifications |
| `openapi_extensions` | `[]const OpenApiExtension` | `&.{}` | Route-level x- extensions |
| `openapi_security` | `[]const OpenApiSecurityAlternative` | `&.{}` | Security requirements |
| `openapi_callbacks` | `[]const OpenApiCallback` | `&.{}` | Callback definitions |
| `openapi_request_examples` | `[]const OpenApiExample` | `&.{}` | Request body examples |
| `openapi_response_examples` | `[]const OpenApiResponseExamples` | `&.{}` | Response examples |
| `strict_validation` | `?bool` | `null` | Override app-level strict validation |
| `max_body_bytes` | `?usize` | `null` | Maximum request body size |

## Path Patterns

Routes support path parameters using curly braces:

- `"/items/{item_id}"` -- captures a single path segment
- `"/files/{file_path:path}"` -- captures all remaining segments (greedy)

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

// users.zig
pub fn buildRouter(allocator: std.mem.Allocator) !zigmund.Router {
    var router = zigmund.Router.init(allocator);

    try router.addHttpRoute(.GET, "/", listUsers, .{
        .summary = "List users",
    });
    try router.addHttpRoute(.POST, "/", createUser, .{
        .summary = "Create user",
    });

    return router;
}

// main.zig
pub fn main() !void {
    var app = try zigmund.App.init(allocator, .{ .title = "API", .version = "1.0" });
    defer app.deinit();

    var users_router = try buildRouter(allocator);
    defer users_router.deinit();

    try app.includeRouter("/api/users", &users_router, .{
        .tags = &.{"users"},
    });

    try app.serve(.{ .port = 8080 });
}
```
