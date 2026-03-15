# First Steps

Build and run a minimal Zigmund application that serves a single JSON endpoint.

## Overview

Every Zigmund application starts with three steps: initialize the app, register routes, and start the server. This page walks through the simplest possible application to introduce those building blocks before you add parameters, request bodies, or middleware.

Zigmund follows the same patterns as FastAPI -- if you have used FastAPI in Python, the structure will feel familiar. The difference is that everything is checked at compile time by the Zig compiler, so many classes of bugs that would surface at runtime in Python are caught before your program ever starts.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

// A handler function. It receives the raw request and a per-request allocator,
// and returns a Response (or an error).
fn root(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req; // Not used in this handler.
    return zigmund.Response.json(allocator, .{ .message = "Hello World" });
}

pub fn main() !void {
    // 1. Create an allocator. The GeneralPurposeAllocator is a good default
    //    for applications; it catches leaks and double-frees in debug builds.
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    // 2. Initialize the application with metadata used by the auto-generated
    //    OpenAPI documentation (available at /docs by default).
    var app = try zigmund.App.init(gpa.allocator(), .{
        .title = "Parity Tutorial",
        .version = "0.1.0",
    });
    defer app.deinit();

    // 3. Register the handler for GET /.
    try app.get("/", root, .{});

    // 4. Start listening. The default address is 127.0.0.1:8000.
    try app.serve(.{});
}
```

## How It Works

### 1. App.init

`App.init` accepts an allocator and an `AppConfig` struct. The two required fields are:

| Field     | Type           | Purpose                                        |
|-----------|----------------|-------------------------------------------------|
| `title`   | `[]const u8`   | Application name shown in the OpenAPI spec.     |
| `version` | `[]const u8`   | Semantic version shown in the OpenAPI spec.     |

Optional fields include `summary`, `description`, `docs_url`, `redoc_url`, and others. See the [AppConfig reference](../reference/) for the full list.

Always pair `App.init` with `defer app.deinit()` to release internal memory when the application shuts down.

### 2. Route registration with app.get

`app.get(path, handler, options)` registers a handler for HTTP GET requests that match `path`. Zigmund provides one method per HTTP verb:

- `app.get`
- `app.post`
- `app.put`
- `app.patch`
- `app.delete`
- `app.options`

The third argument is a `RouteOptions` struct. Passing `.{}` accepts all defaults (no summary, no tags, standard 200 status). You can add OpenAPI metadata here:

```zig
try app.get("/", root, .{
    .summary = "Return a greeting",
    .tags = &.{"tutorial"},
});
```

### 3. Handler signature

The simplest handler signature takes two arguments:

```
fn handler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response
```

- `req` -- a pointer to the incoming request. It gives you access to headers, query string, body bytes, and more.
- `allocator` -- a per-request arena allocator. Any memory you allocate with it is freed automatically after the response is sent, so you never need to manually free intermediate buffers.
- The return type `!zigmund.Response` is a Zig error union. You can return an error at any point, and Zigmund will translate it into an appropriate HTTP error response (or route it to a registered exception handler).

As later pages show, Zigmund also supports an alternative handler signature that replaces `req` with typed parameter markers (Path, Query, Body, etc.), allowing the framework to inject parsed values directly.

### 4. Response.json

`Response.json(allocator, value)` serializes any Zig value into a JSON response body. It uses `std.json` under the hood and sets the `Content-Type` header to `application/json`. Anonymous struct literals (`.{ .key = value }`) are the most common way to build JSON payloads inline.

Other response constructors include:

| Constructor        | Content-Type              |
|--------------------|---------------------------|
| `Response.text`    | `text/plain`              |
| `Response.html`    | `text/html`               |
| `Response.json`    | `application/json`        |

### 5. app.serve

`app.serve(config)` starts the HTTP server and blocks until shutdown. Passing `.{}` uses the defaults:

| Default           | Value         |
|-------------------|---------------|
| Host              | `127.0.0.1`  |
| Port              | `8000`        |
| Worker threads    | CPU count     |

You can override any field:

```zig
try app.serve(.{
    .host = "0.0.0.0",
    .port = 3000,
});
```

## Key Points

- A complete Zigmund application needs fewer than 20 lines of code.
- `App.init` requires only `title` and `version`. Everything else has sensible defaults.
- Handlers return `!zigmund.Response`, which means they can return either a response or an error.
- The per-request allocator frees all allocations automatically after the response is sent.
- OpenAPI documentation is generated and served at `/docs` (Swagger UI) and `/redoc` (ReDoc) by default -- no extra setup required.

## See Also

- [Path Parameters](path-parameters.md) -- capture dynamic segments from the URL.
- [Query Parameters](query-parameters.md) -- read optional or required query string values.
- [Request Body](request-body.md) -- accept JSON payloads in POST/PUT/PATCH handlers.
