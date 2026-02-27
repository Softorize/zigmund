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

fn customUnauthorizedHandler(req: *const zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var res = zigmund.Response.text("custom unauthorized").withStatus(.unauthorized);
    try res.setHeader(allocator, "x-auth-handler", "unauthorized");
    return res;
}

fn customInsufficientScopeHandler(req: *const zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var res = zigmund.Response.text("custom insufficient_scope").withStatus(.forbidden);
    try res.setHeader(allocator, "x-auth-handler", "insufficient_scope");
    return res;
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

test "api key auth failures return forbidden without bearer challenge headers" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "unauthorized-api-key",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("api_key_auth", authDependency);
    try app.addSecurityScheme("api_key_auth", .{
        .api_key = .{
            .name = "x-api-key",
            .in = .header,
        },
    });
    try app.get("/api-key-protected", protected, .{
        .dependencies = &.{.{ .name = "api_key_auth" }},
    });

    try app.addDependency("api_key_scope", scopeFailDependency);
    try app.addSecurityScheme("api_key_scope", .{
        .api_key = .{
            .name = "api_key",
            .in = .query,
        },
    });
    try app.get("/api-key-scope", protected, .{
        .dependencies = &.{.{
            .name = "api_key_scope",
            .scopes = &.{"admin"},
        }},
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var unauthorized = try client.get("/api-key-protected");
    defer unauthorized.deinit(std.testing.allocator);
    try std.testing.expectEqual(.forbidden, unauthorized.status);
    try std.testing.expect(unauthorized.header("www-authenticate") == null);

    var insufficient = try client.get("/api-key-scope");
    defer insufficient.deinit(std.testing.allocator);
    try std.testing.expectEqual(.forbidden, insufficient.status);
    try std.testing.expect(insufficient.header("www-authenticate") == null);
}

test "custom auth failure handlers override default unauthorized and insufficient-scope responses" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "custom-auth-failures",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.setUnauthorizedHandler(customUnauthorizedHandler);
    app.setInsufficientScopeHandler(customInsufficientScopeHandler);

    try app.addDependency("auth", authDependency);
    try app.get("/unauthorized", protected, .{
        .dependencies = &.{.{ .name = "auth" }},
    });

    try app.addDependency("scope", scopeFailDependency);
    try app.get("/insufficient", protected, .{
        .dependencies = &.{.{
            .name = "scope",
            .scopes = &.{"admin"},
        }},
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var unauthorized = try client.get("/unauthorized");
    defer unauthorized.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unauthorized, unauthorized.status);
    try std.testing.expectEqualStrings("custom unauthorized", unauthorized.body);
    try std.testing.expectEqualStrings("unauthorized", unauthorized.header("x-auth-handler").?);
    try std.testing.expect(unauthorized.header("www-authenticate") == null);

    var insufficient = try client.get("/insufficient");
    defer insufficient.deinit(std.testing.allocator);
    try std.testing.expectEqual(.forbidden, insufficient.status);
    try std.testing.expectEqualStrings("custom insufficient_scope", insufficient.body);
    try std.testing.expectEqualStrings("insufficient_scope", insufficient.header("x-auth-handler").?);
    try std.testing.expect(insufficient.header("www-authenticate") == null);
}
