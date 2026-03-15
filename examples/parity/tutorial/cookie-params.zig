const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/cookie-params/";

fn readSessionCookie(
    session_id: zigmund.Cookie([]const u8, .{ .alias = "session_id", .description = "Browser session cookie" }),
    ads_id: zigmund.Cookie([]const u8, .{ .alias = "ads_id", .description = "Advertising tracking cookie" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .session_id = session_id.value orelse "not set",
        .ads_id = ads_id.value orelse "not set",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/cookie-params", readSessionCookie, .{
        .summary = "Extract values from request cookies",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_read_session_cookie",
    });
}
