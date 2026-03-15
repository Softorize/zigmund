# Installation

This guide walks you through installing Zig, adding Zigmund to your project, and running your first server.

---

## Prerequisites

- **Zig 0.15.2 or later** -- Download from [ziglang.org/download](https://ziglang.org/download/)
- **OpenSSL development libraries** -- Required for TLS support
  - macOS: `brew install openssl`
  - Ubuntu/Debian: `apt install libssl-dev`
  - Fedora: `dnf install openssl-devel`
- **zlib** -- Usually available by default; if not, install via your package manager

Verify your Zig installation:

```bash
zig version
# Should print 0.15.2 or later
```

---

## Add Zigmund to Your Project

### 1. Initialize a new Zig project (if needed)

```bash
mkdir my-api && cd my-api
zig init
```

### 2. Fetch the Zigmund dependency

```bash
zig fetch --save git+https://github.com/Softorize/zigmund
```

This adds Zigmund to your `build.zig.zon` dependencies automatically.

### 3. Configure build.zig

In your `build.zig`, add the Zigmund module to your executable:

```zig
const zigmund_dep = b.dependency("zigmund", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zigmund", zigmund_dep.module("zigmund"));
```

You also need to link the C libraries that Zigmund depends on:

```zig
exe.linkLibC();
exe.linkSystemLibrary("ssl");
exe.linkSystemLibrary("crypto");
exe.linkSystemLibrary("z");
```

On macOS with Homebrew, you may need to add include and library paths:

```zig
exe.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
exe.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
```

---

## Verify the Installation

Create a minimal application in `src/main.zig`:

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

Build and run:

```bash
zig build run -- serve
```

Visit `http://localhost:8080` in your browser. You should see:

```json
{"message": "Hello World"}
```

Interactive API documentation is available at `http://localhost:8080/docs`.

---

## Running the Server

### Production mode

```bash
zig build run -- serve
```

Starts the server with default settings. Use flags to customize:

```bash
zig build run -- serve --host 0.0.0.0 --port 3000 --workers 4
```

### Development mode

```bash
zig build run -- dev
```

Development mode enables automatic reloading and verbose logging for a faster development cycle.

---

## CLI Overview

Zigmund ships with a built-in CLI that provides several commands:

| Command   | Description                                      |
|-----------|--------------------------------------------------|
| `serve`   | Start the HTTP server (production mode)          |
| `dev`     | Start the server in development mode             |
| `routes`  | Print all registered routes                      |
| `openapi` | Export the OpenAPI 3.1 JSON specification        |
| `cloud`   | Cloud deployment helpers                         |

Run any command with:

```bash
zig build run -- <command>
```

For example, to see all registered routes:

```bash
zig build run -- routes
```

To export the OpenAPI spec to a file:

```bash
zig build run -- openapi > openapi.json
```

---

## Next Steps

- [First Steps Tutorial](tutorial/first-steps.md) -- Build a complete API step by step
- [Tutorial Index](tutorial/index.md) -- Browse all tutorial topics
- [API Reference](reference/index.md) -- Detailed API documentation
