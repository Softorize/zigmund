# Status Codes Reference

## Overview

Zigmund uses `std.http.Status` from the Zig standard library for HTTP status codes. The type is re-exported as `zigmund.status` for convenience.

## Commonly Used Status Codes

### Informational (1xx)

| Value | Name | Description |
|-------|------|-------------|
| `.@"continue"` | 100 Continue | Request received, continue sending body |
| `.switching_protocols` | 101 Switching Protocols | Switching to WebSocket or other protocol |

### Success (2xx)

| Value | Name | Description |
|-------|------|-------------|
| `.ok` | 200 OK | Standard success response |
| `.created` | 201 Created | Resource successfully created |
| `.accepted` | 202 Accepted | Request accepted for processing |
| `.no_content` | 204 No Content | Success with no response body |

### Redirection (3xx)

| Value | Name | Description |
|-------|------|-------------|
| `.moved_permanently` | 301 Moved Permanently | Resource permanently moved |
| `.found` | 302 Found | Temporary redirect |
| `.see_other` | 303 See Other | Redirect with GET method |
| `.not_modified` | 304 Not Modified | Cached version is still valid |
| `.temporary_redirect` | 307 Temporary Redirect | Temporary redirect preserving method |
| `.permanent_redirect` | 308 Permanent Redirect | Permanent redirect preserving method |

### Client Error (4xx)

| Value | Name | Description |
|-------|------|-------------|
| `.bad_request` | 400 Bad Request | Malformed request |
| `.unauthorized` | 401 Unauthorized | Authentication required |
| `.forbidden` | 403 Forbidden | Insufficient permissions |
| `.not_found` | 404 Not Found | Resource not found |
| `.method_not_allowed` | 405 Method Not Allowed | HTTP method not supported |
| `.conflict` | 409 Conflict | Resource conflict |
| `.gone` | 410 Gone | Resource permanently removed |
| `.unprocessable_content` | 422 Unprocessable Content | Validation error |
| `.too_many_requests` | 429 Too Many Requests | Rate limit exceeded |

### Server Error (5xx)

| Value | Name | Description |
|-------|------|-------------|
| `.internal_server_error` | 500 Internal Server Error | Unexpected server error |
| `.not_implemented` | 501 Not Implemented | Feature not implemented |
| `.bad_gateway` | 502 Bad Gateway | Invalid upstream response |
| `.service_unavailable` | 503 Service Unavailable | Server temporarily unavailable |
| `.gateway_timeout` | 504 Gateway Timeout | Upstream timeout |

## Usage

Status codes are used with `Response.withStatus` and in `RouteOptions.status_code`:

```zig
// Set status on a response
return (try zigmund.Response.json(allocator, data)).withStatus(.created);

// Set default status for a route
try app.post("/items", handler, .{
    .status_code = .created,
});

// Use in redirects
return try zigmund.Response.redirect(allocator, "/new-location", .moved_permanently);
```

## Custom Status Codes

For status codes not in the enum, use `@enumFromInt`:

```zig
const custom_status: std.http.Status = @enumFromInt(418);
return zigmund.Response.text("I'm a teapot").withStatus(custom_status);
```
