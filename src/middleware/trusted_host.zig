const std = @import("std");
const App = @import("../core/app.zig").App;
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const TrustedHostConfig = struct {
    /// Allowed host values. Use "*" to allow any host.
    allowed_hosts: []const []const u8 = &.{"*"},
    /// Whether to allow requests without a Host header.
    allow_missing_host: bool = false,
};

const TrustedHostState = struct {
    config: TrustedHostConfig,

    fn init(allocator: std.mem.Allocator, config: TrustedHostConfig) !*TrustedHostState {
        const state = try allocator.create(TrustedHostState);
        state.* = .{ .config = config };
        return state;
    }

    fn deinit(self: *TrustedHostState, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

/// Check whether the given host matches any entry in the allowlist.
/// Supports exact match and wildcard subdomain match (entries starting
/// with "." match any subdomain, e.g. ".example.com" matches
/// "api.example.com" and "foo.bar.example.com").
fn isHostAllowed(config: TrustedHostConfig, host_raw: []const u8) bool {
    // Strip port if present (handle IPv6 bracket notation)
    const host = stripPort(host_raw);

    for (config.allowed_hosts) |entry| {
        if (std.mem.eql(u8, entry, "*")) return true;

        if (entry.len > 0 and entry[0] == '.') {
            // Wildcard subdomain: ".example.com" matches "sub.example.com"
            if (std.ascii.endsWithIgnoreCase(host, entry)) return true;
            // Also match the bare domain: ".example.com" should match "example.com"
            if (entry.len > 1 and std.ascii.eqlIgnoreCase(host, entry[1..])) return true;
        } else {
            if (std.ascii.eqlIgnoreCase(host, entry)) return true;
        }
    }
    return false;
}

/// Strip the port portion from a host string.
/// Handles both plain hosts ("example.com:8080") and IPv6 bracket
/// notation ("[::1]:8080").
fn stripPort(host: []const u8) []const u8 {
    // IPv6 bracket notation: [::1]:port
    if (host.len > 0 and host[0] == '[') {
        if (std.mem.indexOfScalar(u8, host, ']')) |close| {
            return host[0 .. close + 1];
        }
        return host;
    }

    // Plain host:port — find last colon
    if (std.mem.lastIndexOfScalar(u8, host, ':')) |colon| {
        // Make sure everything after the colon looks like a port number
        const after = host[colon + 1 ..];
        if (after.len > 0 and isAllDigits(after)) {
            return host[0..colon];
        }
    }
    return host;
}

fn isAllDigits(s: []const u8) bool {
    for (s) |c| {
        if (c < '0' or c > '9') return false;
    }
    return true;
}

fn requestHookWithContext(req: *Request, allocator: std.mem.Allocator, context: ?*anyopaque) !void {
    _ = allocator;
    const state = contextToState(context) orelse return;

    const host = req.header("host");

    if (host == null) {
        if (!state.config.allow_missing_host) {
            try req.setDependencyValue("_trusted_host_rejected", "true");
        }
        return;
    }

    if (!isHostAllowed(state.config, host.?)) {
        try req.setDependencyValue("_trusted_host_rejected", "true");
    }
}

fn responseHookWithContext(
    req: *Request,
    response: *Response,
    allocator: std.mem.Allocator,
    context: ?*anyopaque,
) !void {
    _ = allocator;
    _ = context;

    if (req.dependency("_trusted_host_rejected")) |_| {
        response.status = .bad_request;
        response.body = "Invalid host header";
        response.content_type = "text/plain";
    }
}

fn deinitContext(context: ?*anyopaque, allocator: std.mem.Allocator) void {
    const state = contextToState(context) orelse return;
    state.deinit(allocator);
}

fn contextToState(context: ?*anyopaque) ?*TrustedHostState {
    const ptr = context orelse return null;
    return @ptrCast(@alignCast(ptr));
}

/// Create a Middleware struct ready to register with the app.
pub fn middleware(allocator: std.mem.Allocator, config: TrustedHostConfig) App.Middleware {
    const state = TrustedHostState.init(allocator, config) catch @panic("failed to initialize trusted_host middleware");
    return .{
        .name = "trusted_host",
        .context = @ptrCast(state),
        .request_hook_with_context = &requestHookWithContext,
        .response_hook_with_context = &responseHookWithContext,
        .deinit_hook = &deinitContext,
    };
}

// ── Unit tests ──────────────────────────────────────────────────────────

test "stripPort removes port from host" {
    try std.testing.expectEqualStrings("example.com", stripPort("example.com:8080"));
    try std.testing.expectEqualStrings("example.com", stripPort("example.com"));
    try std.testing.expectEqualStrings("[::1]", stripPort("[::1]:8080"));
    try std.testing.expectEqualStrings("[::1]", stripPort("[::1]"));
}

test "isHostAllowed wildcard allows everything" {
    const config = TrustedHostConfig{ .allowed_hosts = &.{"*"} };
    try std.testing.expect(isHostAllowed(config, "anything.example.com"));
    try std.testing.expect(isHostAllowed(config, "localhost"));
}

test "isHostAllowed exact match" {
    const config = TrustedHostConfig{ .allowed_hosts = &.{"example.com"} };
    try std.testing.expect(isHostAllowed(config, "example.com"));
    try std.testing.expect(isHostAllowed(config, "example.com:443"));
    try std.testing.expect(!isHostAllowed(config, "evil.com"));
}

test "isHostAllowed subdomain wildcard" {
    const config = TrustedHostConfig{ .allowed_hosts = &.{".example.com"} };
    try std.testing.expect(isHostAllowed(config, "api.example.com"));
    try std.testing.expect(isHostAllowed(config, "foo.bar.example.com"));
    try std.testing.expect(isHostAllowed(config, "example.com"));
    try std.testing.expect(!isHostAllowed(config, "evil.com"));
    try std.testing.expect(!isHostAllowed(config, "notexample.com"));
}

test "isHostAllowed case insensitive" {
    const config = TrustedHostConfig{ .allowed_hosts = &.{"Example.COM"} };
    try std.testing.expect(isHostAllowed(config, "example.com"));
    try std.testing.expect(isHostAllowed(config, "EXAMPLE.COM"));
}
