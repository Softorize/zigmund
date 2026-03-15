# Middleware Reference

## Overview

Zigmund middleware intercepts requests and responses in the processing pipeline. Middleware can be added via `app.addMiddleware` and runs in registration order for requests and reverse order for responses.

## Middleware Type

```zig
pub const Middleware = struct {
    name: []const u8,
    context: ?*anyopaque = null,
    request_hook: ?RequestMiddlewareFn = null,
    response_hook: ?ResponseMiddlewareFn = null,
    request_hook_with_context: ?RequestMiddlewareWithContextFn = null,
    response_hook_with_context: ?ResponseMiddlewareWithContextFn = null,
    deinit_hook: ?MiddlewareDeinitFn = null,
};
```

## Built-in Middleware

### CORS -- `corsMw`

```zig
try app.addMiddleware(zigmund.corsMw(zigmund.CorsOptions{
    .allowed_origins = &.{ "https://example.com" },
    .allowed_methods = &.{ "GET", "POST" },
    .allow_credentials = true,
}));
```

**CorsOptions:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `allowed_origins` | `[]const []const u8` | `&.{"*"}` | Allowed origin domains |
| `allowed_methods` | `[]const []const u8` | `&.{"GET","POST","PUT","PATCH","DELETE","OPTIONS","HEAD"}` | Allowed HTTP methods |
| `allowed_headers` | `[]const []const u8` | `&.{"Content-Type","Authorization","Accept","Origin","X-Requested-With"}` | Allowed request headers |
| `expose_headers` | `[]const []const u8` | `&.{}` | Headers exposed to the browser |
| `allow_credentials` | `bool` | `false` | Allow credentials (cookies, auth) |
| `max_age` | `u32` | `86400` | Preflight cache duration in seconds |

### Rate Limiting -- `rateLimitMw`

```zig
try app.addMiddleware(zigmund.rateLimitMw(zigmund.RateLimitOptions{
    .max_requests = 100,
    .window_seconds = 60,
}));
```

**RateLimitOptions:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_requests` | `u32` | `100` | Maximum requests per window |
| `window_seconds` | `u32` | `60` | Window duration in seconds |
| `key_func` | `?*const fn (*Request) []const u8` | `null` | Custom client key extraction function |

### CSRF Protection -- `csrfMw`

```zig
try app.addMiddleware(zigmund.csrfMw(zigmund.CsrfOptions{}));
```

**CsrfOptions:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cookie_name` | `[]const u8` | `"_csrf_token"` | CSRF cookie name |
| `header_name` | `[]const u8` | `"X-CSRF-Token"` | Header to check for the token |
| `field_name` | `[]const u8` | `"csrf_token"` | Form field name for the token |
| `token_bytes` | `u8` | `32` | Token length in bytes (hex output is 2x) |
| `safe_methods` | `[]const std.http.Method` | `&.{.GET,.HEAD,.OPTIONS,.TRACE}` | Methods exempt from validation |
| `cookie_path` | `[]const u8` | `"/"` | Cookie path |
| `cookie_secure` | `bool` | `false` | Cookie secure flag |
| `cookie_same_site` | `enum{strict,lax,none}` | `.lax` | Cookie SameSite attribute |

### Response Compression -- `compressionMw`

```zig
try app.addMiddleware(zigmund.compressionMw(zigmund.CompressionOptions{}));
```

**CompressionOptions:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `min_size` | `usize` | `1024` | Minimum body size to trigger compression |
| `compressible_types` | `[]const []const u8` | (text, JSON, XML, JS, SVG) | Content types eligible for compression |
| `level` | `u4` | `6` | Compression level (1-9) |

### Session Management -- `sessionMw` / `sessionMwWithStore`

```zig
try app.addMiddleware(zigmund.sessionMw(zigmund.SessionOptions{}));

// Or with a custom store:
var store = zigmund.InMemoryStore.init(allocator);
try app.addMiddleware(zigmund.sessionMwWithStore(zigmund.SessionOptions{}, store.asSessionStore()));
```

**SessionOptions:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cookie_name` | `[]const u8` | `"session_id"` | Session cookie name |
| `max_age` | `u32` | `3600` | Session expiry in seconds |
| `cookie_path` | `[]const u8` | `"/"` | Cookie path |
| `http_only` | `bool` | `true` | HttpOnly flag |
| `secure` | `bool` | `false` | Secure flag |
| `same_site` | `enum{strict,lax,none}` | `.lax` | SameSite attribute |

**SessionStore interface:**

```zig
pub const SessionStore = struct {
    ptr: *anyopaque,
    getFn: *const fn (*anyopaque, []const u8) ?*SessionData,
    putFn: *const fn (*anyopaque, []const u8) anyerror!*SessionData,
    removeFn: *const fn (*anyopaque, []const u8) void,
};
```

**InMemoryStore** is the default in-memory implementation of `SessionStore`.

### Request Timeout -- `timeoutMw`

```zig
try app.addMiddleware(zigmund.timeoutMw(zigmund.TimeoutConfig{
    .timeout_ms = 30000,
    .message = "Request timeout",
}));
```

**TimeoutConfig:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `timeout_ms` | `u64` | `30000` | Maximum processing time in milliseconds |
| `message` | `[]const u8` | `"Request timeout"` | Response body on timeout |

### HTTPS Redirect -- `httpsRedirectMw`

```zig
try app.addMiddleware(zigmund.httpsRedirectMw(zigmund.HttpsRedirectConfig{}));
```

**HttpsRedirectConfig:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `redirect_status` | `std.http.Status` | `.temporary_redirect` | Redirect status code |
| `https_port` | `?u16` | `null` | Target HTTPS port (null uses 443) |

### Content Negotiation -- `contentNegotiationMw`

```zig
try app.addMiddleware(zigmund.contentNegotiationMw(zigmund.ContentNegotiationConfig{
    .default = .json,
    .supported = &.{ .json, .plain_text, .html },
}));
```

**ContentNegotiationConfig:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `default` | `ContentType` | `.json` | Default content type |
| `supported` | `[]const ContentType` | `&.{.json,.plain_text,.html}` | Supported content types |

**ContentType values:** `.json`, `.plain_text`, `.html`, `.xml`, `.any`

### Trusted Host -- `trustedHostMw`

```zig
try app.addMiddleware(zigmund.trustedHostMw(zigmund.TrustedHostConfig{
    .allowed_hosts = &.{ "api.example.com", ".example.com" },
}));
```

**TrustedHostConfig:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `allowed_hosts` | `[]const []const u8` | `&.{"*"}` | Allowed host values (supports wildcard subdomains with `.` prefix) |
| `allow_missing_host` | `bool` | `false` | Allow requests without a Host header |

## Example

```zig
var app = try zigmund.App.init(allocator, .{ .title = "API", .version = "1.0" });

try app.addMiddleware(zigmund.corsMw(.{ .allowed_origins = &.{"*"} }));
try app.addMiddleware(zigmund.rateLimitMw(.{ .max_requests = 200 }));
try app.addMiddleware(zigmund.compressionMw(.{}));
try app.addMiddleware(zigmund.timeoutMw(.{ .timeout_ms = 15000 }));
```
