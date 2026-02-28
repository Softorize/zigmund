const std = @import("std");
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

var global_options: RateLimitOptions = .{};
var global_store: std.StringHashMap(WindowEntry) = undefined;
var global_store_init: bool = false;
var global_allocator: std.mem.Allocator = undefined;

pub fn configure(allocator: std.mem.Allocator, options: RateLimitOptions) void {
    global_options = options;
    global_allocator = allocator;
    if (!global_store_init) {
        global_store = std.StringHashMap(WindowEntry).init(allocator);
        global_store_init = true;
    }
}

pub fn deinit() void {
    if (global_store_init) {
        var iter = global_store.keyIterator();
        while (iter.next()) |key| {
            global_allocator.free(key.*);
        }
        global_store.deinit();
        global_store_init = false;
    }
}

fn getClientKey(req: *Request) []const u8 {
    if (global_options.key_func) |kf| return kf(req);
    return req.header("x-forwarded-for") orelse req.header("x-real-ip") orelse "unknown";
}

fn currentTimestamp() i64 {
    return std.time.timestamp();
}

/// Request hook: check rate limit and set headers.
pub fn requestHook(req: *Request, allocator: std.mem.Allocator) !void {
    if (!global_store_init) return;
    _ = allocator;

    const key = getClientKey(req);
    const now = currentTimestamp();
    const window = @as(i64, global_options.window_seconds);

    const entry = global_store.getPtr(key);
    if (entry) |e| {
        if (now - e.window_start >= window) {
            e.count = 1;
            e.window_start = now;
        } else {
            e.count += 1;
        }

        const remaining = if (e.count <= global_options.max_requests) global_options.max_requests - e.count else 0;
        const reset = e.window_start + window;

        var limit_buf: [20]u8 = undefined;
        var remaining_buf: [20]u8 = undefined;
        var reset_buf: [20]u8 = undefined;
        const limit_str = std.fmt.bufPrint(&limit_buf, "{d}", .{global_options.max_requests}) catch return;
        const remaining_str = std.fmt.bufPrint(&remaining_buf, "{d}", .{remaining}) catch return;
        const reset_str = std.fmt.bufPrint(&reset_buf, "{d}", .{reset}) catch return;

        try req.setDependencyValue("_rate_limit", limit_str);
        try req.setDependencyValue("_rate_remaining", remaining_str);
        try req.setDependencyValue("_rate_reset", reset_str);

        if (e.count > global_options.max_requests) {
            try req.setDependencyValue("_rate_exceeded", "true");
        }
    } else {
        const owned_key = try global_allocator.dupe(u8, key);
        try global_store.put(owned_key, .{ .count = 1, .window_start = now });

        const remaining = global_options.max_requests - 1;
        const reset = now + window;

        var limit_buf: [20]u8 = undefined;
        var remaining_buf: [20]u8 = undefined;
        var reset_buf: [20]u8 = undefined;
        const limit_str = std.fmt.bufPrint(&limit_buf, "{d}", .{global_options.max_requests}) catch return;
        const remaining_str = std.fmt.bufPrint(&remaining_buf, "{d}", .{remaining}) catch return;
        const reset_str = std.fmt.bufPrint(&reset_buf, "{d}", .{reset}) catch return;

        try req.setDependencyValue("_rate_limit", limit_str);
        try req.setDependencyValue("_rate_remaining", remaining_str);
        try req.setDependencyValue("_rate_reset", reset_str);
    }
}

/// Response hook: add rate limit headers, return 429 if exceeded.
pub fn responseHook(req: *Request, response: *Response, allocator: std.mem.Allocator) !void {
    const limit = req.dependency("_rate_limit") orelse return;
    const remaining = req.dependency("_rate_remaining") orelse return;
    const reset = req.dependency("_rate_reset") orelse return;

    try response.setHeader(allocator, "X-RateLimit-Limit", limit);
    try response.setHeader(allocator, "X-RateLimit-Remaining", remaining);
    try response.setHeader(allocator, "X-RateLimit-Reset", reset);

    if (req.dependency("_rate_exceeded")) |_| {
        response.status = .too_many_requests;
        response.body = "{\"detail\":\"Rate limit exceeded\"}";
        response.content_type = "application/json";

        var retry_buf: [20]u8 = undefined;
        const retry_after = std.fmt.bufPrint(&retry_buf, "{d}", .{global_options.window_seconds}) catch "60";
        try response.setHeader(allocator, "Retry-After", retry_after);
    }
}

/// Create a Middleware struct ready to register with the app.
pub fn middleware(allocator: std.mem.Allocator, options: RateLimitOptions) @import("../core/app.zig").App.Middleware {
    configure(allocator, options);
    return .{
        .name = "rate_limit",
        .request_hook = &requestHook,
        .response_hook = &responseHook,
    };
}
