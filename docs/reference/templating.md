# Templating Reference

## Overview

Zigmund provides two template rendering systems: a simple placeholder-based engine and a Jinja2-compatible engine with full control flow, filters, inheritance, and macros.

## TemplatesIntegration

### Initialization

```zig
pub fn init(allocator: std.mem.Allocator, templates_dir: []const u8) !TemplatesIntegration
```

Creates a template integration bound to a directory.

### `deinit`

```zig
pub fn deinit(self: *TemplatesIntegration) void
```

Frees the owned directory path.

### Simple Rendering

#### `render`

```zig
pub fn render(
    self: *const TemplatesIntegration,
    template_name: []const u8,
    bindings: []const TemplateBinding,
) ![]u8
```

Renders a template by replacing `{{key}}` and `{{ key }}` placeholders with values. Returns an owned string.

#### `renderHtmlResponse`

```zig
pub fn renderHtmlResponse(
    self: *const TemplatesIntegration,
    template_name: []const u8,
    bindings: []const TemplateBinding,
) !Response
```

Renders a template and returns it as an HTML response.

### Jinja2 Rendering

#### `renderJinja`

```zig
pub fn renderJinja(
    self: *const TemplatesIntegration,
    template_name: []const u8,
    vars: []const struct { []const u8, template.Value },
) ![]u8
```

Renders using the Jinja2-compatible engine. Supports control flow (`{% if %}`, `{% for %}`), filters, template inheritance (`{% extends %}`), and macros.

#### `renderJinjaHtmlResponse`

```zig
pub fn renderJinjaHtmlResponse(
    self: *const TemplatesIntegration,
    template_name: []const u8,
    vars: []const struct { []const u8, template.Value },
) !Response
```

Renders a Jinja2 template as an HTML response.

## TemplateBinding

Used with the simple rendering engine.

```zig
pub const TemplateBinding = struct {
    key: []const u8,
    value: TemplateValue,
};
```

## TemplateValue

```zig
pub const TemplateValue = union(enum) {
    string: []const u8,
    integer: i64,
    unsigned: u64,
    float: f64,
    boolean: bool,
};
```

## JinjaEngine

The standalone Jinja2 engine, available as `zigmund.JinjaEngine`.

```zig
pub const JinjaEngine = template.Engine;
```

## renderJinjaString

```zig
pub fn renderJinjaString(allocator: std.mem.Allocator, source: []const u8, vars: anytype) ![]u8
```

Renders a Jinja2 template from a string (not a file). Available as `zigmund.renderJinjaString`.

## Example

```zig
const zigmund = @import("zigmund");

fn pageHandler(allocator: std.mem.Allocator) !zigmund.Response {
    var templates = try zigmund.TemplatesIntegration.init(allocator, "./templates");
    defer templates.deinit();

    // Simple placeholder rendering
    return templates.renderHtmlResponse("page.html", &.{
        .{ .key = "title", .value = .{ .string = "Home" } },
        .{ .key = "count", .value = .{ .unsigned = 42 } },
    });
}

fn jinjaHandler(allocator: std.mem.Allocator) !zigmund.Response {
    var templates = try zigmund.TemplatesIntegration.init(allocator, "./templates");
    defer templates.deinit();

    // Jinja2-compatible rendering
    return templates.renderJinjaHtmlResponse("page.html", &.{
        .{ "title", .{ .string = "Home" } },
        .{ "items", .{ .list = &.{ ... } } },
    });
}
```
