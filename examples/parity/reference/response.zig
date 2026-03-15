const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/response/";

/// Demonstrates Response.json -- the most common response type.
fn jsonResponse(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .type = "json",
        .message = "Response.json(allocator, value) serializes any struct to JSON",
    });
}

/// Demonstrates Response.text -- plain text response.
fn textResponse(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return zigmund.Response.text("Response.text(body) returns plain text with text/plain content-type");
}

/// Demonstrates Response.html -- HTML response.
fn htmlResponse(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return zigmund.Response.html(
        "<h1>Response.html</h1><p>Returns text/html content-type</p>",
    );
}

/// Demonstrates Response.redirect.
fn redirectResponse(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.redirect(allocator, "/reference/response", .temporary_redirect);
}

/// Demonstrates Response.eventStream (SSE).
fn sseResponse(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.eventStream(allocator, &.{
        .{ .id = "1", .event = "update", .data = "first event" },
        .{ .id = "2", .event = "update", .data = "second event" },
    });
}

/// Demonstrates Response.withStatus and setHeader.
fn customStatusResponse(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var response = try zigmund.Response.json(allocator, .{
        .page = source_page,
        .detail = "created with custom status and header",
    });
    response = response.withStatus(.created);
    try response.setHeader(allocator, "x-custom", "reference-example");
    return response;
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/response", jsonResponse, .{
        .summary = "Response.json example",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_response_json",
    });
    try app.get("/reference/response/text", textResponse, .{
        .summary = "Response.text example",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_response_text",
    });
    try app.get("/reference/response/html", htmlResponse, .{
        .summary = "Response.html example",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_response_html",
    });
    try app.get("/reference/response/redirect", redirectResponse, .{
        .summary = "Response.redirect example",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_response_redirect",
    });
    try app.get("/reference/response/sse", sseResponse, .{
        .summary = "Response.eventStream (SSE) example",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_response_sse",
    });
    try app.post("/reference/response/custom", customStatusResponse, .{
        .summary = "Response.withStatus and setHeader example",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_response_custom",
        .status_code = .created,
    });
}
