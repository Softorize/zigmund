const std = @import("std");

pub const Connection = struct {
    pub const Opcode = std.http.Server.WebSocket.Opcode;

    pub const Message = struct {
        opcode: Opcode,
        data: []u8,
    };

    const Mode = enum {
        raw,
        synthetic,
    };

    mode: Mode,
    raw: ?*std.http.Server.WebSocket = null,
    test_endpoint: ?TestEndpoint = null,
    raw_socket_fd: ?std.posix.fd_t = null,
    idle_timeout_ms: ?u64 = null,
    auto_pong: bool = true,
    ping_interval_ms: ?u64 = null,
    pong_timeout_ms: ?u64 = null,
    max_message_bytes: ?usize = null,
    send_timeout_ms: ?u64 = null,
    last_activity_ms: ?i64 = null,
    awaiting_pong_deadline_ms: ?i64 = null,
    negotiated_subprotocol: ?[]const u8 = null,
    last_close_code: ?u16 = null,

    pub fn init(raw: *std.http.Server.WebSocket) Connection {
        return .{
            .mode = .raw,
            .raw = raw,
        };
    }

    pub fn initWithSocket(raw: *std.http.Server.WebSocket, socket_fd: std.posix.fd_t) Connection {
        var conn = init(raw);
        conn.raw_socket_fd = socket_fd;
        return conn;
    }

    pub fn initTest(endpoint: TestEndpoint) Connection {
        return .{
            .mode = .synthetic,
            .test_endpoint = endpoint,
        };
    }

    pub fn setIdleTimeoutMs(self: *Connection, timeout_ms: ?u64) void {
        self.idle_timeout_ms = timeout_ms;
    }

    pub fn setAutoPong(self: *Connection, enabled: bool) void {
        self.auto_pong = enabled;
    }

    pub fn setPingPolicy(self: *Connection, ping_interval_ms: ?u64, pong_timeout_ms: ?u64) void {
        self.ping_interval_ms = ping_interval_ms;
        self.pong_timeout_ms = pong_timeout_ms;
        self.awaiting_pong_deadline_ms = null;
        self.last_activity_ms = std.time.milliTimestamp();
    }

    pub fn setMaxMessageBytes(self: *Connection, max_message_bytes: ?usize) void {
        self.max_message_bytes = max_message_bytes;
    }

    pub fn setSendTimeoutMs(self: *Connection, send_timeout_ms: ?u64) void {
        self.send_timeout_ms = send_timeout_ms;
    }

    pub fn setNegotiatedSubprotocol(self: *Connection, negotiated: ?[]const u8) void {
        self.negotiated_subprotocol = negotiated;
    }

    pub fn subprotocol(self: *const Connection) ?[]const u8 {
        return self.negotiated_subprotocol;
    }

    pub fn lastCloseCode(self: *const Connection) ?u16 {
        return self.last_close_code;
    }

    pub fn sendText(self: *Connection, text: []const u8) !void {
        try self.sendMessage(text, .text);
    }

    pub fn sendBinary(self: *Connection, payload: []const u8) !void {
        try self.sendMessage(payload, .binary);
    }

    pub fn ping(self: *Connection, payload: []const u8) !void {
        try self.sendMessage(payload, .ping);
    }

    pub fn receiveSmall(self: *Connection) !Message {
        return self.receiveInternal(self.idle_timeout_ms);
    }

    pub fn receiveSmallWithTimeout(self: *Connection, timeout_ms: u64) !Message {
        return self.receiveInternal(timeout_ms);
    }

    pub fn close(self: *Connection) void {
        switch (self.mode) {
            .raw => {
                _ = self.closeWithCode(1000, "") catch {};
            },
            .synthetic => {
                _ = self.closeWithCode(1000, "") catch {};
                self.test_endpoint.?.close();
            },
        }
    }

    // Fix #7: removed duplicated .raw/.synthetic branches; replaced
    // heap allocation with a stack buffer (RFC 6455 caps close reason
    // at 123 bytes).
    pub fn closeWithCode(self: *Connection, code: u16, reason: []const u8) !void {
        var payload: [2]u8 = .{
            @intCast((code >> 8) & 0xff),
            @intCast(code & 0xff),
        };
        self.last_close_code = code;

        if (reason.len == 0) {
            try self.sendMessage(&payload, .connection_close);
            return;
        }

        // RFC 6455 limits close reason to 123 bytes (125 - 2 byte code).
        // Use a stack buffer instead of heap allocation.
        var buf: [2 + 123]u8 = undefined;
        const reason_len = @min(reason.len, 123);
        @memcpy(buf[0..2], &payload);
        @memcpy(buf[2..][0..reason_len], reason[0..reason_len]);
        try self.sendMessage(buf[0 .. 2 + reason_len], .connection_close);
    }

    /// Intentionally empty: the Connection wrapper does not own its
    /// underlying resources. The raw WebSocket and test endpoint are
    /// owned by the transport layer (std.http.Server or TestDuplex)
    /// and are freed there. This method exists so callers can follow
    /// a uniform init/deinit pattern without special-casing.
    pub fn deinit(self: *Connection, allocator: std.mem.Allocator) void {
        _ = allocator;
        if (std.debug.runtime_safety) {
            self.raw = null;
            self.test_endpoint = null;
            self.raw_socket_fd = null;
        }
    }

    fn sendMessage(self: *Connection, payload: []const u8, opcode: Opcode) !void {
        switch (self.mode) {
            .raw => {
                if (self.send_timeout_ms) |ms| {
                    const fd = self.raw_socket_fd orelse return error.TimeoutNotSupported;
                    const timeout_i32 = std.math.cast(i32, ms) orelse std.math.maxInt(i32);
                    const writable = try pollWritable(fd, timeout_i32);
                    if (!writable) return error.Backpressure;
                }
                try self.raw.?.writeMessage(payload, opcode);
            },
            .synthetic => try self.test_endpoint.?.sendWithTimeout(payload, opcode, self.send_timeout_ms),
        }
    }

    fn receiveInternal(self: *Connection, timeout_ms: ?u64) !Message {
        const start_ms = std.time.milliTimestamp();
        if (self.last_activity_ms == null) {
            self.last_activity_ms = start_ms;
        }

        const request_deadline_ms: ?i64 = if (timeout_ms) |ms|
            safeAddMs(start_ms, ms)
        else
            null;

        while (true) {
            const now_ms = std.time.milliTimestamp();
            if (request_deadline_ms) |deadline| {
                if (now_ms >= deadline) return error.Timeout;
            }

            try self.maybeStartHeartbeat(now_ms);
            if (self.awaiting_pong_deadline_ms) |pong_deadline| {
                if (now_ms >= pong_deadline) {
                    _ = self.closeWithCode(1011, "pong timeout") catch {};
                    return error.PongTimeout;
                }
            }

            const wait_timeout_ms = self.nextWaitTimeoutMs(request_deadline_ms, now_ms);
            const msg = self.receiveOnce(wait_timeout_ms) catch |err| switch (err) {
                error.Timeout => continue,
                else => return err,
            };

            const recv_ms = std.time.milliTimestamp();
            self.last_activity_ms = recv_ms;

            if (msg.opcode == .connection_close) {
                self.last_close_code = parseCloseCode(msg.data);
                return error.ConnectionClosed;
            }

            if (self.max_message_bytes) |limit| {
                if (msg.data.len > limit) {
                    _ = self.closeWithCode(1009, "message too big") catch {};
                    return error.MessageTooBig;
                }
            }

            if (msg.opcode == .pong) {
                self.awaiting_pong_deadline_ms = null;
            } else if (msg.opcode == .ping and self.auto_pong) {
                // Respond to peer heartbeats while preserving the ping event for handlers.
                self.sendMessage(msg.data, .pong) catch {};
            }

            return msg;
        }
    }

    fn receiveOnce(self: *Connection, timeout_ms: ?u64) !Message {
        return switch (self.mode) {
            .raw => blk: {
                if (timeout_ms) |ms| {
                    const fd = self.raw_socket_fd orelse return error.TimeoutNotSupported;
                    const timeout_i32 = std.math.cast(i32, ms) orelse std.math.maxInt(i32);
                    const ready = try pollReadable(fd, timeout_i32);
                    if (!ready) return error.Timeout;
                }

                const raw_msg = self.raw.?.readSmallMessage() catch |err| switch (err) {
                    error.ConnectionClose => return error.ConnectionClosed,
                    error.MessageTooBig => {
                        _ = self.closeWithCode(1009, "message too big") catch {};
                        return error.MessageTooBig;
                    },
                    else => return err,
                };
                break :blk Message{
                    .opcode = raw_msg.opcode,
                    .data = raw_msg.data,
                };
            },
            .synthetic => blk: {
                const synthetic_msg = if (timeout_ms) |ms|
                    try self.test_endpoint.?.receiveTimed(ms)
                else
                    try self.test_endpoint.?.receive();
                break :blk synthetic_msg;
            },
        };
    }

    fn maybeStartHeartbeat(self: *Connection, now_ms: i64) !void {
        const ping_interval = self.ping_interval_ms orelse return;
        if (self.awaiting_pong_deadline_ms != null) return;

        const last_activity = self.last_activity_ms orelse now_ms;
        if (elapsedMs(last_activity, now_ms) < ping_interval) return;

        try self.sendMessage("", .ping);
        self.last_activity_ms = now_ms;
        if (self.pong_timeout_ms) |pong_timeout| {
            self.awaiting_pong_deadline_ms = safeAddMs(now_ms, pong_timeout);
        }
    }

    fn nextWaitTimeoutMs(
        self: *const Connection,
        request_deadline_ms: ?i64,
        now_ms: i64,
    ) ?u64 {
        var deadline: ?i64 = request_deadline_ms;

        if (self.awaiting_pong_deadline_ms) |pong_deadline| {
            deadline = minDeadline(deadline, pong_deadline);
        }

        if (self.awaiting_pong_deadline_ms == null) {
            if (self.ping_interval_ms) |ping_interval| {
                const last_activity = self.last_activity_ms orelse now_ms;
                const ping_due = safeAddMs(last_activity, ping_interval);
                deadline = minDeadline(deadline, ping_due);
            }
        }

        if (deadline) |deadline_ms| {
            if (deadline_ms <= now_ms) return 0;
            return elapsedMs(now_ms, deadline_ms);
        }
        return null;
    }
};

fn minDeadline(left: ?i64, right: i64) i64 {
    return if (left) |value|
        @min(value, right)
    else
        right;
}

fn elapsedMs(start_ms: i64, end_ms: i64) u64 {
    if (end_ms <= start_ms) return 0;
    const delta: i128 = end_ms - start_ms;
    return @intCast(delta);
}

fn safeAddMs(base_ms: i64, delta_ms: u64) i64 {
    const addend = std.math.cast(i64, delta_ms) orelse std.math.maxInt(i64);
    return std.math.add(i64, base_ms, addend) catch std.math.maxInt(i64);
}

fn parseCloseCode(payload: []const u8) ?u16 {
    if (payload.len < 2) return null;
    return (@as(u16, payload[0]) << 8) | payload[1];
}

// Fix #44: PollError/ConnectionClosed returned instead of treating
// ERR/HUP as readable/writable.
const PollError = error{ PollError, ConnectionClosed };

fn pollReadable(fd: std.posix.fd_t, timeout_ms: i32) (PollError || std.posix.PollError)!bool {
    var pfd = [1]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.IN,
        .revents = undefined,
    }};

    const ready_count = try std.posix.poll(&pfd, timeout_ms);
    if (ready_count == 0) return false;

    const revents = pfd[0].revents;
    if (revents & std.posix.POLL.ERR != 0) return error.PollError;
    if (revents & std.posix.POLL.HUP != 0) return error.ConnectionClosed;
    if (revents & std.posix.POLL.IN != 0) return true;
    return false;
}

fn pollWritable(fd: std.posix.fd_t, timeout_ms: i32) (PollError || std.posix.PollError)!bool {
    var pfd = [1]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.OUT,
        .revents = undefined,
    }};

    const ready_count = try std.posix.poll(&pfd, timeout_ms);
    if (ready_count == 0) return false;

    const revents = pfd[0].revents;
    if (revents & std.posix.POLL.ERR != 0) return error.PollError;
    if (revents & std.posix.POLL.HUP != 0) return error.ConnectionClosed;
    if (revents & std.posix.POLL.OUT != 0) return true;
    return false;
}

pub const TestDuplex = struct {
    allocator: std.mem.Allocator,
    client_to_server: MessageQueue,
    server_to_client: MessageQueue,

    pub fn init(allocator: std.mem.Allocator) TestDuplex {
        return .{
            .allocator = allocator,
            .client_to_server = MessageQueue.init(allocator),
            .server_to_client = MessageQueue.init(allocator),
        };
    }

    pub fn deinit(self: *TestDuplex) void {
        self.client_to_server.deinit();
        self.server_to_client.deinit();
    }

    pub fn close(self: *TestDuplex) void {
        self.client_to_server.close();
        self.server_to_client.close();
    }

    pub fn setMaxPendingMessages(self: *TestDuplex, max_pending_messages: ?usize) void {
        self.client_to_server.setMaxPendingMessages(max_pending_messages);
        self.server_to_client.setMaxPendingMessages(max_pending_messages);
    }

    pub fn clientEndpoint(self: *TestDuplex) TestEndpoint {
        return .{
            .incoming = &self.server_to_client,
            .outgoing = &self.client_to_server,
        };
    }

    pub fn serverEndpoint(self: *TestDuplex) TestEndpoint {
        return .{
            .incoming = &self.client_to_server,
            .outgoing = &self.server_to_client,
        };
    }
};

pub const TestEndpoint = struct {
    incoming: *MessageQueue,
    outgoing: *MessageQueue,

    pub fn send(self: TestEndpoint, payload: []const u8, opcode: Connection.Opcode) !void {
        try self.outgoing.push(payload, opcode);
    }

    pub fn sendWithTimeout(
        self: TestEndpoint,
        payload: []const u8,
        opcode: Connection.Opcode,
        timeout_ms: ?u64,
    ) !void {
        try self.outgoing.pushWithTimeout(payload, opcode, timeout_ms);
    }

    pub fn receive(self: TestEndpoint) !Connection.Message {
        return self.incoming.pop();
    }

    pub fn receiveTimed(self: TestEndpoint, timeout_ms: u64) !Connection.Message {
        return self.incoming.popTimed(timeout_ms);
    }

    pub fn close(self: TestEndpoint) void {
        self.incoming.close();
        self.outgoing.close();
    }
};

// Fix #8: MessageQueue now compacts consumed messages in pop/popTimed
// when read_index > items.len / 2 to prevent unbounded growth.
const MessageQueue = struct {
    const OwnedMessage = struct {
        opcode: Connection.Opcode,
        data: []u8,
    };

    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    closed: bool = false,
    max_pending_messages: ?usize = null,
    messages: std.ArrayListUnmanaged(OwnedMessage) = .empty,
    read_index: usize = 0,

    fn init(allocator: std.mem.Allocator) MessageQueue {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *MessageQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.messages.items) |msg| {
            self.allocator.free(msg.data);
        }
        self.messages.deinit(self.allocator);
        self.read_index = 0;
        self.closed = true;
    }

    fn push(self: *MessageQueue, payload: []const u8, opcode: Connection.Opcode) !void {
        return self.pushWithTimeout(payload, opcode, null);
    }

    fn pushWithTimeout(
        self: *MessageQueue,
        payload: []const u8,
        opcode: Connection.Opcode,
        timeout_ms: ?u64,
    ) !void {
        const timeout_ns: ?u64 = if (timeout_ms) |ms|
            ms * std.time.ns_per_ms
        else
            null;
        const start_ns = std.time.nanoTimestamp();

        self.mutex.lock();
        defer self.mutex.unlock();

        while (!self.closed and self.queueIsFullLocked()) {
            if (timeout_ns) |budget| {
                const now_ns = std.time.nanoTimestamp();
                const elapsed_i128: i128 = if (now_ns > start_ns) now_ns - start_ns else 0;
                const elapsed_ns: u64 = @intCast(elapsed_i128);
                if (elapsed_ns >= budget) return error.Backpressure;
                const remaining = budget - elapsed_ns;
                self.cond.timedWait(&self.mutex, remaining) catch return error.Backpressure;
            } else {
                self.cond.wait(&self.mutex);
            }
        }

        if (self.closed) return error.ConnectionClosed;

        const owned = try self.allocator.dupe(u8, payload);
        errdefer self.allocator.free(owned);

        try self.messages.append(self.allocator, .{
            .opcode = opcode,
            .data = owned,
        });
        self.cond.signal();
    }

    fn pop(self: *MessageQueue) !Connection.Message {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.read_index >= self.messages.items.len and !self.closed) {
            self.cond.wait(&self.mutex);
        }

        if (self.read_index >= self.messages.items.len and self.closed) {
            return error.ConnectionClosed;
        }

        const msg = self.messages.items[self.read_index];
        self.read_index += 1;
        self.compactLocked();
        self.cond.signal();
        if (msg.opcode == .connection_close) {
            self.closed = true;
        }
        return .{
            .opcode = msg.opcode,
            .data = msg.data,
        };
    }

    fn popTimed(self: *MessageQueue, timeout_ms: u64) !Connection.Message {
        self.mutex.lock();
        defer self.mutex.unlock();

        const timeout_ns = timeout_ms * std.time.ns_per_ms;
        const start = std.time.nanoTimestamp();
        var elapsed_ns: u64 = 0;

        while (self.read_index >= self.messages.items.len and !self.closed) {
            if (elapsed_ns >= timeout_ns) return error.Timeout;
            const remaining = timeout_ns - elapsed_ns;
            self.cond.timedWait(&self.mutex, remaining) catch return error.Timeout;

            const now = std.time.nanoTimestamp();
            const elapsed_i128: i128 = if (now > start) now - start else 0;
            elapsed_ns = @intCast(elapsed_i128);
        }

        if (self.read_index >= self.messages.items.len and self.closed) {
            return error.ConnectionClosed;
        }

        const msg = self.messages.items[self.read_index];
        self.read_index += 1;
        self.compactLocked();
        self.cond.signal();
        if (msg.opcode == .connection_close) {
            self.closed = true;
        }

        return .{
            .opcode = msg.opcode,
            .data = msg.data,
        };
    }

    /// Compact consumed messages when more than half the slots have
    /// been read. Frees data of old consumed entries (before the most
    /// recently popped one) and shifts the remainder down. The most
    /// recently popped entry is preserved so its data stays valid for
    /// the caller and can be freed by deinit.
    fn compactLocked(self: *MessageQueue) void {
        if (self.read_index > self.messages.items.len / 2 and self.read_index >= 2) {
            // Free data of entries consumed in *previous* pops
            // (0..read_index-1). The entry at read_index-1 is the one
            // just popped -- its data pointer is still live with the
            // caller so we must keep it.
            for (self.messages.items[0 .. self.read_index - 1]) |old| {
                self.allocator.free(old.data);
            }
            // Shift the just-popped entry + unread entries to front.
            const keep_start = self.read_index - 1;
            const keep_count = self.messages.items.len - keep_start;
            if (keep_count > 0) {
                std.mem.copyForwards(
                    OwnedMessage,
                    self.messages.items[0..keep_count],
                    self.messages.items[keep_start..self.messages.items.len],
                );
            }
            self.messages.items.len = keep_count;
            // read_index now points past the preserved just-popped entry.
            self.read_index = 1;
        }
    }

    fn close(self: *MessageQueue) void {
        self.mutex.lock();
        self.closed = true;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    fn setMaxPendingMessages(self: *MessageQueue, max_pending_messages: ?usize) void {
        self.mutex.lock();
        self.max_pending_messages = max_pending_messages;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    fn queueIsFullLocked(self: *const MessageQueue) bool {
        const limit = self.max_pending_messages orelse return false;
        return self.pendingCountLocked() >= limit;
    }

    fn pendingCountLocked(self: *const MessageQueue) usize {
        if (self.messages.items.len <= self.read_index) return 0;
        return self.messages.items.len - self.read_index;
    }
};

test "test websocket transport exchanges messages" {
    var duplex = TestDuplex.init(std.testing.allocator);
    defer duplex.deinit();

    var server = Connection.initTest(duplex.serverEndpoint());
    var client = Connection.initTest(duplex.clientEndpoint());

    try client.sendText("hello");
    const got_server = try server.receiveSmall();
    try std.testing.expectEqual(.text, got_server.opcode);
    try std.testing.expectEqualStrings("hello", got_server.data);

    try server.sendBinary("ok");
    const got_client = try client.receiveSmall();
    try std.testing.expectEqual(.binary, got_client.opcode);
    try std.testing.expectEqualStrings("ok", got_client.data);

    duplex.close();
    try std.testing.expectError(error.ConnectionClosed, client.receiveSmall());
}
