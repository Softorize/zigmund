const std = @import("std");
const App = @import("../core/app.zig").App;
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const HttpsRedirectConfig = struct {
    /// HTTP status code for the redirect (default 307 Temporary Redirect).
    redirect_status: std.http.Status = .temporary_redirect,
    /// Port to redirect to (null = omit port, use default 443).
    https_port: ?u16 = null,
};

const HttpsRedirectState = struct {
    config: HttpsRedirectConfig,

    fn init(allocator: std.mem.Allocator, config: HttpsRedirectConfig) !*HttpsRedirectState {
        const state = try allocator.create(HttpsRedirectState);
        state.* = .{ .config = config };
        return state;
    }

    fn deinit(self: *HttpsRedirectState, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

fn requestHookWithContext(req: *Request, allocator: std.mem.Allocator, context: ?*anyopaque) !void {
    _ = allocator;
    const state = contextToState(context) orelse return;

    // Check if the request is already HTTPS via X-Forwarded-Proto header.
    if (req.header("x-forwarded-proto")) |proto| {
        if (std.ascii.eqlIgnoreCase(proto, "https")) return;
    }

    // Build the redirect URL: "https://" + host + path + query
    const host_raw = req.header("host") orelse return;

    // Strip any existing port from the host (handles IPv6 bracket notation).
    const host = stripPort(host_raw);

    // Build the URL into a stack buffer to avoid allocation.
    var buf: [4096]u8 = undefined;
    const url = if (state.config.https_port) |port| blk: {
        break :blk std.fmt.bufPrint(&buf, "https://{s}:{d}{s}", .{ host, port, req.target }) catch return;
    } else blk: {
        break :blk std.fmt.bufPrint(&buf, "https://{s}{s}", .{ host, req.target }) catch return;
    };

    // Store the redirect URL and status for the response hook.
    try req.setDependencyValue("_https_redirect_url", url);
    var status_buf: [4]u8 = undefined;
    const status_str = std.fmt.bufPrint(&status_buf, "{d}", .{@intFromEnum(state.config.redirect_status)}) catch return;
    try req.setDependencyValue("_https_redirect_status", status_str);
}

fn responseHookWithContext(
    req: *Request,
    response: *Response,
    allocator: std.mem.Allocator,
    context: ?*anyopaque,
) !void {
    _ = context;
    const redirect_url = req.dependency("_https_redirect_url") orelse return;
    const status_str = req.dependency("_https_redirect_status") orelse return;

    const status_int = std.fmt.parseInt(u10, status_str, 10) catch return;
    const status: std.http.Status = @enumFromInt(status_int);

    response.status = status;
    response.body = "";
    response.content_type = "text/plain; charset=utf-8";
    try response.setHeader(allocator, "location", redirect_url);
}

fn deinitContext(context: ?*anyopaque, allocator: std.mem.Allocator) void {
    const state = contextToState(context) orelse return;
    state.deinit(allocator);
}

fn contextToState(context: ?*anyopaque) ?*HttpsRedirectState {
    const ptr = context orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn stripPort(host: []const u8) []const u8 {
    if (host.len > 0 and host[0] == '[') {
        if (std.mem.indexOfScalar(u8, host, ']')) |close| {
            return host[0 .. close + 1];
        }
        return host;
    }
    if (std.mem.lastIndexOfScalar(u8, host, ':')) |colon| {
        const after = host[colon + 1 ..];
        if (after.len > 0) {
            for (after) |c| {
                if (c < '0' or c > '9') return host;
            }
            return host[0..colon];
        }
    }
    return host;
}

/// Create a Middleware struct ready to register with the app.
pub fn middleware(allocator: std.mem.Allocator, config: HttpsRedirectConfig) App.Middleware {
    const state = HttpsRedirectState.init(allocator, config) catch @panic("failed to initialize https_redirect middleware");
    return .{
        .name = "https_redirect",
        .context = @ptrCast(state),
        .request_hook_with_context = &requestHookWithContext,
        .response_hook_with_context = &responseHookWithContext,
        .deinit_hook = &deinitContext,
    };
}
