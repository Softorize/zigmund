# Behind a Proxy

Configure Zigmund to work correctly behind a reverse proxy (Nginx, Caddy, HAProxy, or a cloud load balancer). The `root_path` setting ensures OpenAPI documentation, Swagger UI, and ReDoc are served under the correct prefix.

## Overview

When a Zigmund application is deployed behind a reverse proxy, the proxy may strip a path prefix before forwarding requests. For example, the proxy might route `/api/v1/items` to the application as `/items`. The `root_path` configuration tells Zigmund about this prefix so that generated URLs in OpenAPI documentation, Swagger UI, and ReDoc remain correct.

This is the Zig equivalent of FastAPI's `root_path` parameter.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn proxyInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .message = "This app is configured with root_path for reverse proxy support",
        .root_path = "/api/v1",
        .note = "OpenAPI docs, Swagger UI, and ReDoc are served under the root_path prefix",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Demonstrate that the app's config exposes root_path.
    // In a real proxy scenario you would initialise the App with:
    //   App.init(allocator, .{ .title = "...", .version = "...", .root_path = "/api/v1" })
    // The route below simply reports the configuration.
    try app.get("/proxy-info", proxyInfo, .{
        .summary = "Show reverse proxy root_path configuration",
    });
}
```

## How It Works

### 1. Setting root_path

Configure `root_path` when initializing the application:

```zig
var app = try zigmund.App.init(allocator, .{
    .title = "My API",
    .version = "1.0",
    .root_path = "/api/v1",
});
```

This tells Zigmund that all external URLs should be prefixed with `/api/v1`.

### 2. Effect on OpenAPI and Documentation

With `root_path = "/api/v1"`:

| Resource           | URL without root_path | URL with root_path          |
|--------------------|----------------------|------------------------------|
| OpenAPI spec       | `/openapi.json`      | `/api/v1/openapi.json`       |
| Swagger UI         | `/docs`              | `/api/v1/docs`               |
| ReDoc              | `/redoc`             | `/api/v1/redoc`              |

The `servers` section of the generated OpenAPI spec will include the `root_path`, so generated client code and API explorers will use the correct base URL.

### 3. Reverse Proxy Configuration

A typical Nginx configuration that strips the prefix:

```nginx
location /api/v1/ {
    proxy_pass http://127.0.0.1:8000/;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

The trailing `/` in `proxy_pass` causes Nginx to strip the `/api/v1` prefix. Zigmund's `root_path` compensates by adding it back to generated URLs.

### 4. Trusted Proxy Headers

When behind a proxy, Zigmund can use forwarded headers (`X-Forwarded-For`, `X-Forwarded-Proto`) to determine the client's real IP address and protocol. These headers are typically set by the reverse proxy.

## Key Points

- Set `root_path` in `AppConfig` when deploying behind a reverse proxy that strips a path prefix.
- `root_path` affects OpenAPI spec URLs, Swagger UI, and ReDoc -- not route matching.
- The OpenAPI spec's `servers` section is updated to include the `root_path`.
- Route handlers do not need to be modified -- they continue to use paths relative to the application root.
- Always configure the reverse proxy to forward appropriate headers (`X-Forwarded-For`, `X-Forwarded-Proto`, `Host`).

## See Also

- [Sub-Applications](sub-applications.md) -- mount applications at sub-paths.
- [Settings](settings.md) -- load proxy configuration from environment variables.
- [Middleware](middleware.md) -- middleware for processing forwarded headers.
