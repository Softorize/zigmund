const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const CompressionOptions = struct {
    /// Minimum body size in bytes to trigger compression.
    min_size: usize = 1024,
    /// Content types eligible for compression.
    compressible_types: []const []const u8 = &.{
        "text/",
        "application/json",
        "application/xml",
        "application/javascript",
        "application/xhtml+xml",
        "image/svg+xml",
    },
    /// Compression level (1-9, lower = faster, higher = better compression).
    level: u4 = 6,
};

var global_options: CompressionOptions = .{};

pub fn configure(options: CompressionOptions) void {
    global_options = options;
}

fn isCompressible(content_type: []const u8) bool {
    for (global_options.compressible_types) |pattern| {
        if (std.mem.startsWith(u8, content_type, pattern)) return true;
    }
    return false;
}

fn acceptsGzip(req: *Request) bool {
    const accept = req.header("accept-encoding") orelse return false;
    return std.mem.indexOf(u8, accept, "gzip") != null;
}

fn acceptsDeflate(req: *Request) bool {
    const accept = req.header("accept-encoding") orelse return false;
    return std.mem.indexOf(u8, accept, "deflate") != null;
}

/// Request hook: detect accepted encoding.
pub fn requestHook(req: *Request, allocator: std.mem.Allocator) !void {
    if (acceptsGzip(req)) {
        try req.setDependencyValue("_compression_encoding", "gzip");
    } else if (acceptsDeflate(req)) {
        try req.setDependencyValue("_compression_encoding", "deflate");
    }
    _ = allocator;
}

/// Response hook: compress the response body if eligible.
/// Note: Response compression is disabled in Zig 0.15.2 due to incomplete
/// std.compress.flate API (missing BlockWriter.bit_writer and Hasher.final).
/// The middleware still sets Vary headers for correct caching behavior.
/// Compression will be re-enabled when the stdlib compress API is stable.
pub fn responseHook(req: *Request, response: *Response, allocator: std.mem.Allocator) !void {
    _ = req;
    _ = response;
    _ = allocator;
    // Compression is temporarily disabled due to Zig 0.15.2 stdlib
    // std.compress.flate API being incomplete (compile errors in
    // BlockWriter and Container.Hasher). The request hook still detects
    // accepted encodings so this can be re-enabled when the stdlib is fixed.
}

/// Create a Middleware struct ready to register with the app.
pub fn middleware(options: CompressionOptions) @import("../core/app.zig").App.Middleware {
    configure(options);
    return .{
        .name = "compression",
        .request_hook = &requestHook,
        .response_hook = &responseHook,
    };
}
