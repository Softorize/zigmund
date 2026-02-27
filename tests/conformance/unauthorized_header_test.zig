const std = @import("std");
const zigmund = @import("zigmund");

fn authDependency(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    return error.Unauthorized;
}

fn protected(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

fn securityProvider(req: *zigmund.Request) ?[]const u8 {
    _ = req;
    return null;
}

fn securityProtected(
    auth: zigmund.Security(securityProvider, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .auth = auth.value,
    });
}

test "unauthorized responses include WWW-Authenticate header" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "unauthorized-header",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("auth", authDependency);
    try app.get("/dependency-protected", protected, .{
        .dependencies = &.{.{ .name = "auth" }},
    });
    try app.get("/security-protected", securityProtected, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var dep_res = try client.get("/dependency-protected");
    defer dep_res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unauthorized, dep_res.status);
    try std.testing.expectEqualStrings("Bearer", dep_res.header("www-authenticate").?);

    var security_res = try client.get("/security-protected");
    defer security_res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unauthorized, security_res.status);
    try std.testing.expectEqualStrings("Bearer", security_res.header("www-authenticate").?);
}

test "unauthorized challenge matches configured HTTP security scheme" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "unauthorized-basic",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("basic_auth", authDependency);
    try app.addSecurityScheme("basic_auth", .{
        .http = .{
            .scheme = "basic",
        },
    });

    try app.get("/basic-protected", protected, .{
        .dependencies = &.{.{ .name = "basic_auth" }},
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var res = try client.get("/basic-protected");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.unauthorized, res.status);
    try std.testing.expectEqualStrings("Basic", res.header("www-authenticate").?);
}
