const std = @import("std");
const zigmund = @import("zigmund");

fn authDependency(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    return error.Unauthorized;
}

fn scopeFailDependency(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    return error.InsufficientScope;
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
    const challenge = res.header("www-authenticate").?;
    try std.testing.expect(std.mem.startsWith(u8, challenge, "Basic"));
    try std.testing.expect(std.mem.indexOf(u8, challenge, "realm=\"zigmund\"") != null);
}

test "digest unauthorized and insufficient-scope challenges include digest auth details" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "unauthorized-digest",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("digest_auth", authDependency);
    try app.addSecurityScheme("digest_auth", .{
        .http = .{
            .scheme = "digest",
        },
    });

    try app.get("/digest-protected", protected, .{
        .dependencies = &.{.{ .name = "digest_auth" }},
    });

    try app.addDependency("digest_scope", scopeFailDependency);
    try app.addSecurityScheme("digest_scope", .{
        .http = .{
            .scheme = "digest",
        },
    });
    try app.get("/digest-scope", protected, .{
        .dependencies = &.{.{
            .name = "digest_scope",
            .scopes = &.{"read"},
        }},
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var unauthorized = try client.get("/digest-protected");
    defer unauthorized.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unauthorized, unauthorized.status);
    const unauthorized_challenge = unauthorized.header("www-authenticate").?;
    try std.testing.expect(std.mem.startsWith(u8, unauthorized_challenge, "Digest"));
    try std.testing.expect(std.mem.indexOf(u8, unauthorized_challenge, "realm=\"zigmund\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, unauthorized_challenge, "qop=\"auth\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, unauthorized_challenge, "algorithm=SHA-256") != null);

    var insufficient = try client.get("/digest-scope");
    defer insufficient.deinit(std.testing.allocator);
    try std.testing.expectEqual(.forbidden, insufficient.status);
    const insufficient_challenge = insufficient.header("www-authenticate").?;
    try std.testing.expect(std.mem.startsWith(u8, insufficient_challenge, "Digest"));
    try std.testing.expect(std.mem.indexOf(u8, insufficient_challenge, "insufficient_scope") == null);
}
