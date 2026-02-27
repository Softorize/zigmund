const std = @import("std");
const zigmund = @import("zigmund");

const ServeThreadCtx = struct {
    app: *zigmund.App,
    cfg: zigmund.ServerConfig,
    serve_error: ?anyerror = null,
};

const AuditCapture = struct {
    mutex: std.Thread.Mutex = .{},
    startup_config_seen: bool = false,
    startup_begin_seen: bool = false,
    startup_complete_seen: bool = false,
    shutdown_begin_seen: bool = false,
    shutdown_complete_seen: bool = false,
    startup_config_detail: ?[]u8 = null,

    fn deinit(self: *AuditCapture, allocator: std.mem.Allocator) void {
        if (self.startup_config_detail) |detail| allocator.free(detail);
        self.startup_config_detail = null;
    }
};

var active_audit_capture: ?*AuditCapture = null;

fn auditSink(event: zigmund.App.AuditEvent, allocator: std.mem.Allocator) !void {
    const capture = active_audit_capture orelse return;

    capture.mutex.lock();
    defer capture.mutex.unlock();

    if (std.mem.eql(u8, event.action, "startup_config")) {
        capture.startup_config_seen = true;
        if (capture.startup_config_detail) |detail| allocator.free(detail);
        capture.startup_config_detail = try allocator.dupe(u8, event.detail);
        return;
    }

    if (std.mem.eql(u8, event.action, "startup_begin")) {
        capture.startup_begin_seen = true;
    } else if (std.mem.eql(u8, event.action, "startup_complete")) {
        capture.startup_complete_seen = true;
    } else if (std.mem.eql(u8, event.action, "shutdown_begin")) {
        capture.shutdown_begin_seen = true;
    } else if (std.mem.eql(u8, event.action, "shutdown_complete")) {
        capture.shutdown_complete_seen = true;
    }
}

fn serveThread(ctx: *ServeThreadCtx) void {
    ctx.app.serve(ctx.cfg) catch |err| {
        ctx.serve_error = err;
    };
}

fn reservePort() !u16 {
    const address = try std.net.Address.resolveIp("127.0.0.1", 0);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();
    return listener.listen_address.getPort();
}

fn connectWithRetry(address: std.net.Address) !std.net.Stream {
    var attempt: usize = 0;
    while (attempt < 20) : (attempt += 1) {
        const stream = std.net.tcpConnectToAddress(address) catch |err| {
            if (attempt + 1 >= 20) return err;
            std.Thread.sleep(50 * std.time.ns_per_ms);
            continue;
        };
        return stream;
    }
    return error.ConnectionFailed;
}

fn waitReadable(fd: std.posix.fd_t, timeout_ms: i32) !bool {
    var pfd = [1]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.IN,
        .revents = undefined,
    }};

    const n = try std.posix.poll(&pfd, timeout_ms);
    if (n == 0) return false;
    return (pfd[0].revents & std.posix.POLL.IN) != 0;
}

fn statusCodeFromResponse(response: []const u8) ?u16 {
    const line_end = std.mem.indexOf(u8, response, "\r\n") orelse return null;
    const line = response[0..line_end];

    var parts = std.mem.tokenizeScalar(u8, line, ' ');
    _ = parts.next() orelse return null;
    const code_text = parts.next() orelse return null;
    return std.fmt.parseInt(u16, code_text, 10) catch null;
}

fn guardrailOkHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

test "server enforces max_body_bytes with 413 response" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "runtime-limits",
        .version = "0.0.1",
    });
    defer app.deinit();

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .idle_timeout_ms = 500,
        .shutdown_grace_period_ms = 200,
        .max_body_bytes = 16,
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer {
        app.requestShutdown();
        thread.join();
    }

    const address = try std.net.Address.resolveIp("127.0.0.1", port);
    var stream = try connectWithRetry(address);
    defer stream.close();

    const body = "abcdefghijklmnopqrstuvwxyz";
    const request = try std.fmt.allocPrint(
        std.testing.allocator,
        "POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: {d}\r\n\r\n{s}",
        .{ body.len, body },
    );
    defer std.testing.allocator.free(request);

    try stream.writeAll(request);

    const readable = try waitReadable(stream.handle, 2_000);
    try std.testing.expect(readable);

    var read_buf: [4096]u8 = undefined;
    const n = try stream.read(&read_buf);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.indexOf(u8, read_buf[0..n], "413") != null);
}

test "server enforces max_header_bytes with 431 response" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "runtime-header-limits",
        .version = "0.0.1",
    });
    defer app.deinit();

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .idle_timeout_ms = 500,
        .shutdown_grace_period_ms = 200,
        .max_header_bytes = 96,
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer {
        app.requestShutdown();
        thread.join();
    }

    const address = try std.net.Address.resolveIp("127.0.0.1", port);
    var stream = try connectWithRetry(address);
    defer stream.close();

    const large_header = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    const request = try std.fmt.allocPrint(
        std.testing.allocator,
        "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Large: {s}\r\n\r\n",
        .{large_header},
    );
    defer std.testing.allocator.free(request);

    try stream.writeAll(request);

    const readable = try waitReadable(stream.handle, 2_000);
    try std.testing.expect(readable);

    var read_buf: [4096]u8 = undefined;
    const n = try stream.read(&read_buf);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.indexOf(u8, read_buf[0..n], "431") != null);
}

test "server enforces max_query_bytes with 414 response" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "runtime-query-limits",
        .version = "0.0.1",
    });
    defer app.deinit();

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .idle_timeout_ms = 500,
        .shutdown_grace_period_ms = 200,
        .max_query_bytes = 8,
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer {
        app.requestShutdown();
        thread.join();
    }

    const address = try std.net.Address.resolveIp("127.0.0.1", port);
    var stream = try connectWithRetry(address);
    defer stream.close();

    const request =
        "GET /search?term=abcdefghijk HTTP/1.1\r\n" ++
        "Host: 127.0.0.1\r\n" ++
        "\r\n";
    try stream.writeAll(request);

    const readable = try waitReadable(stream.handle, 2_000);
    try std.testing.expect(readable);

    var read_buf: [4096]u8 = undefined;
    const n = try stream.read(&read_buf);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.indexOf(u8, read_buf[0..n], "414") != null);
}

test "route guardrails can override global body and query limits" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "runtime-route-guardrails",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/strict", guardrailOkHandler, .{});
    try app.post("/relaxed", guardrailOkHandler, .{
        .max_query_bytes = 64,
        .max_body_bytes = 64,
    });

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .idle_timeout_ms = 500,
        .shutdown_grace_period_ms = 200,
        .max_query_bytes = 8,
        .max_body_bytes = 8,
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer {
        app.requestShutdown();
        thread.join();
    }

    const address = try std.net.Address.resolveIp("127.0.0.1", port);
    const long_query = "term=abcdefghijklmnopqrstuvwxyz";
    const medium_body = "abcdefghijklmnopqrstuvwxyz";

    // Strict route should use global query limit (8 bytes) and fail.
    {
        var stream = try connectWithRetry(address);
        defer stream.close();

        const request = try std.fmt.allocPrint(
            std.testing.allocator,
            "POST /strict?{s} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n",
            .{long_query},
        );
        defer std.testing.allocator.free(request);
        try stream.writeAll(request);

        try std.testing.expect(try waitReadable(stream.handle, 2_000));
        var read_buf: [4096]u8 = undefined;
        const n = try stream.read(&read_buf);
        try std.testing.expect(n > 0);
        try std.testing.expectEqual(@as(?u16, 414), statusCodeFromResponse(read_buf[0..n]));
    }

    // Relaxed route should override query limit and pass.
    {
        var stream = try connectWithRetry(address);
        defer stream.close();

        const request = try std.fmt.allocPrint(
            std.testing.allocator,
            "POST /relaxed?{s} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n",
            .{long_query},
        );
        defer std.testing.allocator.free(request);
        try stream.writeAll(request);

        try std.testing.expect(try waitReadable(stream.handle, 2_000));
        var read_buf: [4096]u8 = undefined;
        const n = try stream.read(&read_buf);
        try std.testing.expect(n > 0);
        try std.testing.expectEqual(@as(?u16, 200), statusCodeFromResponse(read_buf[0..n]));
    }

    // Strict route should use global body limit (8 bytes) and fail.
    {
        var stream = try connectWithRetry(address);
        defer stream.close();

        const request = try std.fmt.allocPrint(
            std.testing.allocator,
            "POST /strict HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ medium_body.len, medium_body },
        );
        defer std.testing.allocator.free(request);
        try stream.writeAll(request);

        try std.testing.expect(try waitReadable(stream.handle, 2_000));
        var read_buf: [4096]u8 = undefined;
        const n = try stream.read(&read_buf);
        try std.testing.expect(n > 0);
        try std.testing.expectEqual(@as(?u16, 413), statusCodeFromResponse(read_buf[0..n]));
    }

    // Relaxed route should override body limit and pass.
    {
        var stream = try connectWithRetry(address);
        defer stream.close();

        const request = try std.fmt.allocPrint(
            std.testing.allocator,
            "POST /relaxed HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ medium_body.len, medium_body },
        );
        defer std.testing.allocator.free(request);
        try stream.writeAll(request);

        try std.testing.expect(try waitReadable(stream.handle, 2_000));
        var read_buf: [4096]u8 = undefined;
        const n = try stream.read(&read_buf);
        try std.testing.expect(n > 0);
        try std.testing.expectEqual(@as(?u16, 200), statusCodeFromResponse(read_buf[0..n]));
    }
}

test "requestShutdown stops server loop gracefully" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "runtime-shutdown",
        .version = "0.0.1",
    });
    defer app.deinit();

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .shutdown_grace_period_ms = 100,
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    std.Thread.sleep(50 * std.time.ns_per_ms);

    app.requestShutdown();
    thread.join();

    try std.testing.expect(serve_ctx.serve_error == null);
}

test "header_timeout_ms closes connections that do not start headers in time" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "runtime-header-timeout",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/ping", guardrailOkHandler, .{});

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .header_timeout_ms = 50,
        .idle_timeout_ms = 2_000,
        .shutdown_grace_period_ms = 100,
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer {
        app.requestShutdown();
        thread.join();
    }

    const address = try std.net.Address.resolveIp("127.0.0.1", port);
    var stream = try connectWithRetry(address);
    defer stream.close();

    std.Thread.sleep(125 * std.time.ns_per_ms);

    const request =
        "GET /ping HTTP/1.1\r\n" ++
        "Host: 127.0.0.1\r\n" ++
        "Connection: close\r\n" ++
        "\r\n";
    stream.writeAll(request) catch |err| switch (err) {
        error.BrokenPipe, error.ConnectionResetByPeer => return,
        else => return err,
    };

    const readable = try waitReadable(stream.handle, 500);
    try std.testing.expect(readable);

    var read_buf: [1024]u8 = undefined;
    const n = stream.read(&read_buf) catch |err| switch (err) {
        error.ConnectionResetByPeer => return,
        else => return err,
    };
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "audit sink emits startup config and lifecycle events during serve" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "runtime-audit",
        .version = "0.0.1",
    });
    defer app.deinit();

    var capture: AuditCapture = .{};
    defer capture.deinit(std.testing.allocator);
    active_audit_capture = &capture;
    defer active_audit_capture = null;

    app.setAuditSink(auditSink);

    const cfg: zigmund.ServerConfig = .{
        .host = "127.0.0.1",
        .port = port,
        .worker_count = 1,
        .accept_poll_interval_ms = 10,
        .header_timeout_ms = 1_500,
        .idle_timeout_ms = 250,
        .shutdown_grace_period_ms = 100,
        .max_header_bytes = 8 * 1024,
        .max_body_bytes = 16 * 1024,
        .max_connections = 32,
        .trusted_proxy_headers = false,
        .trusted_proxy_cidrs = &.{"10.0.0.0/8"},
    };

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = cfg,
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    std.Thread.sleep(75 * std.time.ns_per_ms);

    app.requestShutdown();
    thread.join();

    try std.testing.expect(serve_ctx.serve_error == null);

    capture.mutex.lock();
    defer capture.mutex.unlock();

    try std.testing.expect(capture.startup_config_seen);
    try std.testing.expect(capture.startup_begin_seen);
    try std.testing.expect(capture.startup_complete_seen);
    try std.testing.expect(capture.shutdown_begin_seen);
    try std.testing.expect(capture.shutdown_complete_seen);

    const detail = capture.startup_config_detail orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, detail, "\"host\":\"127.0.0.1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "\"tls_enabled\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "\"trusted_proxy_headers\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "\"trusted_proxy_cidrs\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "\"header_timeout_ms\":1500") != null);

    var port_buf: [32]u8 = undefined;
    const port_fragment = try std.fmt.bufPrint(&port_buf, "\"port\":{d}", .{port});
    try std.testing.expect(std.mem.indexOf(u8, detail, port_fragment) != null);
}
