# Zigmund

**A high-performance, type-safe web framework for Zig -- inspired by FastAPI.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig 0.15.2](https://img.shields.io/badge/Zig-0.15.2-f7a41d.svg)](https://ziglang.org)
[![FastAPI Parity: 118/118](https://img.shields.io/badge/FastAPI_Parity-118%2F118-brightgreen.svg)](#project-status)

Zigmund brings the developer experience of FastAPI to the Zig ecosystem: declarative parameter extraction, automatic OpenAPI generation, compile-time dependency injection, and a batteries-included middleware stack -- all with the performance and safety guarantees of native Zig.

---

## Feature Highlights

| Feature | Description |
|---|---|
| **Comptime Dependency Injection** | `Depends` and `Security` markers resolved at compile time -- no runtime reflection, no overhead |
| **Type-safe Parameters** | Extract `Query`, `Path`, `Header`, `Cookie`, `Body`, `Form`, and `File` parameters with full type validation |
| **Auto OpenAPI 3.1** | Schema generation from handler signatures with built-in Swagger UI and ReDoc endpoints |
| **WebSocket Support** | First-class WebSocket handlers with the same routing and middleware pipeline |
| **Built-in Middleware** | CORS, rate limiting, CSRF protection, gzip/zlib compression, sessions, and request timeouts |
| **Security** | API key (query/header/cookie), HTTP Basic/Bearer/Digest, OAuth2 (password, client credentials, implicit, authorization code), OpenID Connect, and JWT validation |
| **In-process TestClient** | Send requests directly to your app in tests -- no socket, no port, deterministic results |
| **Response Model Filtering** | Shape outgoing JSON to match a declared response model, stripping internal fields automatically |
| **Router Composition** | Mount sub-routers with prefix, tags, and shared dependencies -- build large APIs from small, testable pieces |
| **Multi-worker TLS Serving** | Spawn multiple OS threads behind a single listener with native OpenSSL/TLS support |

---

## Quick Install

Add Zigmund as a dependency using the Zig package manager:

```bash
zig fetch --save=zigmund https://github.com/Softorize/zigmund/archive/refs/heads/main.tar.gz
```

Then wire it into your `build.zig`:

```zig
const zigmund_dep = b.dependency("zigmund", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zigmund", zigmund_dep.module("zigmund"));
```

---

## Hello World

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn hello(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .message = "Hello World" });
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    var app = try zigmund.App.init(gpa.allocator(), .{
        .title = "My API",
        .version = "0.1.0",
    });
    defer app.deinit();

    try app.get("/", hello, .{});
    try app.serve(.{});
}
```

```bash
zig build run -- serve
# => Listening on http://127.0.0.1:8000
# => GET /          -> 200 {"message":"Hello World"}
# => GET /docs      -> Swagger UI
# => GET /redoc     -> ReDoc
# => GET /openapi.json
```

---

## Feature Showcase

### Path Parameters

Extract typed path segments directly into handler arguments. Invalid types return a `422` automatically.

```zig
fn readItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{ .item_id = item_id.value.? });
}
```

### Request Body with Validation

Declare a struct and Zigmund deserializes, validates, and injects it.

```zig
const Item = struct {
    name: []const u8,
    price: f64,
    in_stock: bool = true,
};

fn createItem(
    item: zigmund.Body(Item, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .name = item.value.?.name,
        .price = item.value.?.price,
    });
}
```

### Dependency Injection

Share logic across handlers with zero boilerplate. Dependencies are resolved once per request and cached.

```zig
fn commonParams(req: *zigmund.Request) CommonQueryParams {
    return .{
        .q = req.queryParam("q"),
        .skip = if (req.queryParam("skip")) |s| std.fmt.parseInt(u32, s, 10) catch 0 else 0,
        .limit = if (req.queryParam("limit")) |l| std.fmt.parseInt(u32, l, 10) catch 100 else 100,
    };
}

fn readItems(
    commons: zigmund.Depends(commonParams, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const params = commons.value.?;
    return zigmund.Response.json(allocator, .{ .q = params.q, .skip = params.skip });
}
```

### WebSocket

Upgrade any route to a WebSocket with the same routing conventions.

```zig
fn chatHandler(
    conn: *zigmund.runtime.websocket.Connection,
    _: *zigmund.Request,
    _: std.mem.Allocator,
) anyerror!void {
    try conn.sendText("connected");
    while (true) {
        const msg = conn.receiveSmall() catch |err| switch (err) {
            error.ConnectionClosed => return,
            error.Timeout => continue,
            else => return err,
        };
        if (msg.opcode == .text) try conn.sendText(msg.data);
    }
}
```

---

## Performance

Zigmund is built for production workloads where latency matters:

- **Zero-allocation routing** -- route matching is resolved at compile time with no heap allocation on the hot path.
- **Comptime handler analysis** -- parameter extraction, dependency graphs, and OpenAPI schemas are computed during compilation, not at request time.
- **Multi-worker serving** -- spawn multiple OS threads behind a single listener to saturate all available cores.
- **Native Zig execution** -- no garbage collector, no interpreter overhead. Handlers compile to tight machine code.

---

## Documentation

The `docs/` directory is organized into sections:

| Section | Contents |
|---|---|
| **tutorial/** | Step-by-step guide from Hello World to a complete API |
| **zig-guide/** | Zig language primer for developers coming from Python/Go/Rust |
| **advanced/** | Middleware authoring, custom serialization, deployment patterns |
| **how-to/** | Focused recipes for common tasks |
| **reference/** | API reference for every exported type and function |

---

## CLI

Zigmund ships with a built-in CLI for development and introspection:

```bash
zig build run -- serve          # Start the production server
zig build run -- dev            # Start with hot-reload for development
zig build run -- routes         # Print the route table
zig build run -- openapi        # Dump the OpenAPI 3.1 JSON to stdout
zig build run -- cloud          # Cloud deployment helpers
```

Additional build commands:

```bash
zig build test                  # Run the full test suite
zig build perf                  # Run performance benchmarks
zig build check                 # Compile without running (type-check)
```

---

## Project Status

**Production-ready.** Zigmund has achieved 118/118 FastAPI parity examples across 26 pull requests, covering:

- All parameter types (query, path, header, cookie, body, form, file)
- Dependency injection with cleanup and scoping
- Full OpenAPI 3.1 schema generation with Swagger UI and ReDoc
- Security schemes (API key, HTTP auth, OAuth2, OpenID Connect, JWT)
- Middleware pipeline (CORS, rate limiting, CSRF, compression, sessions, timeouts, HTTPS redirect, trusted hosts)
- WebSocket handlers with security
- Response model filtering and computed fields
- In-process test client with cookie persistence and WebSocket sessions
- Background tasks, content negotiation, API versioning, health checks
- Structured validation errors and RFC 9457 Problem Details

---

## License

MIT -- see [LICENSE](LICENSE) for details.

Copyright (c) 2026 Softorize.
