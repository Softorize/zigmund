const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/response-directly/";

fn directText() zigmund.Response {
    return zigmund.Response.text("Hello, this is a direct text response");
}

fn directJson(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .message = "This JSON was returned directly, not through a response model",
    });
}

fn directHtml() zigmund.Response {
    return zigmund.Response.html(
        \\<html><body><p>Direct HTML response, bypassing response_model</p></body></html>
    );
}

fn directWithStatus(allocator: std.mem.Allocator) !zigmund.Response {
    return (try zigmund.Response.json(allocator, .{
        .detail = "Resource has been created directly",
    })).withStatus(.created);
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/response-directly/text", directText, .{
        .summary = "Return a direct text response (no response model)",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_response_directly_text",
    });
    try app.get("/advanced/response-directly/json", directJson, .{
        .summary = "Return a direct JSON response (no response model)",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_response_directly_json",
    });
    try app.get("/advanced/response-directly/html", directHtml, .{
        .summary = "Return a direct HTML response (no response model)",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_response_directly_html",
    });
    try app.post("/advanced/response-directly/create", directWithStatus, .{
        .summary = "Return a direct response with custom status code",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_response_directly_with_status",
        .status_code = .created,
    });
}
