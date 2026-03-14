const std = @import("std");
const App = @import("../core/app.zig").App;
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const RateLimitOptions = struct {
    /// Maximum requests per window.
    max_requests: u32 = 100,
    /// Window size in seconds.
    window_seconds: u32 = 60,
    /// Function to extract client key (defaults to IP from X-Forwarded-For or remote address).
    key_func: ?*const fn (*Request) []const u8 = null,
};

const WindowEntry = struct {
    count: u32,
    window_start: i64,
};

const RateLimitObservation = struct {
    limit: u32,
    remaining: u32,
    reset: i64,
    exceeded: bool,
};

const RateLimitState = struct {
    allocator: std.mem.Allocator,
    options: RateLimitOptions,
    store: std.StringHashMap(WindowEntry),
    mutex: std.Thread.Mutex = .{},

    fn init(allocator: std.mem.Allocator, options: RateLimitOptions) !*RateLimitState {
        const state = try allocator.create(RateLimitState);
        errdefer allocator.destroy(state);

        state.* = .{
            .allocator = allocator,
            .options = options,
            .store = std.StringHashMap(WindowEntry).init(allocator),
        };
        return state;
    }

    fn deinit(self: *RateLimitState) void {
        var iter = self.store.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.store.deinit();
        self.allocator.destroy(self);
    }

    fn observe(self: *RateLimitState, req: *Request) !RateLimitObservation {
        const key = getClientKey(self.options, req);
        const now = currentTimestamp();
        const window_seconds = @as(i64, self.options.window_seconds);

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.store.getPtr(key)) |entry| {
            if (now - entry.window_start >= window_seconds) {
                entry.count = 1;
                entry.window_start = now;
            } else {
                entry.count += 1;
            }

            return .{
                .limit = self.options.max_requests,
                .remaining = remainingRequests(self.options.max_requests, entry.count),
                .reset = entry.window_start + window_seconds,
                .exceeded = entry.count > self.options.max_requests,
            };
        }

        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);

        try self.store.put(owned_key, .{
            .count = 1,
            .window_start = now,
        });

        return .{
            .limit = self.options.max_requests,
            .remaining = remainingRequests(self.options.max_requests, 1),
            .reset = now + window_seconds,
            .exceeded = false,
        };
    }
};

pub fn configure(_: std.mem.Allocator, _: RateLimitOptions) void {}

pub fn deinit() void {}

fn getClientKey(options: RateLimitOptions, req: *Request) []const u8 {
    if (options.key_func) |kf| return kf(req);
    return req.header("x-forwarded-for") orelse req.header("x-real-ip") orelse "unknown";
}

fn currentTimestamp() i64 {
    return std.time.timestamp();
}

fn remainingRequests(limit: u32, count: u32) u32 {
    if (count >= limit) return 0;
    return limit - count;
}

fn writeObservation(req: *Request, observation: RateLimitObservation) !void {
    var limit_buf: [20]u8 = undefined;
    var remaining_buf: [20]u8 = undefined;
    var reset_buf: [20]u8 = undefined;

    const limit_str = try std.fmt.bufPrint(&limit_buf, "{d}", .{observation.limit});
    const remaining_str = try std.fmt.bufPrint(&remaining_buf, "{d}", .{observation.remaining});
    const reset_str = try std.fmt.bufPrint(&reset_buf, "{d}", .{observation.reset});

    try req.setDependencyValue("_rate_limit", limit_str);
    try req.setDependencyValue("_rate_remaining", remaining_str);
    try req.setDependencyValue("_rate_reset", reset_str);

    if (observation.exceeded) {
        try req.setDependencyValue("_rate_exceeded", "true");
    }
}

pub fn requestHook(req: *Request, allocator: std.mem.Allocator) !void {
    _ = req;
    _ = allocator;
}

fn requestHookWithContext(req: *Request, allocator: std.mem.Allocator, context: ?*anyopaque) !void {
    _ = allocator;
    const state = contextToState(context) orelse return;
    const observation = try state.observe(req);
    try writeObservation(req, observation);
}

pub fn responseHook(req: *Request, response: *Response, allocator: std.mem.Allocator) !void {
    _ = req;
    _ = response;
    _ = allocator;
}

fn responseHookWithContext(
    req: *Request,
    response: *Response,
    allocator: std.mem.Allocator,
    context: ?*anyopaque,
) !void {
    const limit = req.dependency("_rate_limit") orelse return;
    const remaining = req.dependency("_rate_remaining") orelse return;
    const reset = req.dependency("_rate_reset") orelse return;

    try response.setHeader(allocator, "X-RateLimit-Limit", limit);
    try response.setHeader(allocator, "X-RateLimit-Remaining", remaining);
    try response.setHeader(allocator, "X-RateLimit-Reset", reset);

    if (req.dependency("_rate_exceeded")) |_| {
        const state = contextToState(context) orelse return;
        response.status = .too_many_requests;
        response.body = "{\"detail\":\"Rate limit exceeded\"}";
        response.content_type = "application/json";

        var retry_buf: [20]u8 = undefined;
        const retry_after = std.fmt.bufPrint(&retry_buf, "{d}", .{state.options.window_seconds}) catch "60";
        try response.setHeader(allocator, "Retry-After", retry_after);
    }
}

fn deinitContext(context: ?*anyopaque, allocator: std.mem.Allocator) void {
    _ = allocator;
    const state = contextToState(context) orelse return;
    state.deinit();
}

fn contextToState(context: ?*anyopaque) ?*RateLimitState {
    const ptr = context orelse return null;
    return @ptrCast(@alignCast(ptr));
}

/// Create a Middleware struct ready to register with the app.
pub fn middleware(allocator: std.mem.Allocator, options: RateLimitOptions) App.Middleware {
    const state = RateLimitState.init(allocator, options) catch @panic("failed to initialize rate limit middleware");
    return .{
        .name = "rate_limit",
        .context = @ptrCast(state),
        .request_hook_with_context = &requestHookWithContext,
        .response_hook_with_context = &responseHookWithContext,
        .deinit_hook = &deinitContext,
    };
}
