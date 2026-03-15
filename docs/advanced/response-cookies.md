# Response Cookies

Set, configure, and delete HTTP cookies on responses. Zigmund provides `setCookie()` with full control over cookie attributes and `deleteCookie()` to remove cookies from the client.

## Overview

Cookies are small pieces of data sent from the server to the client via `Set-Cookie` headers. They are commonly used for session management, user preferences, and tracking. Zigmund provides a structured API for setting cookies with security attributes like `HttpOnly`, `Secure`, `SameSite`, and expiration controls.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn setCookies(allocator: std.mem.Allocator) !zigmund.Response {
    var response = try zigmund.Response.json(allocator, .{
        .message = "Cookies have been set",
    });
    try response.setCookie(allocator, "session_id", "abc-123-def", .{
        .path = "/",
        .http_only = true,
        .secure = true,
        .same_site = .lax,
        .max_age_seconds = 3600,
    });
    try response.setCookie(allocator, "preferences", "dark-mode", .{
        .path = "/",
        .http_only = false,
        .secure = false,
        .max_age_seconds = 86400 * 30,
    });
    return response;
}

fn deleteCookie(allocator: std.mem.Allocator) !zigmund.Response {
    var response = try zigmund.Response.json(allocator, .{
        .message = "Cookie deleted",
    });
    try response.deleteCookie(allocator, "session_id", .{});
    return response;
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/set", setCookies, .{
        .summary = "Set response cookies with various options",
    });
    try app.get("/delete", deleteCookie, .{
        .summary = "Delete a response cookie",
    });
}
```

## How It Works

### 1. Setting a Cookie

Use `response.setCookie(allocator, name, value, options)`:

```zig
try response.setCookie(allocator, "session_id", "abc-123-def", .{
    .path = "/",
    .http_only = true,
    .secure = true,
    .same_site = .lax,
    .max_age_seconds = 3600,
});
```

The options struct controls the cookie's behavior:

| Field              | Type         | Description                                              |
|--------------------|--------------|----------------------------------------------------------|
| `path`             | `[]const u8` | URL path scope for the cookie. `"/"` means all paths.   |
| `http_only`        | `bool`       | If true, the cookie is inaccessible to JavaScript.       |
| `secure`           | `bool`       | If true, the cookie is only sent over HTTPS.             |
| `same_site`        | enum         | Controls cross-site request behavior (`.lax`, `.strict`, `.none`). |
| `max_age_seconds`  | `i64`        | Number of seconds until the cookie expires.              |

### 2. Security Best Practices

For session cookies, always set:

- `http_only = true` -- prevents JavaScript from reading the cookie, mitigating XSS attacks.
- `secure = true` -- ensures the cookie is only transmitted over HTTPS.
- `same_site = .lax` or `.strict` -- prevents cross-site request forgery (CSRF).

For non-sensitive cookies (like UI preferences), you can relax these settings:

```zig
try response.setCookie(allocator, "preferences", "dark-mode", .{
    .path = "/",
    .http_only = false,    // JavaScript needs to read this
    .secure = false,       // Works on HTTP during development
    .max_age_seconds = 86400 * 30,  // 30 days
});
```

### 3. Deleting a Cookie

Use `response.deleteCookie(allocator, name, options)` to instruct the client to remove a cookie:

```zig
try response.deleteCookie(allocator, "session_id", .{});
```

This sets the cookie with an expired `Max-Age`, causing the browser to remove it. The options struct allows you to specify the `path` and `domain` to match the original cookie's scope.

### 4. Multiple Cookies

You can set multiple cookies on the same response by calling `setCookie` multiple times. Each call adds a separate `Set-Cookie` header.

## Key Points

- Use `setCookie()` with the full options struct to control cookie behavior.
- Always use `http_only`, `secure`, and `same_site` for session cookies.
- `deleteCookie()` removes a cookie by setting an expired `Max-Age`.
- Multiple cookies can be set on a single response.
- The response must be declared as `var` because `setCookie` and `deleteCookie` mutate the response.

## See Also

- [Response Headers](response-headers.md) -- set other custom headers on responses.
- [Security](security.md) -- authentication patterns that often use cookies.
- [Middleware](middleware.md) -- set cookies globally via middleware hooks.
