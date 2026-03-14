const std = @import("std");
const builtin = @import("builtin");
const config = @import("config.zig");

const c = if (builtin.link_libc) @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
}) else struct {};

pub const InitError = error{
    TlsUnsupported,
    TlsContextInitFailed,
    TlsCertificateLoadFailed,
    TlsPrivateKeyLoadFailed,
    TlsPrivateKeyMismatch,
    TlsProtocolVersionRangeInvalid,
    TlsCipherListInvalid,
    TlsClientCaRequired,
    TlsClientCaLoadFailed,
    OutOfMemory,
};

pub const ConnectError = error{
    TlsUnsupported,
    TlsSessionInitFailed,
    TlsHandshakeFailed,
};

pub const IoError = error{
    EndOfStream,
    ReadFailed,
    WriteFailed,
};

pub const Context = if (builtin.link_libc) struct {
    raw: *c.SSL_CTX,

    pub fn init(tls_cfg: config.TlsConfig) InitError!Context {
        _ = tls_cfg.alpn;

        if (c.OPENSSL_init_ssl(0, null) != 1) return error.TlsContextInitFailed;

        const method = c.TLS_server_method();
        const ssl_ctx = c.SSL_CTX_new(method) orelse return error.TlsContextInitFailed;
        errdefer c.SSL_CTX_free(ssl_ctx);

        try configureProtocolVersions(ssl_ctx, tls_cfg);
        try configureCipherList(ssl_ctx, tls_cfg);
        try configureClientAuth(ssl_ctx, tls_cfg);

        const cert_z = try std.heap.c_allocator.dupeZ(u8, tls_cfg.cert_pem_path);
        defer std.heap.c_allocator.free(cert_z);
        const key_z = try std.heap.c_allocator.dupeZ(u8, tls_cfg.key_pem_path);
        defer std.heap.c_allocator.free(key_z);

        if (c.SSL_CTX_use_certificate_chain_file(ssl_ctx, cert_z.ptr) != 1 and
            c.SSL_CTX_use_certificate_file(ssl_ctx, cert_z.ptr, c.SSL_FILETYPE_PEM) != 1)
        {
            return error.TlsCertificateLoadFailed;
        }

        if (c.SSL_CTX_use_PrivateKey_file(ssl_ctx, key_z.ptr, c.SSL_FILETYPE_PEM) != 1) {
            return error.TlsPrivateKeyLoadFailed;
        }

        if (c.SSL_CTX_check_private_key(ssl_ctx) != 1) {
            return error.TlsPrivateKeyMismatch;
        }

        return .{ .raw = ssl_ctx };
    }

    pub fn deinit(self: *Context) void {
        c.SSL_CTX_free(self.raw);
        self.* = undefined;
    }
} else struct {
    pub fn init(_: config.TlsConfig) InitError!Context {
        return error.TlsUnsupported;
    }

    pub fn deinit(_: *Context) void {}
};

fn configureProtocolVersions(ssl_ctx: *c.SSL_CTX, tls_cfg: config.TlsConfig) InitError!void {
    const min_version = protocolVersionToOpenSsl(tls_cfg.min_version);
    const max_version = if (tls_cfg.max_version) |value| protocolVersionToOpenSsl(value) else 0;

    if (max_version != 0 and max_version < min_version) {
        return error.TlsProtocolVersionRangeInvalid;
    }

    if (c.SSL_CTX_set_min_proto_version(ssl_ctx, min_version) != 1) {
        return error.TlsContextInitFailed;
    }
    if (max_version != 0 and c.SSL_CTX_set_max_proto_version(ssl_ctx, max_version) != 1) {
        return error.TlsContextInitFailed;
    }
}

fn configureCipherList(ssl_ctx: *c.SSL_CTX, tls_cfg: config.TlsConfig) InitError!void {
    const cipher_list = tls_cfg.cipher_list orelse return;
    const cipher_list_z = try std.heap.c_allocator.dupeZ(u8, cipher_list);
    defer std.heap.c_allocator.free(cipher_list_z);

    if (c.SSL_CTX_set_cipher_list(ssl_ctx, cipher_list_z.ptr) != 1) {
        return error.TlsCipherListInvalid;
    }
}

fn configureClientAuth(ssl_ctx: *c.SSL_CTX, tls_cfg: config.TlsConfig) InitError!void {
    if (tls_cfg.client_auth == .none) {
        c.SSL_CTX_set_verify(ssl_ctx, c.SSL_VERIFY_NONE, null);
        return;
    }

    const client_ca_path = tls_cfg.client_ca_pem_path orelse return error.TlsClientCaRequired;
    const client_ca_path_z = try std.heap.c_allocator.dupeZ(u8, client_ca_path);
    defer std.heap.c_allocator.free(client_ca_path_z);

    if (c.SSL_CTX_load_verify_locations(ssl_ctx, client_ca_path_z.ptr, null) != 1) {
        return error.TlsClientCaLoadFailed;
    }

    const verify_mode: c_int = switch (tls_cfg.client_auth) {
        .none => c.SSL_VERIFY_NONE,
        .optional => c.SSL_VERIFY_PEER,
        .required => c.SSL_VERIFY_PEER | c.SSL_VERIFY_FAIL_IF_NO_PEER_CERT,
    };
    c.SSL_CTX_set_verify(ssl_ctx, verify_mode, null);
}

fn protocolVersionToOpenSsl(version: config.TlsProtocolVersion) c_int {
    return switch (version) {
        .tls_1_2 => c.TLS1_2_VERSION,
        .tls_1_3 => c.TLS1_3_VERSION,
    };
}

pub const Connection = if (builtin.link_libc) struct {
    ssl: *c.SSL,
    reader: std.Io.Reader,
    writer: std.Io.Writer,

    pub fn init(
        ctx: *const Context,
        fd: std.posix.fd_t,
        recv_buffer: []u8,
        send_buffer: []u8,
    ) ConnectError!Connection {
        const ssl = c.SSL_new(ctx.raw) orelse return error.TlsSessionInitFailed;
        errdefer c.SSL_free(ssl);

        if (c.SSL_set_fd(ssl, @intCast(fd)) != 1) return error.TlsSessionInitFailed;
        if (c.SSL_accept(ssl) != 1) return error.TlsHandshakeFailed;

        return .{
            .ssl = ssl,
            .reader = .{
                .vtable = &.{
                    .stream = stream,
                },
                .buffer = recv_buffer,
                .seek = 0,
                .end = 0,
            },
            .writer = .{
                .vtable = &.{
                    .drain = drain,
                },
                .buffer = send_buffer,
                .end = 0,
            },
        };
    }

    pub fn deinit(self: *Connection) void {
        _ = c.SSL_shutdown(self.ssl);
        c.SSL_free(self.ssl);
        self.* = undefined;
    }

    fn stream(
        io_reader: *std.Io.Reader,
        io_writer: *std.Io.Writer,
        limit: std.Io.Limit,
    ) std.Io.Reader.StreamError!usize {
        const self: *Connection = @alignCast(@fieldParentPtr("reader", io_reader));
        const read_buf = limit.slice(io_reader.buffer);
        if (read_buf.len == 0) return 0;

        const n = self.readSome(read_buf) catch |err| switch (err) {
            error.EndOfStream => return error.EndOfStream,
            else => return error.ReadFailed,
        };

        io_reader.seek = 0;
        io_reader.end = n;

        return io_reader.stream(io_writer, .limited(n));
    }

    fn drain(
        io_writer: *std.Io.Writer,
        data: []const []const u8,
        splat: usize,
    ) std.Io.Writer.Error!usize {
        const self: *Connection = @alignCast(@fieldParentPtr("writer", io_writer));
        const buffered = io_writer.buffered();
        var transferred: usize = 0;

        if (buffered.len != 0) {
            self.writeAll(buffered) catch return error.WriteFailed;
            transferred += buffered.len;
        }

        for (data[0 .. data.len - 1]) |chunk| {
            if (chunk.len == 0) continue;
            self.writeAll(chunk) catch return error.WriteFailed;
            transferred += chunk.len;
        }

        const pattern = data[data.len - 1];
        if (pattern.len != 0 and splat != 0) {
            var i: usize = 0;
            while (i < splat) : (i += 1) {
                self.writeAll(pattern) catch return error.WriteFailed;
                transferred += pattern.len;
            }
        }

        return io_writer.consume(transferred);
    }

    fn readSome(self: *Connection, dest: []u8) IoError!usize {
        while (true) {
            const max_chunk: usize = @min(dest.len, @as(usize, std.math.maxInt(c_int)));
            const rc = c.SSL_read(self.ssl, dest.ptr, @intCast(max_chunk));
            if (rc > 0) return @intCast(rc);

            const err_code = c.SSL_get_error(self.ssl, rc);
            switch (err_code) {
                c.SSL_ERROR_ZERO_RETURN => return error.EndOfStream,
                c.SSL_ERROR_WANT_READ, c.SSL_ERROR_WANT_WRITE => continue,
                else => return error.ReadFailed,
            }
        }
    }

    fn writeAll(self: *Connection, bytes: []const u8) IoError!void {
        var offset: usize = 0;
        while (offset < bytes.len) {
            const remaining = bytes[offset..];
            const chunk_len: usize = @min(remaining.len, @as(usize, std.math.maxInt(c_int)));
            const rc = c.SSL_write(self.ssl, remaining.ptr, @intCast(chunk_len));
            if (rc > 0) {
                offset += @intCast(rc);
                continue;
            }

            const err_code = c.SSL_get_error(self.ssl, rc);
            switch (err_code) {
                c.SSL_ERROR_WANT_READ, c.SSL_ERROR_WANT_WRITE => continue,
                c.SSL_ERROR_ZERO_RETURN => return error.EndOfStream,
                else => return error.WriteFailed,
            }
        }
    }
} else struct {
    pub fn init(_: *const Context, _: std.posix.fd_t, _: []u8, _: []u8) ConnectError!Connection {
        return error.TlsUnsupported;
    }

    pub fn deinit(_: *Connection) void {}
};
