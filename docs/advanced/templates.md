# Templates

Render HTML pages from template files using Zigmund's built-in template integration. Templates support variable binding with typed values, enabling dynamic HTML generation.

## Overview

While Zigmund is primarily designed for JSON APIs, many applications also need to serve HTML pages. The `TemplatesIntegration` module provides a simple template engine that loads HTML files from a directory, substitutes variable bindings, and returns the result as an HTML response.

This is the Zig equivalent of FastAPI's Jinja2 template integration via `Jinja2Templates`.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn renderTemplate(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var templates = zigmund.TemplatesIntegration.init(
        allocator,
        "examples/parity/assets/templates",
    ) catch {
        return zigmund.Response.html("<h1>Template directory not configured</h1>");
    };
    defer templates.deinit();

    const bindings = [_]zigmund.TemplateBinding{
        .{ .key = "name", .value = .{ .string = "zigmund" } },
        .{ .key = "id", .value = .{ .unsigned = 42 } },
    };

    return templates.renderHtmlResponse("index.html", &bindings) catch {
        return zigmund.Response.html("<h1>Template file not found</h1>");
    };
}

fn templateInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .templates_dir = "examples/parity/assets/templates",
        .template = "index.html",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/page", renderTemplate, .{
        .summary = "Render HTML using template integration",
    });
    try app.get("/page/info", templateInfo, .{
        .summary = "Template integration metadata",
    });
}
```

## How It Works

### 1. Initializing the Template Engine

Create a `TemplatesIntegration` instance pointing to your templates directory:

```zig
var templates = zigmund.TemplatesIntegration.init(
    allocator,
    "path/to/templates",
) catch {
    return zigmund.Response.html("<h1>Template directory not configured</h1>");
};
defer templates.deinit();
```

The `init` function validates that the directory exists. Always pair with `defer templates.deinit()` to release resources.

### 2. Defining Template Bindings

Bindings are key-value pairs that substitute variables in the template:

```zig
const bindings = [_]zigmund.TemplateBinding{
    .{ .key = "name", .value = .{ .string = "zigmund" } },
    .{ .key = "id", .value = .{ .unsigned = 42 } },
};
```

The `value` field is a tagged union supporting multiple types:

| Value Type    | Zig Type       | Example                            |
|---------------|----------------|------------------------------------|
| `.string`     | `[]const u8`   | `.{ .string = "hello" }`          |
| `.unsigned`   | `u64`          | `.{ .unsigned = 42 }`             |
| `.signed`     | `i64`          | `.{ .signed = -1 }`               |
| `.float`      | `f64`          | `.{ .float = 3.14 }`              |
| `.boolean`    | `bool`         | `.{ .boolean = true }`            |

### 3. Rendering a Template

Call `renderHtmlResponse` with the template filename and bindings:

```zig
return templates.renderHtmlResponse("index.html", &bindings) catch {
    return zigmund.Response.html("<h1>Template file not found</h1>");
};
```

This loads the template file, performs variable substitution, and returns a `Response` with `Content-Type: text/html`.

### 4. Error Handling

Both `init` and `renderHtmlResponse` can fail. Handle errors gracefully with fallback responses:

- `init` fails if the template directory does not exist.
- `renderHtmlResponse` fails if the template file is not found or cannot be read.

### 5. Template File Format

Template files are standard HTML with placeholder syntax for variable substitution. Place template files in the configured directory and reference them by filename when rendering.

## Key Points

- `TemplatesIntegration` provides simple HTML template rendering with variable binding.
- Templates are loaded from a directory specified at initialization.
- Bindings support strings, integers (signed/unsigned), floats, and booleans.
- Always call `defer templates.deinit()` after initialization.
- Handle initialization and rendering errors with fallback HTML responses.
- For complex templating needs, consider generating HTML in Zig code or integrating an external template engine.

## See Also

- [Custom Response](custom-response.md) -- return HTML directly without templates.
- [Response Directly](response-directly.md) -- return responses without a response model.
- [Settings](settings.md) -- load template directory paths from configuration.
