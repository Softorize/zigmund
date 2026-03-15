# Cookie Parameters

Read values from HTTP cookies using the `Cookie()` parameter marker.

## Overview

Cookies are small pieces of data stored in the browser and sent with every request to the same domain. They are commonly used for session management, user preferences, and tracking. In Zigmund you extract cookie values with the `Cookie()` parameter marker, following the same pattern as `Path()`, `Query()`, and `Header()`.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn readSessionCookie(
    session_id: zigmund.Cookie([]const u8, .{
        .alias = "session_id",
        .description = "Browser session cookie",
    }),
    ads_id: zigmund.Cookie([]const u8, .{
        .alias = "ads_id",
        .description = "Advertising tracking cookie",
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .session_id = session_id.value orelse "not set",
        .ads_id = ads_id.value orelse "not set",
    });
}

// Registration:
// app.get("/session", readSessionCookie, .{})
```

### Request example

```bash
curl http://127.0.0.1:8000/session \
  -H "Cookie: session_id=abc123; ads_id=xyz789"
```

Response:

```json
{
  "session_id": "abc123",
  "ads_id": "xyz789"
}
```

When cookies are missing:

```bash
curl http://127.0.0.1:8000/session
```

```json
{
  "session_id": "not set",
  "ads_id": "not set"
}
```

## How It Works

### 1. Declare cookie parameters with Cookie()

Add `zigmund.Cookie(T, options)` parameters to your handler signature:

```zig
fn readSessionCookie(
    session_id: zigmund.Cookie([]const u8, .{ .alias = "session_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
```

### 2. The .alias option

`.alias` specifies the cookie name as it appears in the `Cookie` header. Cookie names are case-sensitive:

```
Cookie: session_id=abc123
        ^^^^^^^^^^
        matches .alias = "session_id"
```

### 3. Optional cookies with orelse

Cookie values use `.value` which is an optional. Since cookies may or may not be present in any given request, use `orelse` to provide defaults:

```zig
const sid = session_id.value orelse "not set";
```

Note the difference from `Path()` parameters: path parameters use `.value.?` (unwrap, because the value is always present), while cookie parameters typically use `.value orelse default` (because cookies are inherently optional -- the client may not have them set).

### 4. The .description option

The `.description` field adds documentation to the cookie parameter in the OpenAPI spec. This is particularly useful for cookies, since their purpose is not always obvious from their name:

```zig
session_id: zigmund.Cookie([]const u8, .{
    .alias = "session_id",
    .description = "Browser session cookie",
}),
```

### 5. CookieOptions reference

| Field              | Type                      | Default | Description                                        |
|--------------------|---------------------------|---------|----------------------------------------------------|
| `alias`            | `?[]const u8`             | `null`  | The cookie name to read.                           |
| `description`      | `?[]const u8`             | `null`  | Description for OpenAPI docs.                      |
| `gt`, `ge`, `lt`, `le` | `?f64`               | `null`  | Numeric validation constraints.                    |
| `min_length`       | `?usize`                  | `null`  | Minimum string length.                             |
| `max_length`       | `?usize`                  | `null`  | Maximum string length.                             |
| `pattern`          | `?[]const u8`             | `null`  | Regex pattern for validation.                      |
| `enum_values`      | `[]const []const u8`      | `&.{}`  | Restrict to a fixed set of string values.          |

### 6. Setting cookies in responses

While `Cookie()` reads incoming cookies, you set outgoing cookies on the response using `setCookie`:

```zig
fn login(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var response = try zigmund.Response.json(allocator, .{ .logged_in = true });
    try response.setCookie(allocator, "session_id", "new_session_value", .{
        .http_only = true,
        .secure = true,
        .same_site = .strict,
        .max_age_seconds = 3600,
    });
    return response;
}
```

To delete a cookie, use `deleteCookie`:

```zig
try response.deleteCookie(allocator, "session_id", .{});
```

## Key Points

- `Cookie()` extracts values from the HTTP `Cookie` header using the `.alias` as the cookie name.
- Cookie parameters are inherently optional -- use `orelse` to provide defaults when a cookie is not set.
- Use `.description` to document the purpose of each cookie in the OpenAPI spec.
- To set cookies on outgoing responses, use `response.setCookie()` with options for security attributes (HttpOnly, Secure, SameSite, Max-Age).
- To delete a cookie, use `response.deleteCookie()`, which sets Max-Age to 0 and the Expires header to a past date.

## See Also

- [Header Parameters](header-params.md) -- reading values from HTTP headers.
- [Query Parameters](query-parameters.md) -- reading values from the query string.
- [Response Status Code](response-status-code.md) -- setting status codes on responses.
