const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/response-headers/";

fn customHeaders(allocator: std.mem.Allocator) !zigmund.Response {
    var response = try zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .message = "Response includes custom headers",
    });
    try response.setHeader(allocator, "x-custom-header", "custom-value");
    try response.setHeader(allocator, "x-request-duration", "42ms");
    try response.setHeader(allocator, "x-api-version", "1.0.0");
    return response;
}

fn cacheHeaders(allocator: std.mem.Allocator) !zigmund.Response {
    var response = try zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .message = "Response includes cache-related headers",
    });
    try response.setHeader(allocator, "cache-control", "public, max-age=3600");
    try response.setEtag(allocator, "\"v1-abc123\"");
    try response.setLastModified(allocator, "Sat, 14 Mar 2026 12:00:00 GMT");
    return response;
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/response-headers/custom", customHeaders, .{
        .summary = "Return response with custom headers",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_response_headers_custom",
    });
    try app.get("/advanced/response-headers/cache", cacheHeaders, .{
        .summary = "Return response with cache-related headers",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_response_headers_cache",
    });
}
