const std = @import("std");
const ServerConfig = @import("config.zig").ServerConfig;
const tls_openssl = @import("tls_openssl.zig");

pub const DispatchFn = *const fn (
    ctx: *anyopaque,
    raw_request: *std.http.Server.Request,
    peer_address: std.net.Address,
    socket_fd: std.posix.fd_t,
) anyerror!void;
pub const ShouldStopFn = *const fn (ctx: *anyopaque) bool;

const ServeState = struct {
    should_stop_ctx: ?*anyopaque = null,
    should_stop_fn: ?ShouldStopFn = null,
    active_connections: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    shutdown_started_ms: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
};

pub fn serve(
    ctx: *anyopaque,
    cfg: ServerConfig,
    dispatch: DispatchFn,
    should_stop_ctx: ?*anyopaque,
    should_stop_fn: ?ShouldStopFn,
) anyerror!void {
    var tls_ctx_storage: ?tls_openssl.Context = null;
    defer {
        if (tls_ctx_storage) |*tls_ctx| tls_ctx.deinit();
    }
    if (cfg.tls) |tls_cfg| {
        tls_ctx_storage = try tls_openssl.Context.init(tls_cfg);
    }
    const tls_ctx: ?*const tls_openssl.Context = if (tls_ctx_storage) |*ctx_ptr| ctx_ptr else null;

    const address = try std.net.Address.resolveIp(cfg.host, cfg.port);
    var listener = try address.listen(.{
        .reuse_address = cfg.reuse_address,
        .kernel_backlog = 1024,
    });
    defer listener.deinit();

    var state: ServeState = .{
        .should_stop_ctx = should_stop_ctx,
        .should_stop_fn = should_stop_fn,
    };

    const workers = cfg.resolvedWorkerCount();
    const scheme: []const u8 = if (cfg.tls != null) "https" else "http";
    std.log.info("zigmund listening on {s}://{s}:{d} with {d} worker(s)", .{ scheme, cfg.host, cfg.port, workers });

    if (workers <= 1) {
        workerLoop(&listener, cfg, ctx, dispatch, &state, tls_ctx);
        return;
    }

    const threads = std.heap.c_allocator.alloc(std.Thread, workers - 1) catch return error.WorkerSpawnFailed;
    defer std.heap.c_allocator.free(threads);

    for (threads) |*thread| {
        thread.* = std.Thread.spawn(.{}, workerLoop, .{ &listener, cfg, ctx, dispatch, &state, tls_ctx }) catch {
            return error.WorkerSpawnFailed;
        };
    }

    workerLoop(&listener, cfg, ctx, dispatch, &state, tls_ctx);

    for (threads) |thread| {
        thread.join();
    }
}

fn workerLoop(
    listener: *std.net.Server,
    cfg: ServerConfig,
    ctx: *anyopaque,
    dispatch: DispatchFn,
    state: *ServeState,
    tls_ctx: ?*const tls_openssl.Context,
) void {
    while (true) {
        if (shouldTerminate(state, cfg)) return;

        const ready = pollReadable(listener.stream.handle, cfg.accept_poll_interval_ms) catch |err| {
            std.log.err("accept poll failed: {s}", .{@errorName(err)});
            continue;
        };
        if (!ready) continue;

        const connection = listener.accept() catch |err| {
            std.log.err("accept failed: {s}", .{@errorName(err)});
            continue;
        };

        if (shutdownRequested(state)) {
            connection.stream.close();
            continue;
        }

        if (cfg.max_connections != 0 and state.active_connections.load(.acquire) >= cfg.max_connections) {
            sendOverloadedResponse(connection.stream.handle, cfg.overload_retry_after_seconds);
            connection.stream.close();
            continue;
        }

        _ = state.active_connections.fetchAdd(1, .acq_rel);
        defer _ = state.active_connections.fetchSub(1, .acq_rel);

        handleConnection(connection, cfg, ctx, dispatch, state, tls_ctx) catch |err| {
            std.log.err("connection failed: {s}", .{@errorName(err)});
        };
    }
}

fn handleConnection(
    connection: std.net.Server.Connection,
    cfg: ServerConfig,
    ctx: *anyopaque,
    dispatch: DispatchFn,
    state: *ServeState,
    tls_ctx: ?*const tls_openssl.Context,
) !void {
    const peer_address = connection.address;
    defer connection.stream.close();

    const recv_buf = try std.heap.c_allocator.alloc(u8, cfg.recv_buffer_size);
    defer std.heap.c_allocator.free(recv_buf);
    const send_buf = try std.heap.c_allocator.alloc(u8, cfg.send_buffer_size);
    defer std.heap.c_allocator.free(send_buf);

    if (tls_ctx) |tls_context| {
        var tls_conn = try tls_openssl.Connection.init(tls_context, connection.stream.handle, recv_buf, send_buf);
        defer tls_conn.deinit();

        var server = std.http.Server.init(&tls_conn.reader, &tls_conn.writer);
        try serveRequests(&server, connection.stream.handle, cfg, ctx, dispatch, state, peer_address);
        return;
    }

    var conn_reader = connection.stream.reader(recv_buf);
    var conn_writer = connection.stream.writer(send_buf);
    var server = std.http.Server.init(conn_reader.interface(), &conn_writer.interface);
    try serveRequests(&server, connection.stream.handle, cfg, ctx, dispatch, state, peer_address);
}

fn serveRequests(
    server: *std.http.Server,
    socket_fd: std.posix.fd_t,
    cfg: ServerConfig,
    ctx: *anyopaque,
    dispatch: DispatchFn,
    state: *ServeState,
    peer_address: std.net.Address,
) !void {
    var first_request = true;
    while (server.reader.state == .ready) {
        const read_timeout_ms: i32 = if (first_request and cfg.header_timeout_ms >= 0)
            cfg.header_timeout_ms
        else
            cfg.idle_timeout_ms;

        if (read_timeout_ms >= 0) {
            const ready = try pollReadable(socket_fd, read_timeout_ms);
            if (!ready) return;
        }

        var raw_request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => return err,
        };
        first_request = false;

        if (cfg.max_header_bytes != 0 and requestHeaderBytes(&raw_request) > cfg.max_header_bytes) {
            raw_request.respond("request header too large", .{
                .status = .request_header_fields_too_large,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "text/plain; charset=utf-8" },
                },
            }) catch {};
            return;
        }

        if (cfg.body_timeout_ms >= 0) {
            try setSocketRecvTimeout(socket_fd, cfg.body_timeout_ms);
        }
        defer if (cfg.body_timeout_ms >= 0) {
            setSocketRecvTimeout(socket_fd, 0) catch {};
        };
        if (cfg.write_timeout_ms >= 0) {
            try setSocketSendTimeout(socket_fd, cfg.write_timeout_ms);
        }
        defer if (cfg.write_timeout_ms >= 0) {
            setSocketSendTimeout(socket_fd, 0) catch {};
        };

        dispatch(ctx, &raw_request, peer_address, socket_fd) catch |err| {
            std.log.err("request dispatch failed for {s}: {s}", .{ raw_request.head.target, @errorName(err) });
            raw_request.respond("internal server error", .{
                .status = .internal_server_error,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "text/plain; charset=utf-8" },
                },
            }) catch {};
            return;
        };

        // During graceful shutdown, drain after the active request.
        if (shutdownRequested(state)) return;
    }
}

fn pollReadable(fd: std.posix.fd_t, timeout_ms: i32) !bool {
    var pfd = [1]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.IN,
        .revents = undefined,
    }};

    const ready_count = try std.posix.poll(&pfd, timeout_ms);
    if (ready_count == 0) return false;

    const revents = pfd[0].revents;
    if (revents & std.posix.POLL.IN != 0) return true;
    if (revents & std.posix.POLL.HUP != 0) return true;
    if (revents & std.posix.POLL.ERR != 0) return true;
    return false;
}

fn requestHeaderBytes(raw_request: *std.http.Server.Request) usize {
    var total: usize = @tagName(raw_request.head.method).len +
        1 +
        raw_request.head.target.len +
        " HTTP/1.1\r\n".len;

    var headers = raw_request.iterateHeaders();
    while (headers.next()) |header| {
        total += header.name.len + 2 + header.value.len + 2;
    }

    total += 2;
    return total;
}

fn sendOverloadedResponse(fd: std.posix.fd_t, retry_after_seconds: u32) void {
    if (retry_after_seconds == 0) {
        const response =
            "HTTP/1.1 503 Service Unavailable\r\n" ++
            "content-type: text/plain; charset=utf-8\r\n" ++
            "content-length: 17\r\n" ++
            "connection: close\r\n" ++
            "\r\n" ++
            "server overloaded";
        _ = std.posix.write(fd, response) catch {};
        return;
    }

    var retry_after_buf: [32]u8 = undefined;
    const retry_after = std.fmt.bufPrint(&retry_after_buf, "{d}", .{retry_after_seconds}) catch return;

    var response_buf: [512]u8 = undefined;
    const response = std.fmt.bufPrint(
        &response_buf,
        "HTTP/1.1 503 Service Unavailable\r\n" ++
            "content-type: text/plain; charset=utf-8\r\n" ++
            "content-length: 17\r\n" ++
            "connection: close\r\n" ++
            "retry-after: {s}\r\n" ++
            "\r\n" ++
            "server overloaded",
        .{retry_after},
    ) catch return;
    _ = std.posix.write(fd, response) catch {};
}

fn setSocketRecvTimeout(fd: std.posix.fd_t, timeout_ms: i32) !void {
    if (timeout_ms < 0) return;

    const timeout_ms_nonnegative: u64 = @intCast(timeout_ms);
    const secs: i64 = @intCast(timeout_ms_nonnegative / 1000);
    const usec: i32 = @intCast((timeout_ms_nonnegative % 1000) * 1000);
    const timeout = std.posix.timeval{
        .sec = secs,
        .usec = usec,
    };
    try std.posix.setsockopt(
        fd,
        std.posix.SOL.SOCKET,
        std.posix.SO.RCVTIMEO,
        std.mem.asBytes(&timeout),
    );
}

fn setSocketSendTimeout(fd: std.posix.fd_t, timeout_ms: i32) !void {
    if (timeout_ms < 0) return;

    const timeout_ms_nonnegative: u64 = @intCast(timeout_ms);
    const secs: i64 = @intCast(timeout_ms_nonnegative / 1000);
    const usec: i32 = @intCast((timeout_ms_nonnegative % 1000) * 1000);
    const timeout = std.posix.timeval{
        .sec = secs,
        .usec = usec,
    };
    try std.posix.setsockopt(
        fd,
        std.posix.SOL.SOCKET,
        std.posix.SO.SNDTIMEO,
        std.mem.asBytes(&timeout),
    );
}

fn shutdownRequested(state: *const ServeState) bool {
    const should_stop_fn = state.should_stop_fn orelse return false;
    const stop_ctx = state.should_stop_ctx orelse return false;
    return should_stop_fn(stop_ctx);
}

fn shouldTerminate(state: *ServeState, cfg: ServerConfig) bool {
    if (!shutdownRequested(state)) return false;

    if (state.shutdown_started_ms.load(.acquire) == 0) {
        state.shutdown_started_ms.store(std.time.milliTimestamp(), .release);
    }

    if (state.active_connections.load(.acquire) == 0) return true;
    if (cfg.shutdown_grace_period_ms == 0) return true;

    const started_ms = state.shutdown_started_ms.load(.acquire);
    if (started_ms == 0) return false;

    const now_ms = std.time.milliTimestamp();
    const elapsed_ms: u64 = @intCast(if (now_ms > started_ms) now_ms - started_ms else 0);
    return elapsed_ms >= cfg.shutdown_grace_period_ms;
}

test "sendOverloadedResponse writes 503 payload" {
    const bind_address = try std.net.Address.resolveIp("127.0.0.1", 0);
    var listener = try bind_address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const client_address = try std.net.Address.resolveIp("127.0.0.1", listener.listen_address.getPort());
    var client = try std.net.tcpConnectToAddress(client_address);
    defer client.close();

    const accepted = try listener.accept();
    defer accepted.stream.close();

    sendOverloadedResponse(accepted.stream.handle, 1);

    var read_buf: [512]u8 = undefined;
    const n = try client.read(&read_buf);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.indexOf(u8, read_buf[0..n], "503 Service Unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, read_buf[0..n], "retry-after: 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, read_buf[0..n], "server overloaded") != null);
}

test "sendOverloadedResponse omits retry-after when disabled" {
    const bind_address = try std.net.Address.resolveIp("127.0.0.1", 0);
    var listener = try bind_address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const client_address = try std.net.Address.resolveIp("127.0.0.1", listener.listen_address.getPort());
    var client = try std.net.tcpConnectToAddress(client_address);
    defer client.close();

    const accepted = try listener.accept();
    defer accepted.stream.close();

    sendOverloadedResponse(accepted.stream.handle, 0);

    var read_buf: [512]u8 = undefined;
    const n = try client.read(&read_buf);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.indexOf(u8, read_buf[0..n], "503 Service Unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, read_buf[0..n], "retry-after:") == null);
    try std.testing.expect(std.mem.indexOf(u8, read_buf[0..n], "server overloaded") != null);
}
