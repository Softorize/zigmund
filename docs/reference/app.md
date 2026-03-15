# App Reference

## Overview

`App` is the central type in Zigmund. It holds the router, dependency registry, middleware stack, security schemes, and server configuration. All route registration, middleware setup, and lifecycle management flows through the `App` instance.

## Initialization

### `App.init`

```zig
pub fn init(allocator: std.mem.Allocator, cfg: AppConfig) !App
```

Creates a new application instance with the given allocator and configuration.

### `App.deinit`

```zig
pub fn deinit(self: *App) void
```

Releases all resources owned by the application, including routes, middleware, dependencies, and caches.

## AppConfig

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `title` | `[]const u8` | (required) | API title used in OpenAPI info and docs UI |
| `version` | `[]const u8` | (required) | API version string |
| `summary` | `?[]const u8` | `null` | Short API summary |
| `description` | `?[]const u8` | `null` | Detailed API description |
| `terms_of_service` | `?[]const u8` | `null` | URL to terms of service |
| `contact` | `?OpenApiContact` | `null` | Contact information (name, url, email) |
| `license_info` | `?OpenApiLicense` | `null` | License information (name, identifier, url) |
| `root_path` | `?[]const u8` | `null` | Root path prefix for all routes |
| `openapi_url` | `?[]const u8` | `"/openapi.json"` | OpenAPI JSON endpoint path, or null to disable |
| `docs_url` | `?[]const u8` | `"/docs"` | Swagger UI endpoint path, or null to disable |
| `redoc_url` | `?[]const u8` | `"/redoc"` | ReDoc endpoint path, or null to disable |
| `metrics_url` | `?[]const u8` | `null` | Prometheus metrics endpoint path |
| `redirect_slashes` | `bool` | `true` | Redirect trailing-slash mismatches |
| `request_id_enabled` | `bool` | `true` | Generate a unique request ID per request |
| `request_id_header` | `[]const u8` | `"x-request-id"` | Header name for the request ID |
| `correlation_id_header` | `[]const u8` | `"x-correlation-id"` | Header name for correlation ID |
| `docs` | `SwaggerUiConfig` | `(defaults)` | Swagger UI customization |
| `redoc` | `RedocUiConfig` | `(defaults)` | ReDoc customization |
| `servers` | `[]const []const u8` | `&.{}` | Server URLs for OpenAPI |
| `strict_validation` | `bool` | `false` | Reject requests with unknown fields |
| `json_schema_dialect` | `?[]const u8` | `"https://json-schema.org/draft/2020-12/schema"` | JSON Schema dialect URI |
| `openapi_deterministic` | `bool` | `false` | Produce deterministic OpenAPI output |
| `openapi_extensions` | `[]const OpenApiExtension` | `&.{}` | App-level x- extensions |
| `webhooks` | `[]const OpenApiWebhook` | `&.{}` | OpenAPI webhook definitions |

### Structured Logging Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `structured_access_logs` | `bool` | `false` | Enable structured access logs |
| `structured_telemetry_logs` | `bool` | `false` | Enable structured telemetry logs |
| `structured_trace_logs` | `bool` | `false` | Enable structured trace logs |
| `structured_metrics_logs` | `bool` | `false` | Enable structured metrics logs |
| `structured_audit_logs` | `bool` | `false` | Enable structured audit logs |
| `structured_log_redaction_text` | `[]const u8` | `"[redacted]"` | Replacement text for redacted fields |
| `structured_log_redact_tracestate` | `bool` | `true` | Redact tracestate in logs |
| `structured_log_redact_baggage` | `bool` | `true` | Redact baggage in logs |
| `structured_log_redact_remote_addr` | `bool` | `true` | Redact remote address in logs |
| `structured_log_redact_user_agent` | `bool` | `true` | Redact user agent in logs |

## Route Registration Methods

All route methods share the same signature:

```zig
pub fn get(self: *App, path: []const u8, handler: anytype, opts: RouteOptions) !void
pub fn post(self: *App, path: []const u8, handler: anytype, opts: RouteOptions) !void
pub fn put(self: *App, path: []const u8, handler: anytype, opts: RouteOptions) !void
pub fn patch(self: *App, path: []const u8, handler: anytype, opts: RouteOptions) !void
pub fn delete(self: *App, path: []const u8, handler: anytype, opts: RouteOptions) !void
pub fn options(self: *App, path: []const u8, handler: anytype, opts: RouteOptions) !void
pub fn head(self: *App, path: []const u8, handler: anytype, opts: RouteOptions) !void
pub fn trace(self: *App, path: []const u8, handler: anytype, opts: RouteOptions) !void
```

Each registers a handler at the given path for the corresponding HTTP method. The `handler` can be any function -- Zigmund's compile-time injector automatically resolves parameters such as `Body`, `Query`, `Path`, `Security`, and `Depends` from the function signature.

### `websocket`

```zig
pub fn websocket(self: *App, path: []const u8, handler: anytype, opts: WebSocketRouteOptions) !void
```

Registers a WebSocket handler at the given path.

## Router Integration

### `includeRouter`

```zig
pub fn includeRouter(
    self: *App,
    prefix: []const u8,
    router: *const Router,
    opts: IncludeRouterOptions,
) !void
```

Merges all routes from an external `Router` into the app under the given prefix. Tags and dependencies from `IncludeRouterOptions` are merged with each route's existing options.

### `mount`

```zig
pub fn mount(self: *App, prefix: []const u8, subapp: *const App) !void
```

Mounts another `App` as a sub-application at the given prefix.

## Middleware

### `addMiddleware`

```zig
pub fn addMiddleware(self: *App, mw: anytype) !void
```

Adds middleware to the processing pipeline. Accepts either a `Middleware` struct (with named request/response hooks) or a value whose type provides `requestHook` and/or `responseHook` methods.

## Exception Handling

### `addExceptionHandler`

```zig
pub fn addExceptionHandler(self: *App, err_tag: type, handler: anytype) !void
```

Registers a handler for a specific error set. When an error in `err_tag` is returned from a route handler, the exception handler is called to produce a response.

## Security

### `addSecurityScheme`

```zig
pub fn addSecurityScheme(self: *App, name: []const u8, scheme: OpenApiSecurityScheme) !void
```

Registers a named security scheme that appears in the OpenAPI specification's `securitySchemes` section.

### `setUnauthorizedHandler`

```zig
pub fn setUnauthorizedHandler(self: *App, handler: anytype) void
```

Sets a custom response handler for authentication failures (Unauthorized errors).

### `setInsufficientScopeHandler`

```zig
pub fn setInsufficientScopeHandler(self: *App, handler: anytype) void
```

Sets a custom response handler for insufficient scope errors.

## Dependencies

### `addDependency`

```zig
pub fn addDependency(self: *App, name: []const u8, resolver: anytype) !void
```

Registers a named dependency resolver.

### `addDependencyWithCleanup`

```zig
pub fn addDependencyWithCleanup(self: *App, name: []const u8, resolver: anytype, cleanup: anytype) !void
```

Registers a named dependency resolver with a cleanup function called after each request.

### `overrideDependency`

```zig
pub fn overrideDependency(self: *App, name: []const u8, resolver: anytype) !void
```

Replaces a dependency resolver (useful for testing).

### `clearDependencyOverride`

```zig
pub fn clearDependencyOverride(self: *App, name: []const u8) bool
```

Removes a dependency override, restoring the original resolver.

## Lifecycle

### `onStartup` / `onShutdown`

```zig
pub fn onStartup(self: *App, handler: anytype) !void
pub fn onShutdown(self: *App, handler: anytype) !void
```

Register functions to run during server startup or shutdown.

### `lifespan`

```zig
pub fn lifespan(self: *App, startup: anytype, shutdown: anytype) !void
```

Convenience method that registers both startup and shutdown hooks in one call.

### `serve`

```zig
pub fn serve(self: *App, cfg: ServerConfig) !void
```

Starts the HTTP server with the given configuration. Runs startup hooks, begins accepting connections, and runs shutdown hooks when the server stops.

### `requestShutdown`

```zig
pub fn requestShutdown(self: *App) void
```

Signals the server to perform a graceful shutdown.

## Request Customization

### `setRequestCustomizer`

```zig
pub fn setRequestCustomizer(self: *App, customizer: anytype) void
```

Sets a function called on every request before route dispatch.

### `setDefaultRouteWrapper`

```zig
pub fn setDefaultRouteWrapper(self: *App, wrapper: anytype) void
```

Sets a function that wraps every route handler.

## Observability

### `setTelemetrySink` / `setTraceSink` / `setAccessLogSink` / `setMetricsSink` / `setAuditSink`

```zig
pub fn setTelemetrySink(self: *App, sink: anytype) void
pub fn setTraceSink(self: *App, sink: anytype) void
pub fn setAccessLogSink(self: *App, sink: anytype) void
pub fn setMetricsSink(self: *App, sink: anytype) void
pub fn setAuditSink(self: *App, sink: anytype) void
```

Register custom sinks for various observability events.

### JSON Sink Helpers

```zig
pub fn enableJsonTelemetrySink(self: *App) void
pub fn enableJsonTraceSink(self: *App) void
pub fn enableJsonAccessLogSink(self: *App) void
pub fn enableJsonMetricsSink(self: *App) void
pub fn enableJsonAuditSink(self: *App) void
```

Enable built-in JSON-formatted sinks for structured logging.

## Health Checks

### `addHealthCheck`

```zig
pub fn addHealthCheck(self: *App, name: []const u8, check: HealthCheckFn) !void
```

Registers a named health check function for readiness probes.

### `enableHealthEndpoints`

```zig
pub fn enableHealthEndpoints(self: *App) void
```

Enables the built-in `/health/live` and `/health/ready` endpoints.

## State

### `setStateBorrowed` / `setStateOwned`

```zig
pub fn setStateBorrowed(self: *App, key: []const u8, value: anytype) !void
pub fn setStateOwned(self: *App, key: []const u8, value: anytype, cleanup: anytype) !void
```

Store application-level state accessible from request handlers via `req.app_state`.

### `stateAs`

```zig
pub fn stateAs(self: *App, comptime Ptr: type, key: []const u8) ?Ptr
```

Retrieve application-level state cast to the given pointer type.

## OpenAPI

### `openapi`

```zig
pub fn openapi(self: *App) ![]const u8
```

Returns the generated OpenAPI JSON document as a string. The result is cached and invalidated when routes change.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try zigmund.App.init(allocator, .{
        .title = "My Service",
        .version = "1.0.0",
        .description = "A sample Zigmund application",
    });
    defer app.deinit();

    try app.get("/health", healthHandler, .{
        .summary = "Health check",
        .tags = &.{"system"},
    });

    try app.serve(.{ .port = 8080 });
}

fn healthHandler(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{ .status = "ok" });
}
```
