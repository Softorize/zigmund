const std = @import("std");
const App = @import("../core/app.zig").App;
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const TimeoutConfig = struct {
    /// Maximum allowed request processing time in milliseconds.
    timeout_ms: u64 = 30000,
    /// Response body returned when the timeout is exceeded.
    message: []const u8 = "Request timeout",
};

const TimeoutState = struct {
    config: TimeoutConfig,

    fn init(allocator: std.mem.Allocator, config: TimeoutConfig) !*TimeoutState {
        const state = try allocator.create(TimeoutState);
        state.* = .{ .config = config };
        return state;
    }

    fn deinit(self: *TimeoutState, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

fn requestHookWithContext(req: *Request, allocator: std.mem.Allocator, context: ?*anyopaque) !void {
    _ = allocator;
    _ = context;
    const now = std.time.milliTimestamp();
    var buf: [20]u8 = undefined;
    const ts = std.fmt.bufPrint(&buf, "{d}", .{now}) catch return;
    try req.setDependencyValue("_timeout_start_ms", ts);
}

fn responseHookWithContext(
    req: *Request,
    response: *Response,
    allocator: std.mem.Allocator,
    context: ?*anyopaque,
) !void {
    _ = allocator;
    const state = contextToState(context) orelse return;
    const start_str = req.dependency("_timeout_start_ms") orelse return;

    const start_ms = std.fmt.parseInt(i64, start_str, 10) catch return;
    const now = std.time.milliTimestamp();
    const elapsed: u64 = @intCast(@max(0, now - start_ms));

    if (elapsed > state.config.timeout_ms) {
        response.status = .gateway_timeout;
        response.body = state.config.message;
        response.content_type = "text/plain; charset=utf-8";
    }
}

fn deinitContext(context: ?*anyopaque, allocator: std.mem.Allocator) void {
    const state = contextToState(context) orelse return;
    state.deinit(allocator);
}

fn contextToState(context: ?*anyopaque) ?*TimeoutState {
    const ptr = context orelse return null;
    return @ptrCast(@alignCast(ptr));
}

/// Create a Middleware struct ready to register with the app.
pub fn middleware(allocator: std.mem.Allocator, config: TimeoutConfig) App.Middleware {
    const state = TimeoutState.init(allocator, config) catch @panic("failed to initialize timeout middleware");
    return .{
        .name = "timeout",
        .context = @ptrCast(state),
        .request_hook_with_context = &requestHookWithContext,
        .response_hook_with_context = &responseHookWithContext,
        .deinit_hook = &deinitContext,
    };
}
