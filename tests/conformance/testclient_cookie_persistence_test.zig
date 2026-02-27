const std = @import("std");
const zigmund = @import("zigmund");

fn login(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    var response = zigmund.Response.text("logged-in");
    try response.setCookie(allocator, "session", "abc123", .{
        .path = "/",
        .http_only = true,
        .same_site = .lax,
    });
    return response;
}

fn logout(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    var response = zigmund.Response.text("logged-out");
    try response.deleteCookie(allocator, "session", .{
        .path = "/",
    });
    return response;
}

fn currentSession(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .session = req.cookie("session") orelse "",
    });
}

test "TestClient persists cookies from Set-Cookie and applies deletions" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "testclient-cookies",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/login", login, .{});
    try app.post("/logout", logout, .{});
    try app.get("/session", currentSession, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var before = try client.get("/session");
    defer before.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, before.body, "\"session\":\"\"") != null);

    var login_res = try client.post("/login", "");
    defer login_res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, login_res.status);

    var after_login = try client.get("/session");
    defer after_login.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, after_login.body, "\"session\":\"abc123\"") != null);

    var logout_res = try client.post("/logout", "");
    defer logout_res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, logout_res.status);

    var after_logout = try client.get("/session");
    defer after_logout.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, after_logout.body, "\"session\":\"\"") != null);
}
