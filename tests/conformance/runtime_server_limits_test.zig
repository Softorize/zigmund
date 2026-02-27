const std = @import("std");
const zigmund = @import("zigmund");

const ServeThreadCtx = struct {
    app: *zigmund.App,
    cfg: zigmund.ServerConfig,
    serve_error: ?anyerror = null,
};

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
    defer thread.join();

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

    app.requestShutdown();
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
    defer thread.join();

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

    app.requestShutdown();
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
