# Response Reference

## Overview

`Response` represents an outgoing HTTP response. It carries a status code, content type, body, and headers. Multiple factory methods create responses for common content types.

## Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `status` | `std.http.Status` | `.ok` | HTTP status code |
| `body` | `[]const u8` | `""` | Response body bytes |
| `content_type` | `[]const u8` | `"text/plain; charset=utf-8"` | Content-Type header value |
| `headers` | `std.ArrayListUnmanaged(std.http.Header)` | empty | Additional response headers |

## Factory Methods

### `Response.text`

```zig
pub fn text(body: []const u8) Response
```

Creates a plain text response with status 200.

### `Response.html`

```zig
pub fn html(body: []const u8) Response
```

Creates an HTML response with status 200.

### `Response.json`

```zig
pub fn json(allocator: std.mem.Allocator, value: anytype) !Response
```

Serializes any Zig value to JSON and returns it with `Content-Type: application/json`. The serialized body is owned by the response and freed on `deinit`.

### `Response.redirect`

```zig
pub fn redirect(allocator: std.mem.Allocator, location: []const u8, status: std.http.Status) !Response
```

Creates a redirect response with the given location and status code.

### `Response.fileFromPath`

```zig
pub fn fileFromPath(allocator: std.mem.Allocator, path: []const u8) !Response
```

Reads a file from disk and returns it as a response. The content type is guessed from the file extension.

### `Response.fileFromPathWithContentType`

```zig
pub fn fileFromPathWithContentType(
    allocator: std.mem.Allocator,
    path: []const u8,
    content_type: ?[]const u8,
) !Response
```

Reads a file with an explicit content type override.

### `Response.jsonLines`

```zig
pub fn jsonLines(allocator: std.mem.Allocator, items: anytype) !Response
```

Serializes a slice of items as newline-delimited JSON (NDJSON). Content-Type: `application/x-ndjson`.

### `Response.jsonLinesRaw`

```zig
pub fn jsonLinesRaw(allocator: std.mem.Allocator, lines: []const []const u8) !Response
```

Creates an NDJSON response from pre-formatted JSON lines.

### `Response.streamChunks`

```zig
pub fn streamChunks(
    allocator: std.mem.Allocator,
    chunks: []const []const u8,
    content_type: []const u8,
) !Response
```

Concatenates chunks into a single response body with the given content type.

### `Response.eventStream`

```zig
pub fn eventStream(
    allocator: std.mem.Allocator,
    events: []const ServerSentEvent,
) !Response
```

Creates a Server-Sent Events response. Automatically sets `Content-Type: text/event-stream`, `Cache-Control: no-cache`, and `Connection: keep-alive`.

### `Response.notModified`

```zig
pub fn notModified() Response
```

Returns a 304 Not Modified response.

## Modifier Methods

### `withStatus`

```zig
pub fn withStatus(self: Response, status: std.http.Status) Response
```

Returns a copy of the response with the given status code. Designed for chaining:

```zig
return (try Response.json(allocator, data)).withStatus(.created);
```

**Note:** Ownership transfers to the returned copy. Do not call `deinit` on the original after calling `withStatus`.

### `setHeader`

```zig
pub fn setHeader(self: *Response, allocator: std.mem.Allocator, name: []const u8, value: []const u8) !void
```

Adds a response header. Both name and value are duplicated and owned by the response.

### `setCookie`

```zig
pub fn setCookie(
    self: *Response,
    allocator: std.mem.Allocator,
    name: []const u8,
    value: []const u8,
    opts: CookieOptions,
) !void
```

Sets a `Set-Cookie` header with the given options.

### `deleteCookie`

```zig
pub fn deleteCookie(
    self: *Response,
    allocator: std.mem.Allocator,
    name: []const u8,
    opts: CookieOptions,
) !void
```

Deletes a cookie by setting Max-Age=0 and Expires to epoch.

### `setEtag`

```zig
pub fn setEtag(self: *Response, allocator: std.mem.Allocator, etag: []const u8) !void
```

Sets the `ETag` header.

### `setLastModified`

```zig
pub fn setLastModified(self: *Response, allocator: std.mem.Allocator, value: []const u8) !void
```

Sets the `Last-Modified` header.

### `header`

```zig
pub fn header(self: *const Response, name: []const u8) ?[]const u8
```

Returns the value of a response header by name.

### `deinit`

```zig
pub fn deinit(self: *Response, allocator: std.mem.Allocator) void
```

Frees the owned body and all owned headers.

## CookieOptions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `path` | `?[]const u8` | `"/"` | Cookie path |
| `domain` | `?[]const u8` | `null` | Cookie domain |
| `max_age_seconds` | `?i64` | `null` | Max-Age in seconds |
| `expires` | `?[]const u8` | `null` | Expires date string |
| `secure` | `bool` | `false` | Secure flag |
| `http_only` | `bool` | `true` | HttpOnly flag |
| `same_site` | `?CookieSameSite` | `null` | SameSite attribute (.lax, .strict, .none) |

## ServerSentEvent

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `data` | `[]const u8` | (required) | Event data |
| `id` | `?[]const u8` | `null` | Event ID |
| `event` | `?[]const u8` | `null` | Event type |
| `retry_ms` | `?u32` | `null` | Retry interval in milliseconds |

## Conditional Responses

### `Response.conditionalNotModified`

```zig
pub fn conditionalNotModified(
    allocator: std.mem.Allocator,
    etag: ?[]const u8,
    last_modified: ?[]const u8,
    if_none_match: ?[]const u8,
    if_modified_since: ?[]const u8,
) !?Response
```

Checks ETag/Last-Modified against request cache validators and returns a 304 response if the content has not changed. Returns `null` if the content is modified and a full response should be sent.

## Example

```zig
fn handler(allocator: std.mem.Allocator) !zigmund.Response {
    var response = try zigmund.Response.json(allocator, .{
        .message = "created",
    });
    try response.setHeader(allocator, "x-custom", "value");
    try response.setCookie(allocator, "session", "abc123", .{
        .secure = true,
        .same_site = .strict,
    });
    return response.withStatus(.created);
}
```
