# Welcome to Zigmund

Zigmund is a high-performance, type-safe web framework for Zig, inspired by FastAPI. It provides automatic parameter injection, OpenAPI generation, dependency injection, and a comprehensive middleware stack -- all leveraging Zig's comptime capabilities.

---

## Getting Started

New to Zigmund? Start here:

- [Installation](installation.md) -- Install Zig 0.15.2 and add Zigmund to your project
- [First Steps](tutorial/first-steps.md) -- Build your first Zigmund application in minutes

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
    var app = try zigmund.App.init(gpa.allocator(), .{ .title = "My API", .version = "0.1.0" });
    defer app.deinit();
    try app.get("/", hello, .{});
    try app.serve(.{});
}
```

Run it with:

```bash
zig build run -- serve
```

Your API is now live at `http://localhost:8080`, with interactive documentation at `/docs`.

---

## Documentation Sections

### [Tutorial](tutorial/index.md)

Step-by-step guides covering all framework features, from path parameters and request bodies to dependency injection, security, and testing. Start here if you are learning Zigmund.

### [Zig Guide](zig-guide/index.md)

Zig-specific concepts for developers coming from Python, TypeScript, or other dynamic languages. Covers comptime, error handling, memory management, and how Zigmund maps FastAPI patterns to Zig idioms.

### [Advanced](advanced/index.md)

Advanced features and patterns: custom responses, WebSockets, sub-applications, OpenAPI callbacks, proxy configuration, and more.

### [How-To](how-to/index.md)

Quick recipes for common tasks: conditional OpenAPI, custom Swagger UI, GraphQL integration, extending the OpenAPI schema, and database testing.

### [Reference](reference/index.md)

Complete API reference for every public type and function in Zigmund: `App`, `Router`, `Request`, `Response`, parameters, dependencies, security, middleware, and more.

### [Deployment](deployment/index.md)

Docker images, production configuration, TLS setup, reverse proxy integration, and cloud deployment guides.
