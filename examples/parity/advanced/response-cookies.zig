const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/response-cookies/";

fn setCookies(allocator: std.mem.Allocator) !zigmund.Response {
    var response = try zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .message = "Cookies have been set",
    });
    try response.setCookie(allocator, "session_id", "abc-123-def", .{
        .path = "/",
        .http_only = true,
        .secure = true,
        .same_site = .lax,
        .max_age_seconds = 3600,
    });
    try response.setCookie(allocator, "preferences", "dark-mode", .{
        .path = "/",
        .http_only = false,
        .secure = false,
        .max_age_seconds = 86400 * 30,
    });
    return response;
}

fn deleteCookie(allocator: std.mem.Allocator) !zigmund.Response {
    var response = try zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .message = "Cookie deleted",
    });
    try response.deleteCookie(allocator, "session_id", .{});
    return response;
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/response-cookies/set", setCookies, .{
        .summary = "Set response cookies with various options",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_response_cookies_set",
    });
    try app.get("/advanced/response-cookies/delete", deleteCookie, .{
        .summary = "Delete a response cookie",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_response_cookies_delete",
    });
}
