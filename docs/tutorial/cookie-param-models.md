# Cookie Parameter Models

Group related cookie values into a single Zig struct so your handler receives a clean, typed object instead of reading cookies one at a time.

## Overview

Cookies often carry multiple related values -- a session identifier, a theme preference, a locale setting. Rather than extracting each cookie individually, Zigmund lets you define a struct whose fields map to cookie names and pass it to `zigmund.Cookie`. The framework reads the `Cookie` header, parses key-value pairs, and populates your struct automatically.

This pattern mirrors [Query Parameter Models](query-param-models.md) and [Header Parameter Models](header-param-models.md), giving all parameter sources a consistent struct-based interface.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const CookieContext = struct {
    session_id: ?[]const u8 = null,
    theme: []const u8 = "light",
};

fn implemented(
    cookies: zigmund.Cookie(CookieContext, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = "tutorial/cookie-param-models/",
        .cookies = cookies.value.?,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/cookie-param-models", implemented, .{
        .summary = "Parity implementation for tutorial/cookie-param-models/",
        .tags = &.{ "parity", "tutorial" },
    });
}
```

## How It Works

1. **Define the model.** `CookieContext` is a plain struct where each field name corresponds to a cookie name:
   - `session_id` is optional (`?[]const u8`), defaulting to `null` when the cookie is absent.
   - `theme` is a required string that defaults to `"light"` when not sent by the client.

2. **Wrap with `zigmund.Cookie`.** `zigmund.Cookie(CookieContext, .{})` instructs the framework to parse the `Cookie` request header and map its key-value pairs to `CookieContext` fields. Field names use underscores in Zig; Zigmund handles the mapping to cookie names (which may use hyphens or other conventions depending on configuration).

3. **Access the values.** `cookies.value.?` gives you a fully populated `CookieContext`. Fields that were absent in the request carry their declared default values.

4. **Return the result.** The populated struct can be serialized directly into the JSON response or used for any business logic.

## Key Points

- Fields with default values are optional cookies. Fields without defaults are required -- a missing required cookie produces a `422` error.
- Cookie values are always transmitted as strings over HTTP. Zigmund performs automatic type coercion for non-string field types (e.g., `u32`, `bool`).
- Cookie parameter models are reflected in the OpenAPI schema as individual cookie parameters, matching how documentation tools expect them.
- For setting cookies in the response, use `Response.setCookie()` or the response headers API. This page covers reading cookies from the request only.
- The struct can be reused across multiple handlers to ensure consistent cookie handling throughout your application.

## See Also

- [Cookie Parameters](cookie-params.md) -- Extract individual cookie values without a model struct.
- [Query Parameter Models](query-param-models.md) -- The same grouping pattern applied to query parameters.
- [Header Parameter Models](header-param-models.md) -- The same grouping pattern applied to HTTP headers.
- [Security](security.md) -- Session-based authentication patterns that build on cookie handling.
