const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const CsrfOptions = struct {
    /// Name of the cookie holding the CSRF token.
    cookie_name: []const u8 = "_csrf_token",
    /// Name of the header to check for the token.
    header_name: []const u8 = "X-CSRF-Token",
    /// Name of the form field to check for the token.
    field_name: []const u8 = "csrf_token",
    /// Token byte length (hex-encoded, so output is 2x).
    token_bytes: u8 = 32,
    /// Methods that are exempt from CSRF validation (safe methods).
    safe_methods: []const std.http.Method = &.{ .GET, .HEAD, .OPTIONS, .TRACE },
    /// Cookie path.
    cookie_path: []const u8 = "/",
    /// Cookie secure flag.
    cookie_secure: bool = false,
    /// Cookie SameSite.
    cookie_same_site: enum { strict, lax, none } = .lax,
};

var global_options: CsrfOptions = .{};

pub fn configure(options: CsrfOptions) void {
    global_options = options;
}

fn isSafeMethod(method: std.http.Method) bool {
    for (global_options.safe_methods) |m| {
        if (method == m) return true;
    }
    return false;
}

fn generateToken(allocator: std.mem.Allocator) ![]u8 {
    var bytes: [32]u8 = undefined;
    std.crypto.random.bytes(&bytes);
    const hex = std.fmt.bytesToHex(bytes, .lower);
    return try allocator.dupe(u8, &hex);
}

/// Request hook: validate CSRF token for state-changing methods.
pub fn requestHook(req: *Request, allocator: std.mem.Allocator) !void {
    // Always generate a token and make it available via dependency
    const existing_cookie = req.header("cookie");
    var cookie_token: ?[]const u8 = null;

    if (existing_cookie) |cookies| {
        cookie_token = extractCookieValue(cookies, global_options.cookie_name);
    }

    if (cookie_token == null) {
        // Generate new token
        const token = try generateToken(allocator);
        defer allocator.free(token);
        try req.setDependencyValue("_csrf_token", token);
        try req.setDependencyValue("_csrf_new_cookie", "true");
    } else {
        try req.setDependencyValue("_csrf_token", cookie_token.?);
    }

    // Skip validation for safe methods
    if (isSafeMethod(req.method)) return;

    // For state-changing methods, validate the token
    const expected_token = cookie_token orelse {
        try req.setDependencyValue("_csrf_rejected", "true");
        return;
    };

    // Check header first, then form field
    const submitted_token = req.header(global_options.header_name) orelse
        req.queryParam(global_options.field_name) orelse
        {
            try req.setDependencyValue("_csrf_rejected", "true");
            return;
        };

    if (!std.mem.eql(u8, expected_token, submitted_token)) {
        try req.setDependencyValue("_csrf_rejected", "true");
    }
}

/// Response hook: set CSRF cookie and reject if validation failed.
pub fn responseHook(req: *Request, response: *Response, allocator: std.mem.Allocator) !void {
    // Set cookie if it's a new token
    if (req.dependency("_csrf_new_cookie")) |_| {
        const token = req.dependency("_csrf_token") orelse return;
        const same_site_str: []const u8 = switch (global_options.cookie_same_site) {
            .strict => "Strict",
            .lax => "Lax",
            .none => "None",
        };
        const cookie = try std.fmt.allocPrint(
            allocator,
            "{s}={s}; Path={s}; SameSite={s}{s}",
            .{
                global_options.cookie_name,
                token,
                global_options.cookie_path,
                same_site_str,
                if (global_options.cookie_secure) "; Secure" else "",
            },
        );
        defer allocator.free(cookie);
        try response.setHeader(allocator, "Set-Cookie", cookie);
    }

    // Reject if CSRF validation failed
    if (req.dependency("_csrf_rejected")) |_| {
        response.status = .forbidden;
        response.body = "{\"detail\":\"CSRF token missing or invalid\"}";
        response.content_type = "application/json";
    }
}

fn extractCookieValue(cookies: []const u8, name: []const u8) ?[]const u8 {
    var iter = std.mem.splitSequence(u8, cookies, "; ");
    while (iter.next()) |pair| {
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
            const key = std.mem.trim(u8, pair[0..eq], " ");
            if (std.mem.eql(u8, key, name)) {
                return pair[eq + 1 ..];
            }
        }
    }
    return null;
}

/// Create a Middleware struct ready to register with the app.
pub fn middleware(options: CsrfOptions) @import("../core/app.zig").App.Middleware {
    configure(options);
    return .{
        .name = "csrf",
        .request_hook = &requestHook,
        .response_hook = &responseHook,
    };
}
