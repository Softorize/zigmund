# WSGI

Zigmund runs on a native Zig HTTP server -- there is no WSGI or ASGI adapter layer. This page explains the differences from Python's WSGI/ASGI model and how Zigmund handles the same responsibilities natively.

## Overview

In the Python ecosystem, WSGI (Web Server Gateway Interface) and ASGI (Asynchronous Server Gateway Interface) provide a standard interface between web servers and web applications. Zigmund does not use this pattern. Instead, the application creates an HTTP server directly using `app.listen()` or `app.serve()`, handling connections with Zig's native networking stack.

This page exists for developers migrating from Python/FastAPI who are looking for the WSGI/ASGI equivalent in Zigmund.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn serverInfo(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .runtime = "native Zig HTTP server",
        .protocol = "HTTP/1.1",
        .wsgi_equivalent = "not applicable — Zig runs natively",
        .message = "zigmund.App runs directly without WSGI/ASGI; configure with AppConfig and call app.listen()",
    });
}

/// Usage (standalone server):
///
///   var app = try zigmund.App.init(allocator, .{
///       .title = "My App",
///       .version = "1.0",
///   });
///   defer app.deinit();
///
///   // Register routes...
///   try app.get("/", handler, .{});
///
///   // Start the native server
///   try app.listen(.{ .port = 8000 });

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/server-info", serverInfo, .{
        .summary = "Native Zig server — no WSGI/ASGI needed",
    });
}
```

## How It Works

### 1. No Gateway Interface Needed

In Python:

```
Client -> Nginx -> WSGI/ASGI -> Python App
```

In Zigmund:

```
Client -> (optional: Nginx) -> Zigmund App
```

Zigmund's built-in HTTP server handles connections directly. There is no intermediate gateway layer.

### 2. Starting the Server

Instead of configuring a WSGI server (Gunicorn, uWSGI) or ASGI server (Uvicorn, Daphne), you simply call `app.serve()` or `app.listen()`:

```zig
var app = try zigmund.App.init(allocator, .{
    .title = "My App",
    .version = "1.0",
});
defer app.deinit();

try app.get("/", handler, .{});

// Start listening on port 8000
try app.serve(.{ .port = 8000 });
```

### 3. Configuration Mapping

| Python (WSGI/ASGI)           | Zigmund Equivalent                    |
|------------------------------|---------------------------------------|
| `gunicorn app:app`           | `app.serve(.{})`                      |
| `--bind 0.0.0.0:8000`       | `.host = "0.0.0.0", .port = 8000`    |
| `--workers 4`                | Worker threads configured internally  |
| `uvicorn app:app --reload`   | Recompile and restart (`zig build run`)|
| `WSGI_APPLICATION` setting   | Not needed -- app is the server       |

### 4. Deployment

For production deployment, Zigmund compiles to a single static binary:

```bash
zig build -Doptimize=.ReleaseFast
./zig-out/bin/myapp
```

No Python runtime, no virtual environment, no WSGI server, no dependency installation. The binary is self-contained and can be deployed via:

- Direct execution
- Docker containers
- Systemd services
- Cloud compute instances

### 5. Reverse Proxy (Optional)

While Zigmund can serve clients directly, production deployments often place a reverse proxy (Nginx, Caddy) in front for TLS termination, static file serving, and load balancing. See [Behind a Proxy](behind-a-proxy.md) for configuration details.

## Key Points

- Zigmund runs natively without WSGI, ASGI, or any gateway interface.
- `app.serve()` or `app.listen()` starts the built-in HTTP server directly.
- The application compiles to a single static binary -- no runtime dependencies.
- Worker threads are managed internally by the Zig runtime.
- A reverse proxy (Nginx, Caddy) is optional but recommended for TLS and static files in production.
- There is no equivalent of `gunicorn`, `uvicorn`, or `uWSGI` -- Zigmund is its own server.

## See Also

- [Behind a Proxy](behind-a-proxy.md) -- configure Zigmund behind Nginx or Caddy.
- [Settings](settings.md) -- configure host, port, and other settings from environment variables.
- [Events](events.md) -- startup and shutdown hooks for the native server lifecycle.
