# Production Settings

This guide covers the server configuration options available in Zigmund for production deployments, including network settings, timeouts, TLS, and security middleware.

---

## ServerConfig Reference

The `ServerConfig` struct controls the low-level behavior of the HTTP server. All fields have sensible defaults; override only what your deployment requires.

| Field | Type | Default | Description |
|---|---|---|---|
| `host` | `[]const u8` | `"127.0.0.1"` | Bind address. Use `"0.0.0.0"` to listen on all interfaces. |
| `port` | `u16` | `8000` | TCP port number. |
| `worker_count` | `usize` | `0` | Number of worker threads. `0` means auto-detect based on available CPU cores. |
| `recv_buffer_size` | `usize` | `16384` (16 KB) | Per-connection receive buffer size. |
| `send_buffer_size` | `usize` | `16384` (16 KB) | Per-connection send buffer size. |
| `max_header_bytes` | `usize` | `65536` (64 KB) | Maximum allowed request header size. Requests exceeding this receive a `431 Request Header Fields Too Large` response. Set to `0` to disable. |
| `max_query_bytes` | `usize` | `16384` (16 KB) | Maximum query string size. |
| `max_body_bytes` | `usize` | `8388608` (8 MB) | Maximum request body size. |
| `max_connections` | `usize` | `0` | Maximum concurrent connections. `0` means unlimited. When exceeded, the server responds with `503 Service Unavailable`. |
| `overload_retry_after_seconds` | `u32` | `1` | Value of the `Retry-After` header sent with 503 responses. Set to `0` to omit the header. |
| `accept_poll_interval_ms` | `i32` | `250` | Polling interval for the accept loop, in milliseconds. Controls how frequently workers check for shutdown signals between connections. |
| `header_timeout_ms` | `i32` | `10000` (10 s) | Time allowed for the client to send request headers on a new connection. Set to `-1` to disable. |
| `body_timeout_ms` | `i32` | `10000` (10 s) | Socket receive timeout applied while reading the request body. Set to `-1` to disable. |
| `write_timeout_ms` | `i32` | `10000` (10 s) | Socket send timeout applied while writing the response. Set to `-1` to disable. |
| `idle_timeout_ms` | `i32` | `30000` (30 s) | Keep-alive idle timeout. Connections idle longer than this are closed. Set to `-1` to disable. |
| `shutdown_grace_period_ms` | `u64` | `30000` (30 s) | Time to wait for active requests to complete during graceful shutdown. After this period, remaining connections are forcibly closed. |
| `reuse_address` | `bool` | `true` | Enable `SO_REUSEADDR` on the listening socket. |
| `trusted_proxy_headers` | `bool` | `true` | Whether to trust proxy-related headers. |
| `trusted_proxy_forwarded_header` | `bool` | `true` | Trust the standard `Forwarded` header. |
| `trusted_proxy_x_forwarded_headers` | `bool` | `true` | Trust `X-Forwarded-For`, `X-Forwarded-Proto`, and related headers. |
| `trusted_proxy_cidrs` | `[]const []const u8` | `&.{}` | CIDR ranges of trusted proxies. Empty means all proxies are trusted when `trusted_proxy_headers` is enabled. |
| `tls` | `?TlsConfig` | `null` | TLS configuration. Set to enable HTTPS directly in Zigmund. |

---

## Production Example

A typical production configuration:

```zig
try app.serve(.{
    .host = "0.0.0.0",
    .port = 8080,
    .worker_count = 4,
    .max_connections = 10000,
    .max_header_bytes = 32 * 1024,
    .max_body_bytes = 4 * 1024 * 1024,
    .header_timeout_ms = 5_000,
    .body_timeout_ms = 15_000,
    .write_timeout_ms = 15_000,
    .idle_timeout_ms = 60_000,
    .shutdown_grace_period_ms = 30_000,
    .recv_buffer_size = 32 * 1024,
    .send_buffer_size = 64 * 1024,
    .overload_retry_after_seconds = 5,
});
```

### Worker Count

When `worker_count` is set to `0` (the default), Zigmund calls `std.Thread.getCpuCount()` to detect the number of available CPU cores and spawns that many workers. In containerized environments, set this explicitly to match your CPU limit:

```zig
.worker_count = 4,
```

A single-threaded mode is used when the resolved worker count is 1.

### Connection Limits

The `max_connections` field limits concurrent connections across all workers. When the limit is reached, new connections receive a `503 Service Unavailable` response with a `Retry-After` header. This protects the server from resource exhaustion under load spikes.

### Buffer Sizes

The `recv_buffer_size` and `send_buffer_size` fields control per-connection I/O buffers allocated on the hot path. Larger buffers reduce system calls for large payloads but increase per-connection memory usage:

- **API workloads** (small JSON payloads): 16 KB is sufficient.
- **File uploads or large responses**: increase to 64 KB or 128 KB.
- **Memory-constrained environments**: reduce to 8 KB.

---

## TLS Configuration

Zigmund supports native TLS via OpenSSL. Configure TLS by providing a `TlsConfig` to the `tls` field of `ServerConfig`.

### TlsConfig Reference

| Field | Type | Default | Description |
|---|---|---|---|
| `cert_pem_path` | `[]const u8` | (required) | Path to the PEM-encoded certificate file. Supports certificate chains. |
| `key_pem_path` | `[]const u8` | (required) | Path to the PEM-encoded private key file. |
| `alpn` | `[]const []const u8` | `&.{"http/1.1"}` | ALPN protocol list for protocol negotiation. |
| `min_version` | `TlsProtocolVersion` | `.tls_1_2` | Minimum accepted TLS version. Options: `.tls_1_2`, `.tls_1_3`. |
| `max_version` | `?TlsProtocolVersion` | `null` | Maximum accepted TLS version. `null` means no upper bound (use the highest supported). |
| `cipher_list` | `?[]const u8` | `null` | OpenSSL cipher list string. `null` uses the OpenSSL defaults. |
| `client_auth` | `TlsClientAuth` | `.none` | Client certificate authentication mode. Options: `.none`, `.optional`, `.required`. |
| `client_ca_pem_path` | `?[]const u8` | `null` | Path to the CA certificate for verifying client certificates. Required when `client_auth` is `.optional` or `.required`. |

### TLS Example

```zig
try app.serve(.{
    .host = "0.0.0.0",
    .port = 443,
    .worker_count = 4,
    .tls = .{
        .cert_pem_path = "/etc/ssl/certs/server.pem",
        .key_pem_path = "/etc/ssl/private/server-key.pem",
        .min_version = .tls_1_2,
        .client_auth = .none,
    },
});
```

### Mutual TLS (mTLS)

For services that require client certificate verification:

```zig
.tls = .{
    .cert_pem_path = "/etc/ssl/certs/server.pem",
    .key_pem_path = "/etc/ssl/private/server-key.pem",
    .min_version = .tls_1_3,
    .client_auth = .required,
    .client_ca_pem_path = "/etc/ssl/certs/client-ca.pem",
},
```

### TLS Protocol Versions

- `.tls_1_2` -- TLS 1.2. Widely supported; recommended as the minimum version.
- `.tls_1_3` -- TLS 1.3. Improved security and performance. Use as minimum when all clients support it.

Setting `min_version` to `.tls_1_3` with `max_version` set to `null` enforces TLS 1.3 only. The server returns `TlsProtocolVersionRangeInvalid` if `max_version` is set to a version lower than `min_version`.

---

## Graceful Shutdown

Zigmund supports graceful shutdown through a callback mechanism. When a shutdown signal is received:

1. The server stops accepting new connections.
2. New connections that arrive during shutdown receive a `503 Service Unavailable` response with the message "server shutting down".
3. Active requests are allowed to complete.
4. After `shutdown_grace_period_ms` elapses, remaining connections are forcibly terminated.

The `shutdown_grace_period_ms` setting controls how long the server waits for in-flight requests. Set this to a value that covers your longest expected request:

```zig
.shutdown_grace_period_ms = 30_000, // 30 seconds
```

Set to `0` to shut down immediately without waiting for active connections.

---

## Logging Configuration

Zigmund provides structured logging through the `AppConfig` settings:

```zig
const app = try Zigmund.init(allocator, .{
    .title = "My API",
    .version = "1.0.0",
    .structured_access_logs = true,
    .structured_telemetry_logs = true,
    .structured_trace_logs = true,
    .structured_metrics_logs = true,
    .structured_audit_logs = true,
    .structured_log_redaction_text = "[redacted]",
    .structured_log_redact_remote_addr = true,
    .structured_log_redact_user_agent = true,
});
```

| Field | Default | Description |
|---|---|---|
| `structured_access_logs` | `false` | Emit structured JSON access logs for each request. |
| `structured_telemetry_logs` | `false` | Emit structured telemetry data. |
| `structured_trace_logs` | `false` | Emit distributed tracing data. |
| `structured_metrics_logs` | `false` | Emit metrics data in structured format. |
| `structured_audit_logs` | `false` | Emit audit trail logs. |
| `structured_log_redaction_text` | `"[redacted]"` | Replacement text for redacted fields. |
| `structured_log_redact_tracestate` | `true` | Redact the `tracestate` header in logs. |
| `structured_log_redact_baggage` | `true` | Redact the `baggage` header in logs. |
| `structured_log_redact_remote_addr` | `true` | Redact the client IP address in logs. |
| `structured_log_redact_user_agent` | `true` | Redact the `User-Agent` header in logs. |

---

## Rate Limiting

The built-in rate limiting middleware protects your API from abuse. It uses a sliding window counter keyed by client IP:

```zig
const rate_limit = @import("zigmund").middleware.rate_limit;
app.addMiddleware(rate_limit, .{
    .max_requests = 100,
    .window_seconds = 60,
});
```

| Field | Type | Default | Description |
|---|---|---|---|
| `max_requests` | `u32` | `100` | Maximum requests allowed per window. |
| `window_seconds` | `u32` | `60` | Duration of the rate limit window in seconds. |
| `key_func` | `?*const fn (*Request) []const u8` | `null` | Custom function to extract the rate limit key. Defaults to client IP via `X-Forwarded-For` or remote address. |

---

## HTTPS Redirect Middleware

Redirect all HTTP traffic to HTTPS. Use this when TLS is terminated at the application level or when you want to enforce HTTPS even behind a proxy that sets `X-Forwarded-Proto`:

```zig
const https_redirect = @import("zigmund").middleware.https_redirect;
app.addMiddleware(https_redirect, .{
    .redirect_status = .temporary_redirect, // 307
    .https_port = null,                     // default 443
});
```

| Field | Type | Default | Description |
|---|---|---|---|
| `redirect_status` | `std.http.Status` | `.temporary_redirect` (307) | HTTP status code for the redirect response. Use `.moved_permanently` (301) for permanent redirects. |
| `https_port` | `?u16` | `null` | Target port for the HTTPS redirect. `null` omits the port (uses default 443). |

---

## Trusted Host Middleware

Prevent host header attacks by validating the `Host` header against a whitelist:

```zig
const trusted_host = @import("zigmund").middleware.trusted_host;
app.addMiddleware(trusted_host, .{
    .allowed_hosts = &.{ "api.example.com", ".example.com" },
    .allow_missing_host = false,
});
```

| Field | Type | Default | Description |
|---|---|---|---|
| `allowed_hosts` | `[]const []const u8` | `&.{"*"}` | List of allowed host values. Use `"*"` to allow any host. Entries starting with `"."` match any subdomain (e.g., `".example.com"` matches `"api.example.com"`). |
| `allow_missing_host` | `bool` | `false` | Whether to allow requests without a `Host` header. |

---

## Compression Middleware

Compress responses automatically using gzip when the client supports it:

```zig
const compression = @import("zigmund").middleware.compression;
compression.configure(.{
    .min_size = 1024,
    .level = 6,
    .compressible_types = &.{
        "text/",
        "application/json",
        "application/xml",
        "application/javascript",
        "application/xhtml+xml",
        "image/svg+xml",
    },
});
```

| Field | Type | Default | Description |
|---|---|---|---|
| `min_size` | `usize` | `1024` | Minimum response body size in bytes to trigger compression. Responses smaller than this are sent uncompressed. |
| `level` | `u4` | `6` | Compression level (1-9). Lower values are faster; higher values produce smaller output. |
| `compressible_types` | `[]const []const u8` | (see above) | Content type prefixes eligible for compression. A response is compressed if its `Content-Type` starts with any of these strings. |

---

## Full Production Configuration Example

Combining server settings with security middleware:

```zig
const std = @import("std");
const Zigmund = @import("zigmund");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try Zigmund.init(allocator, .{
        .title = "Production API",
        .version = "1.0.0",
        .structured_access_logs = true,
        .structured_audit_logs = true,
        .request_id_enabled = true,
    });

    // Security middleware
    const trusted_host = @import("zigmund").middleware.trusted_host;
    app.addMiddleware(trusted_host, .{
        .allowed_hosts = &.{ "api.example.com" },
    });

    const rate_limit = @import("zigmund").middleware.rate_limit;
    app.addMiddleware(rate_limit, .{
        .max_requests = 200,
        .window_seconds = 60,
    });

    const compression = @import("zigmund").middleware.compression;
    compression.configure(.{
        .min_size = 512,
        .level = 4,
    });

    // Register routes...

    try app.serve(.{
        .host = "0.0.0.0",
        .port = 8080,
        .worker_count = 4,
        .max_connections = 10000,
        .max_header_bytes = 32 * 1024,
        .max_body_bytes = 4 * 1024 * 1024,
        .header_timeout_ms = 5_000,
        .body_timeout_ms = 15_000,
        .write_timeout_ms = 15_000,
        .idle_timeout_ms = 60_000,
        .shutdown_grace_period_ms = 30_000,
        .tls = .{
            .cert_pem_path = "/etc/ssl/certs/server.pem",
            .key_pem_path = "/etc/ssl/private/server-key.pem",
            .min_version = .tls_1_2,
        },
    });
}
```
