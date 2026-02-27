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
    while (attempt < 30) : (attempt += 1) {
        const stream = std.net.tcpConnectToAddress(address) catch |err| {
            if (attempt + 1 >= 30) return err;
            std.Thread.sleep(25 * std.time.ns_per_ms);
            continue;
        };
        return stream;
    }
    return error.ConnectionFailed;
}

fn parseStatusCode(response: []const u8) ?u16 {
    const line_end = std.mem.indexOf(u8, response, "\r\n") orelse return null;
    const line = response[0..line_end];

    var parts = std.mem.tokenizeScalar(u8, line, ' ');
    _ = parts.next() orelse return null;
    const code_text = parts.next() orelse return null;
    return std.fmt.parseInt(u16, code_text, 10) catch null;
}

fn pingHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return zigmund.Response.text("pong");
}

var request_started: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var allow_finish: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn resetDrainFlags() void {
    request_started.store(false, .release);
    allow_finish.store(false, .release);
}

fn slowHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    request_started.store(true, .release);

    var attempts: usize = 0;
    while (!allow_finish.load(.acquire) and attempts < 200) : (attempts += 1) {
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    return zigmund.Response.text("drained");
}

const ClientCtx = struct {
    port: u16,
    status: ?u16 = null,
    err: ?anyerror = null,
};

fn slowRequestClientThread(ctx: *ClientCtx) void {
    const address = std.net.Address.resolveIp("127.0.0.1", ctx.port) catch |err| {
        ctx.err = err;
        return;
    };

    var stream = connectWithRetry(address) catch |err| {
        ctx.err = err;
        return;
    };
    defer stream.close();

    const request =
        "GET /slow HTTP/1.1\r\n" ++
        "Host: 127.0.0.1\r\n" ++
        "Connection: close\r\n" ++
        "\r\n";
    stream.writeAll(request) catch |err| {
        ctx.err = err;
        return;
    };

    var buf: [4096]u8 = undefined;
    const n = stream.read(&buf) catch |err| {
        ctx.err = err;
        return;
    };
    if (n == 0) {
        ctx.err = error.EmptyResponse;
        return;
    }
    ctx.status = parseStatusCode(buf[0..n]);
}

test "runtime handles connection churn with consistent 200 responses" {
    const port = try reservePort();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "reliability-churn",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/ping", pingHandler, .{});

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = .{
            .host = "127.0.0.1",
            .port = port,
            .worker_count = 1,
            .accept_poll_interval_ms = 5,
            .idle_timeout_ms = 500,
            .shutdown_grace_period_ms = 500,
            .max_connections = 64,
        },
    };

    const thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer {
        app.requestShutdown();
        thread.join();
    }

    const address = try std.net.Address.resolveIp("127.0.0.1", port);
    var i: usize = 0;
    while (i < 60) : (i += 1) {
        var stream = try connectWithRetry(address);
        defer stream.close();

        const request =
            "GET /ping HTTP/1.1\r\n" ++
            "Host: 127.0.0.1\r\n" ++
            "Connection: close\r\n" ++
            "\r\n";
        try stream.writeAll(request);

        var buf: [2048]u8 = undefined;
        const n = try stream.read(&buf);
        try std.testing.expect(n > 0);
        try std.testing.expectEqual(@as(?u16, 200), parseStatusCode(buf[0..n]));
    }
}

test "runtime drains in-flight request during shutdown" {
    resetDrainFlags();

    const port = try reservePort();
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "reliability-drain",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/slow", slowHandler, .{});

    var serve_ctx: ServeThreadCtx = .{
        .app = &app,
        .cfg = .{
            .host = "127.0.0.1",
            .port = port,
            .worker_count = 1,
            .accept_poll_interval_ms = 5,
            .idle_timeout_ms = 2_000,
            .shutdown_grace_period_ms = 1_500,
            .max_connections = 32,
        },
    };

    const server_thread = try std.Thread.spawn(.{}, serveThread, .{&serve_ctx});
    defer server_thread.join();

    var client_ctx: ClientCtx = .{ .port = port };
    const client_thread = try std.Thread.spawn(.{}, slowRequestClientThread, .{&client_ctx});

    var spins: usize = 0;
    while (!request_started.load(.acquire) and spins < 400) : (spins += 1) {
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }
    try std.testing.expect(request_started.load(.acquire));

    app.requestShutdown();
    allow_finish.store(true, .release);

    client_thread.join();

    if (client_ctx.err) |err| return err;
    try std.testing.expectEqual(@as(?u16, 200), client_ctx.status);
}
