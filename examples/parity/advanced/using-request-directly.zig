const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/using-request-directly/";

/// Demonstrates direct access to the raw Request object.
/// The handler receives *zigmund.Request as a parameter and can inspect
/// method, path, query, headers, body, and other request properties.
fn directRequestAccess(
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user_agent = req.header("user-agent") orelse "unknown";
    const content_type = req.header("content-type") orelse "none";
    const custom_header = req.header("x-custom") orelse "not set";

    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .method = @tagName(req.method),
        .path = req.path,
        .query = req.query,
        .body_length = req.body.len,
        .user_agent = user_agent,
        .content_type = content_type,
        .custom_header = custom_header,
        .message = "Direct request object access",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/using-request-directly", directRequestAccess, .{
        .summary = "Direct request object access for headers, path, query, and body",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_using_request_directly",
    });

    // Also register POST to demonstrate body access
    try app.post("/advanced/using-request-directly", directRequestAccess, .{
        .summary = "Direct request object access (POST with body)",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_using_request_directly_post",
    });
}
