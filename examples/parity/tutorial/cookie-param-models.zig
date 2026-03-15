const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/cookie-param-models/";

const CookieContext = struct {
    session_id: ?[]const u8 = null,
    theme: []const u8 = "light",
};

fn implemented(
    cookies: zigmund.Cookie(CookieContext, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .cookies = cookies.value.?,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/cookie-param-models", implemented, .{
        .summary = "Parity implementation for tutorial/cookie-param-models/",
        .tags = &.{ "parity", "tutorial" },
    });
}
