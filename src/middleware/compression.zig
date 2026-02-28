const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const c = @cImport(@cInclude("zlib.h"));

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
    _ = allocator;
    if (acceptsGzip(req)) {
        try req.setDependencyValue("_compression_encoding", "gzip");
    } else if (acceptsDeflate(req)) {
        try req.setDependencyValue("_compression_encoding", "deflate");
    }
}

/// Response hook: compress the response body if eligible.
pub fn responseHook(req: *Request, response: *Response, allocator: std.mem.Allocator) !void {
    const encoding = req.dependency("_compression_encoding") orelse return;

    // Skip if body is too small
    if (response.body.len < global_options.min_size) return;

    // Skip if content type is not compressible
    if (!isCompressible(response.content_type)) return;

    // Skip if already encoded
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "content-encoding")) return;
    }

    const is_gzip = std.mem.eql(u8, encoding, "gzip");

    const compressed_body = if (is_gzip)
        gzipCompress(allocator, response.body, global_options.level) catch return
    else
        deflateCompress(allocator, response.body, global_options.level) catch return;

    // Only use compressed version if it's actually smaller
    if (compressed_body.len >= response.body.len) {
        allocator.free(compressed_body);
        return;
    }

    if (response.owned_body) |owned| allocator.free(owned);
    response.body = compressed_body;
    response.owned_body = compressed_body;
    try response.setHeader(allocator, "Content-Encoding", if (is_gzip) "gzip" else "deflate");
    try response.setHeader(allocator, "Vary", "Accept-Encoding");
}

/// Compress data using gzip format via C zlib.
fn gzipCompress(allocator: std.mem.Allocator, input: []const u8, level: u4) ![]u8 {
    var stream: c.z_stream = std.mem.zeroes(c.z_stream);
    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);

    // windowBits = 15 + 16 enables gzip wrapper
    if (c.deflateInit2(&stream, @as(c_int, @intCast(level)), c.Z_DEFLATED, 15 + 16, 8, c.Z_DEFAULT_STRATEGY) != c.Z_OK)
        return error.ZlibInitFailed;

    const bound: usize = @intCast(c.deflateBound(&stream, @intCast(input.len)));
    const buf = try allocator.alloc(u8, bound);
    errdefer allocator.free(buf);

    stream.next_out = buf.ptr;
    stream.avail_out = @intCast(buf.len);

    if (c.deflate(&stream, c.Z_FINISH) != c.Z_STREAM_END) {
        _ = c.deflateEnd(&stream);
        return error.ZlibCompressFailed;
    }
    _ = c.deflateEnd(&stream);

    const written: usize = @intCast(stream.total_out);
    const exact = try allocator.alloc(u8, written);
    @memcpy(exact, buf[0..written]);
    allocator.free(buf);
    return exact;
}

/// Compress data using deflate (zlib-wrapped) format via C zlib.
fn deflateCompress(allocator: std.mem.Allocator, input: []const u8, level: u4) ![]u8 {
    var stream: c.z_stream = std.mem.zeroes(c.z_stream);
    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);

    // windowBits = 15 for standard zlib/deflate format
    if (c.deflateInit2(&stream, @as(c_int, @intCast(level)), c.Z_DEFLATED, 15, 8, c.Z_DEFAULT_STRATEGY) != c.Z_OK)
        return error.ZlibInitFailed;

    const bound: usize = @intCast(c.deflateBound(&stream, @intCast(input.len)));
    const buf = try allocator.alloc(u8, bound);
    errdefer allocator.free(buf);

    stream.next_out = buf.ptr;
    stream.avail_out = @intCast(buf.len);

    if (c.deflate(&stream, c.Z_FINISH) != c.Z_STREAM_END) {
        _ = c.deflateEnd(&stream);
        return error.ZlibCompressFailed;
    }
    _ = c.deflateEnd(&stream);

    const written: usize = @intCast(stream.total_out);
    const exact = try allocator.alloc(u8, written);
    @memcpy(exact, buf[0..written]);
    allocator.free(buf);
    return exact;
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
