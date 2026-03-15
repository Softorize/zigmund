# Response Directly

Return raw `Response` objects from handlers, bypassing any response model layer. This gives you full control over the response body, status code, and headers.

## Overview

In most cases, Zigmund handlers return structured data that can be documented via a response model. However, there are situations where you need to return a response directly -- for example, returning different content types from the same handler, or constructing a response that does not fit a predefined schema. Returning a `zigmund.Response` directly skips response model validation and gives you complete control.

This is the Zig equivalent of returning a `Response` object directly in FastAPI instead of a Pydantic model.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn directText() zigmund.Response {
    return zigmund.Response.text("Hello, this is a direct text response");
}

fn directJson(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .message = "This JSON was returned directly, not through a response model",
    });
}

fn directHtml() zigmund.Response {
    return zigmund.Response.html(
        \\<html><body><p>Direct HTML response, bypassing response_model</p></body></html>
    );
}

fn directWithStatus(allocator: std.mem.Allocator) !zigmund.Response {
    return (try zigmund.Response.json(allocator, .{
        .detail = "Resource has been created directly",
    })).withStatus(.created);
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/text", directText, .{
        .summary = "Return a direct text response (no response model)",
    });
    try app.get("/json", directJson, .{
        .summary = "Return a direct JSON response (no response model)",
    });
    try app.get("/html", directHtml, .{
        .summary = "Return a direct HTML response (no response model)",
    });
    try app.post("/create", directWithStatus, .{
        .summary = "Return a direct response with custom status code",
        .status_code = .created,
    });
}
```

## How It Works

### 1. Direct Text Response

The simplest direct response. No allocator needed for string literals:

```zig
fn directText() zigmund.Response {
    return zigmund.Response.text("Hello, this is a direct text response");
}
```

Notice the handler signature: it returns `zigmund.Response` (no error union `!`) and takes no parameters. Zigmund's flexible handler injection lets you declare only the parameters you actually need.

### 2. Direct JSON Response

JSON serialization requires an allocator:

```zig
fn directJson(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .message = "Direct JSON response",
    });
}
```

### 3. Direct HTML Response

HTML string literals use Zig's multiline string syntax:

```zig
fn directHtml() zigmund.Response {
    return zigmund.Response.html(
        \\<html><body><p>Direct HTML</p></body></html>
    );
}
```

### 4. Custom Status Code

Chain `.withStatus()` to override the default 200 status:

```zig
return (try zigmund.Response.json(allocator, .{
    .detail = "Resource created",
})).withStatus(.created);
```

When doing this, set the `status_code` in route options to match for accurate OpenAPI documentation:

```zig
try app.post("/create", directWithStatus, .{
    .status_code = .created,
});
```

## Key Points

- Returning `zigmund.Response` directly gives full control over the response body, headers, and status code.
- No response model validation is applied -- the handler is responsible for the response shape.
- Handler signatures are flexible: omit parameters you do not need (no `req`, no `allocator`, etc.).
- Handlers that do not perform allocation can return `zigmund.Response` without the error union (`!`).
- You can mix response types within the same application -- some handlers use response models, others return directly.

## See Also

- [Custom Response](custom-response.md) -- all available response constructors (HTML, text, redirect, JSON).
- [Response Headers](response-headers.md) -- add custom headers to direct responses.
- [Additional Status Codes](additional-status-codes.md) -- set non-200 status codes.
