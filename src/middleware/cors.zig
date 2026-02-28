const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const CorsOptions = struct {
    allowed_origins: []const []const u8 = &.{"*"},
    allowed_methods: []const []const u8 = &.{ "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD" },
    allowed_headers: []const []const u8 = &.{ "Content-Type", "Authorization", "Accept", "Origin", "X-Requested-With" },
    expose_headers: []const []const u8 = &.{},
    allow_credentials: bool = false,
    max_age: u32 = 86400,

    fn isOriginAllowed(self: CorsOptions, origin: []const u8) bool {
        for (self.allowed_origins) |allowed| {
            if (std.mem.eql(u8, allowed, "*") or std.mem.eql(u8, allowed, origin)) return true;
        }
        return false;
    }
};

var global_options: CorsOptions = .{};

pub fn configure(options: CorsOptions) void {
    global_options = options;
}

/// Request hook: handle OPTIONS preflight with 204 short-circuit.
pub fn requestHook(req: *Request, allocator: std.mem.Allocator) !void {
    const origin = req.header("origin") orelse return;

    if (!global_options.isOriginAllowed(origin)) return;

    // Store origin for response hook
    try req.setDependencyValue("_cors_origin", origin);

    // Check if this is a preflight request
    if (req.method == .OPTIONS) {
        const request_method = req.header("access-control-request-method");
        if (request_method != null) {
            // This is a preflight — mark for 204 response
            try req.setDependencyValue("_cors_preflight", "true");
        }
    }
    _ = allocator;
}

/// Response hook: add CORS headers to all responses.
pub fn responseHook(req: *Request, response: *Response, allocator: std.mem.Allocator) !void {
    const origin = req.dependency("_cors_origin") orelse return;

    // Add CORS headers
    if (global_options.allow_credentials) {
        try response.setHeader(allocator, "Access-Control-Allow-Origin", origin);
        try response.setHeader(allocator, "Access-Control-Allow-Credentials", "true");
    } else {
        // If wildcard is in allowed_origins, send *
        var use_wildcard = false;
        for (global_options.allowed_origins) |allowed| {
            if (std.mem.eql(u8, allowed, "*")) {
                use_wildcard = true;
                break;
            }
        }
        if (use_wildcard) {
            try response.setHeader(allocator, "Access-Control-Allow-Origin", "*");
        } else {
            try response.setHeader(allocator, "Access-Control-Allow-Origin", origin);
        }
    }

    // Vary header
    try response.setHeader(allocator, "Vary", "Origin");

    // Expose headers
    if (global_options.expose_headers.len > 0) {
        const expose = try joinStrings(allocator, global_options.expose_headers, ", ");
        defer allocator.free(expose);
        try response.setHeader(allocator, "Access-Control-Expose-Headers", expose);
    }

    // Preflight-specific headers
    if (req.dependency("_cors_preflight")) |_| {
        const methods = try joinStrings(allocator, global_options.allowed_methods, ", ");
        defer allocator.free(methods);
        try response.setHeader(allocator, "Access-Control-Allow-Methods", methods);

        const headers_str = try joinStrings(allocator, global_options.allowed_headers, ", ");
        defer allocator.free(headers_str);
        try response.setHeader(allocator, "Access-Control-Allow-Headers", headers_str);

        var max_age_buf: [20]u8 = undefined;
        const max_age = std.fmt.bufPrint(&max_age_buf, "{d}", .{global_options.max_age}) catch "86400";
        try response.setHeader(allocator, "Access-Control-Max-Age", max_age);

        // Short-circuit: 204 No Content for preflight
        response.status = .no_content;
        response.body = "";
    }
}

fn joinStrings(allocator: std.mem.Allocator, strings: []const []const u8, sep: []const u8) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    for (strings, 0..) |s, i| {
        if (i > 0) try buf.appendSlice(allocator, sep);
        try buf.appendSlice(allocator, s);
    }
    return buf.toOwnedSlice(allocator);
}

/// Create a Middleware struct ready to register with the app.
pub fn middleware(options: CorsOptions) @import("../core/app.zig").App.Middleware {
    configure(options);
    return .{
        .name = "cors",
        .request_hook = &requestHook,
        .response_hook = &responseHook,
    };
}
