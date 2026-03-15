# Custom Index Page

Replace the default root page with your own handler to serve a welcome message, health check, or any custom response at the base URL of your application.

## Overview

By default, Zigmund serves its built-in welcome page at the root path (`/`). In production, you typically want to replace this with your own root endpoint -- a health check, an API overview, or a redirect to documentation. Registering a handler on `/` (or any base path) overrides the default behavior.

This example demonstrates registering two foundational routes: a root endpoint that returns a greeting and a health check endpoint that reports the application's status.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn readRoot(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .message = "Hello World",
    });
}

fn readHealth(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .status = "ok",
        .framework = "zigmund",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial", readRoot, .{
        .summary = "Tutorial root endpoint",
        .tags = &.{ "parity", "tutorial" },
    });
    try app.get("/tutorial/health", readHealth, .{
        .summary = "Tutorial health endpoint",
        .tags = &.{ "parity", "tutorial" },
    });
}
```

## How It Works

1. **Register a root handler.** `app.get("/tutorial", readRoot, .{...})` registers a `GET` handler at the base path. When a client requests this URL, `readRoot` runs and returns a JSON greeting. In your own application, you would register on `"/"` to replace the default welcome page.

2. **Return JSON.** `zigmund.Response.json(allocator, .{ .message = "Hello World" })` creates a `200 OK` response with `Content-Type: application/json` and the serialized body `{"message":"Hello World"}`.

3. **Add a health check.** The `/tutorial/health` endpoint returns a simple status object. Health checks are a common pattern for load balancers, container orchestrators (Kubernetes liveness/readiness probes), and monitoring systems.

4. **Minimal configuration.** Both routes use a lightweight configuration with only `.summary` and `.tags`. No additional metadata is required for basic endpoints.

## Key Points

- Registering a handler on `"/"` replaces Zigmund's built-in welcome page. The default page is only served when no handler is registered at the root path.
- Health check endpoints should be fast, side-effect-free, and always available. Avoid database queries or external service calls in a basic liveness check. If you need a deeper health check, create a separate `/ready` endpoint.
- The `_ = req` pattern discards the request object when the handler does not need it. The compiler requires all function parameters to be used; the discard satisfies this requirement.
- You can serve HTML instead of JSON at the root by returning `Response.html(allocator, html_content)` or by combining with [Static Files](static-files.md) to serve an `index.html`.
- Both routes share the same tags, so they appear in the same section of the generated OpenAPI documentation.

## See Also

- [First Steps](first-steps.md) -- Full application setup including `App.init`, route registration, and server startup.
- [Static Files](static-files.md) -- Serve an HTML landing page from disk instead of a handler.
- [API Metadata and Tags](metadata.md) -- Configure the API title and description shown in documentation.
- [Bigger Applications](bigger-applications.md) -- Organize root and nested routes across multiple routers.
