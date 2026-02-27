const std = @import("std");

pub const TlsConfig = struct {
    cert_pem_path: []const u8,
    key_pem_path: []const u8,
    alpn: []const []const u8 = &.{"http/1.1"},
};

pub const ServerConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8000,
    worker_count: usize = 0,
    recv_buffer_size: usize = 16 * 1024,
    send_buffer_size: usize = 16 * 1024,
    max_header_bytes: usize = 64 * 1024,
    max_body_bytes: usize = 8 * 1024 * 1024,
    max_connections: usize = 0,
    accept_poll_interval_ms: i32 = 250,
    idle_timeout_ms: i32 = 30_000,
    shutdown_grace_period_ms: u64 = 30_000,
    reuse_address: bool = true,
    trusted_proxy_headers: bool = true,
    trusted_proxy_cidrs: []const []const u8 = &.{},
    tls: ?TlsConfig = null,

    pub fn resolvedWorkerCount(self: ServerConfig) usize {
        if (self.worker_count != 0) return self.worker_count;
        return std.Thread.getCpuCount() catch 1;
    }
};
