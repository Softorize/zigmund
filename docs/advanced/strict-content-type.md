# Strict Content Type

Enforce strict `Content-Type` header validation on incoming requests. When enabled, Zigmund rejects requests that do not include the expected `Content-Type` header for body deserialization.

## Overview

By default, Zigmund is lenient about the `Content-Type` header -- it attempts to parse the request body regardless of the header value. With strict validation enabled, Zigmund requires the `Content-Type` header to match `application/json` for JSON body deserialization, returning a 415 Unsupported Media Type error otherwise.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const StrictPayload = struct {
    name: []const u8,
    value: u32,
};

fn strictEndpoint(
    body: zigmund.Body(StrictPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .received_name = body.value.?.name,
        .received_value = body.value.?.value,
        .strict_validation = true,
    });
}

fn nonStrictEndpoint(
    body: zigmund.Body(StrictPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .received_name = body.value.?.name,
        .received_value = body.value.?.value,
        .strict_validation = false,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/strict", strictEndpoint, .{
        .summary = "Accept request only with strict content-type validation",
        .strict_validation = true,
    });
    try app.post("/lenient", nonStrictEndpoint, .{
        .summary = "Accept request with lenient content-type validation",
        .strict_validation = false,
    });
}
```

## How It Works

### 1. Enabling Strict Validation

Set `.strict_validation = true` in the route options:

```zig
try app.post("/strict", strictEndpoint, .{
    .strict_validation = true,
});
```

With strict validation enabled:
- Requests with `Content-Type: application/json` are accepted and parsed normally.
- Requests without a `Content-Type` header or with a non-JSON content type receive a **415 Unsupported Media Type** error.

### 2. Lenient Mode (Default)

With `.strict_validation = false` (or omitted, as it is the default):

```zig
try app.post("/lenient", nonStrictEndpoint, .{
    .strict_validation = false,
});
```

Zigmund attempts to parse the request body as JSON regardless of the `Content-Type` header. This is more forgiving for clients that may not set headers correctly.

### 3. When to Use Strict Validation

Use strict validation when:
- You want to enforce API contracts precisely.
- Security requirements demand explicit content type verification.
- You are building a public API that should reject malformed requests early.
- You want to prevent content type confusion attacks.

Use lenient validation when:
- You are building internal APIs where client behavior is controlled.
- You need backward compatibility with clients that omit `Content-Type`.
- You are in early development and want fewer friction points.

### 4. Error Response

When strict validation rejects a request, the response is:

```
HTTP/1.1 415 Unsupported Media Type
Content-Type: application/json

{"detail": "Unsupported Media Type"}
```

## Key Points

- Set `.strict_validation = true` in route options to enforce `Content-Type` header matching.
- Strict validation returns 415 Unsupported Media Type for requests without the correct `Content-Type`.
- The default behavior is lenient -- `Content-Type` is not enforced.
- Strict validation is a per-route setting, so you can mix strict and lenient endpoints.
- Both strict and lenient endpoints use the same `Body()` parameter for deserialization.
- Strict validation adds a layer of defense against content type confusion and malformed requests.

## See Also

- [Dataclasses](dataclasses.md) -- define struct types used with `Body()` deserialization.
- [Response Directly](response-directly.md) -- return custom error responses.
- [Middleware](middleware.md) -- apply content type validation globally via middleware.
