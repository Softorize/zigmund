const std = @import("std");

pub const TlsProtocolVersion = enum {
    tls_1_2,
    tls_1_3,
};

pub const TlsClientAuth = enum {
    none,
    optional,
    required,
};

pub const TlsConfig = struct {
    cert_pem_path: []const u8,
    key_pem_path: []const u8,
    alpn: []const []const u8 = &.{"http/1.1"},
    min_version: TlsProtocolVersion = .tls_1_2,
    max_version: ?TlsProtocolVersion = null,
    cipher_list: ?[]const u8 = null,
    client_auth: TlsClientAuth = .none,
    client_ca_pem_path: ?[]const u8 = null,
};

pub const ServerConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8000,
    worker_count: usize = 0,
    recv_buffer_size: usize = 16 * 1024,
    send_buffer_size: usize = 16 * 1024,
    max_header_bytes: usize = 64 * 1024,
    max_query_bytes: usize = 16 * 1024,
    max_body_bytes: usize = 8 * 1024 * 1024,
    max_connections: usize = 0,
    overload_retry_after_seconds: u32 = 1,
    accept_poll_interval_ms: i32 = 250,
    header_timeout_ms: i32 = 10_000,
    body_timeout_ms: i32 = 10_000,
    write_timeout_ms: i32 = 10_000,
    idle_timeout_ms: i32 = 30_000,
    shutdown_grace_period_ms: u64 = 30_000,
    reuse_address: bool = true,
    trusted_proxy_headers: bool = true,
    trusted_proxy_forwarded_header: bool = true,
    trusted_proxy_x_forwarded_headers: bool = true,
    trusted_proxy_cidrs: []const []const u8 = &.{},
    tls: ?TlsConfig = null,

    pub fn resolvedWorkerCount(self: ServerConfig) usize {
        if (self.worker_count != 0) return self.worker_count;
        return std.Thread.getCpuCount() catch 1;
    }
};
