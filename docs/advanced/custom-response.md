# Custom Response

Zigmund provides built-in response constructors for the most common content types: HTML, plain text, redirects, and JSON. Each constructor sets the appropriate `Content-Type` header automatically.

## Overview

By default, Zigmund handlers return JSON responses via `Response.json()`. However, many applications need to serve HTML pages, return plain text, or issue redirects. Zigmund provides dedicated constructors on the `Response` type for each of these cases, so you do not need to manually set headers or format bodies.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn htmlResponse() zigmund.Response {
    return zigmund.Response.html(
        \\<html><body><h1>Hello from Zigmund</h1></body></html>
    );
}

fn textResponse() zigmund.Response {
    return zigmund.Response.text("Plain text response from Zigmund");
}

fn redirectResponse(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.redirect(allocator, "/html", .temporary_redirect);
}

fn jsonResponse(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .response_type = "json",
        .message = "Standard JSON response",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/html", htmlResponse, .{
        .summary = "Return an HTML response",
    });
    try app.get("/text", textResponse, .{
        .summary = "Return a plain text response",
    });
    try app.get("/redirect", redirectResponse, .{
        .summary = "Return a redirect response",
    });
    try app.get("/json", jsonResponse, .{
        .summary = "Return a JSON response",
    });
}
```

## How It Works

### Response.html

Returns an HTML response with `Content-Type: text/html`.

```zig
return zigmund.Response.html(
    \\<html><body><h1>Hello</h1></body></html>
);
```

The argument is a `[]const u8` containing the HTML body. This constructor does not require an allocator because the body is typically a comptime-known string literal (using Zig's multiline string syntax `\\`).

### Response.text

Returns a plain text response with `Content-Type: text/plain`.

```zig
return zigmund.Response.text("Plain text content");
```

Like `html()`, this constructor works with string literals and does not require an allocator.

### Response.redirect

Returns a redirect response with the specified status code and a `Location` header pointing to the target URL.

```zig
return zigmund.Response.redirect(allocator, "/target-path", .temporary_redirect);
```

Common redirect status codes:

| Status                  | HTTP Code | Use Case                            |
|-------------------------|-----------|-------------------------------------|
| `.temporary_redirect`   | 307       | Temporary redirect, preserves method |
| `.permanent_redirect`   | 308       | Permanent redirect, preserves method |
| `.moved_permanently`    | 301       | Permanent redirect, may change method |
| `.found`                | 302       | Temporary redirect, may change method |
| `.see_other`            | 303       | Redirect after POST (always GET)     |

### Response.json

Returns a JSON response with `Content-Type: application/json`. The value is serialized using `std.json`.

```zig
return zigmund.Response.json(allocator, .{
    .key = "value",
    .count = 42,
});
```

This is the most common response type and requires an allocator for serialization.

## Key Points

- Each response constructor sets the correct `Content-Type` header automatically.
- `Response.html()` and `Response.text()` do not require an allocator when used with string literals.
- `Response.redirect()` requires an allocator and accepts a redirect status code enum value.
- `Response.json()` serializes any Zig value (structs, anonymous structs, slices) into JSON.
- You can chain `.withStatus()` on any response to override the default status code.
- All response types can have custom headers added via `response.setHeader()`.

## See Also

- [Response Directly](response-directly.md) -- return responses without a response model.
- [Response Headers](response-headers.md) -- add custom headers to any response.
- [Response Change Status Code](response-change-status-code.md) -- dynamically set status codes.
- [Templates](templates.md) -- render HTML from template files.
