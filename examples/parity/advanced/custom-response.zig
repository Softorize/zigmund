const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/custom-response/";

fn htmlResponse() zigmund.Response {
    return zigmund.Response.html(
        \\<html><body><h1>Hello from Zigmund</h1></body></html>
    );
}

fn textResponse() zigmund.Response {
    return zigmund.Response.text("Plain text response from Zigmund");
}

fn redirectResponse(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.redirect(allocator, "/advanced/custom-response/html", .temporary_redirect);
}

fn jsonResponse(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .response_type = "json",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/custom-response/html", htmlResponse, .{
        .summary = "Return an HTML response",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_custom_response_html",
    });
    try app.get("/advanced/custom-response/text", textResponse, .{
        .summary = "Return a plain text response",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_custom_response_text",
    });
    try app.get("/advanced/custom-response/redirect", redirectResponse, .{
        .summary = "Return a redirect response",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_custom_response_redirect",
    });
    try app.get("/advanced/custom-response/json", jsonResponse, .{
        .summary = "Return a JSON response",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_custom_response_json",
    });
}
