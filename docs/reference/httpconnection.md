# HTTP Connection Reference

## Overview

HTTP connection details in Zigmund are accessible through the `Request` type. The request carries information about the underlying connection, including the peer address, raw HTTP server handle, and request metadata.

## Connection Information

### Peer Address

```zig
req.peer_address: ?std.net.Address
```

The remote client's network address. Available when the server provides peer information. This can be an IPv4 or IPv6 address.

### Raw Server Request

```zig
req.raw: ?*std.http.Server.Request
```

The underlying Zig standard library HTTP server request. This is `null` for synthetic/test requests created via `Request.initSynthetic`.

### Request Target

```zig
req.target: []const u8   // Full target including query string
req.path: []const u8     // Path component only
req.query: []const u8    // Query string only
```

### Method

```zig
req.method: std.http.Method
```

The HTTP method of the request (`.GET`, `.POST`, `.PUT`, `.PATCH`, `.DELETE`, `.OPTIONS`, `.HEAD`, `.TRACE`).

## Request Identity

### Request ID

```zig
req.request_id: ?[]const u8
```

A unique identifier assigned to each request. Generated automatically when `AppConfig.request_id_enabled` is `true` (the default). The header name is configurable via `AppConfig.request_id_header` (default: `"x-request-id"`).

### Correlation ID

```zig
req.correlation_id: ?[]const u8
```

Propagated from the incoming request header specified by `AppConfig.correlation_id_header` (default: `"x-correlation-id"`). Used for distributed tracing across services.

## ServerConfig

Configuration for the HTTP server, passed to `app.serve`:

```zig
pub const ServerConfig = struct {
    port: u16,
    host: []const u8 = "0.0.0.0",
    num_threads: ?usize = null,
    tls: ?TlsConfig = null,
};
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `port` | `u16` | (required) | Port to listen on |
| `host` | `[]const u8` | `"0.0.0.0"` | Bind address |
| `num_threads` | `?usize` | `null` | Worker thread count (null = auto) |
| `tls` | `?TlsConfig` | `null` | TLS configuration |

## TlsConfig

```zig
pub const TlsConfig = struct {
    cert_path: []const u8,
    key_path: []const u8,
    ca_path: ?[]const u8 = null,
    min_version: ?TlsProtocolVersion = null,
    client_auth: ?TlsClientAuth = null,
};
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cert_path` | `[]const u8` | (required) | Path to TLS certificate |
| `key_path` | `[]const u8` | (required) | Path to TLS private key |
| `ca_path` | `?[]const u8` | `null` | Path to CA certificate for client auth |
| `min_version` | `?TlsProtocolVersion` | `null` | Minimum TLS version |
| `client_auth` | `?TlsClientAuth` | `null` | Client certificate authentication mode |

## Example

```zig
fn handler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const client_ip = if (req.peer_address) |addr| blk: {
        var buf: [64]u8 = undefined;
        break :blk std.fmt.bufPrint(&buf, "{}", .{addr}) catch "unknown";
    } else "unknown";

    return zigmund.Response.json(allocator, .{
        .request_id = req.request_id orelse "none",
        .correlation_id = req.correlation_id orelse "none",
        .method = @tagName(req.method),
        .path = req.path,
        .client_ip = client_ip,
    });
}
```
