const std = @import("std");
const zigmund = @import("zigmund");

fn protected(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

fn wsAuthProvider(req: *zigmund.Request) ?[]const u8 {
    return req.queryParam("token");
}

fn wsProtected(
    conn: *zigmund.runtime.websocket.Connection,
    auth: zigmund.SecurityNamed(wsAuthProvider, "auth", &.{"items:read"}),
    allocator: std.mem.Allocator,
) !void {
    _ = conn;
    _ = auth;
    _ = allocator;
}

test "openapi exposes configured security schemes and route security" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "security",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addSecurityScheme("auth", .{ .http = .{ .scheme = "bearer", .bearer_format = "JWT" } });

    try app.get("/secure", protected, .{
        .dependencies = &.{.{ .name = "auth", .scopes = &.{"items:read"} }},
    });

    const doc = try app.openapi();

    try std.testing.expect(std.mem.indexOf(u8, doc, "\"securitySchemes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"auth\":{\"type\":\"http\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"security\":[{\"auth\":[\"items:read\"]}]") != null);
}

test "openapi exposes openid connect security schemes and route security" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "security-openid",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addSecurityScheme("oidc_auth", .{
        .openid_connect = .{
            .openid_connect_url = "https://issuer.example/.well-known/openid-configuration",
        },
    });

    try app.get("/oidc-secure", protected, .{
        .dependencies = &.{.{ .name = "oidc_auth" }},
    });

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"oidc_auth\":{\"type\":\"openIdConnect\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"openIdConnectUrl\":\"https://issuer.example/.well-known/openid-configuration\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"security\":[{\"oidc_auth\":[]}]") != null);
}

test "openapi exposes oauth2 flows for implicit password client-credentials and authorization-code" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "security-oauth2-flows",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addSecurityScheme("oauth_auth", .{
        .oauth2 = .{
            .flows = .{
                .implicit = .{
                    .authorization_url = "https://issuer.example/oauth/authorize",
                    .refresh_url = "https://issuer.example/oauth/refresh",
                    .scopes = &.{.{ .name = "items:read" }},
                },
                .password = .{
                    .token_url = "https://issuer.example/oauth/token",
                    .scopes = &.{.{ .name = "items:write" }},
                },
                .client_credentials = .{
                    .token_url = "https://issuer.example/oauth/token",
                    .scopes = &.{.{ .name = "items:admin" }},
                },
                .authorization_code = .{
                    .authorization_url = "https://issuer.example/oauth/authorize",
                    .token_url = "https://issuer.example/oauth/token",
                    .refresh_url = "https://issuer.example/oauth/refresh",
                    .scopes = &.{.{ .name = "items:sync" }},
                },
            },
        },
    });

    try app.get("/oauth-secure", protected, .{
        .dependencies = &.{.{ .name = "oauth_auth", .scopes = &.{"items:read"} }},
    });

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"oauth_auth\":{\"type\":\"oauth2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"implicit\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"password\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"clientCredentials\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"authorizationCode\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"authorizationUrl\":\"https://issuer.example/oauth/authorize\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"tokenUrl\":\"https://issuer.example/oauth/token\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"refreshUrl\":\"https://issuer.example/oauth/refresh\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"security\":[{\"oauth_auth\":[\"items:read\"]}]") != null);
}

test "openapi exposes api key security schemes for query header and cookie" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "security-api-key-schemes",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addSecurityScheme("key_query", .{
        .api_key = .{
            .name = "api_key",
            .in = .query,
        },
    });
    try app.addSecurityScheme("key_header", .{
        .api_key = .{
            .name = "x-api-key",
            .in = .header,
        },
    });
    try app.addSecurityScheme("key_cookie", .{
        .api_key = .{
            .name = "session",
            .in = .cookie,
        },
    });

    try app.get("/query-secure", protected, .{
        .dependencies = &.{.{ .name = "key_query" }},
    });
    try app.get("/header-secure", protected, .{
        .dependencies = &.{.{ .name = "key_header" }},
    });
    try app.get("/cookie-secure", protected, .{
        .dependencies = &.{.{ .name = "key_cookie" }},
    });

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"key_query\":{\"type\":\"apiKey\",\"name\":\"api_key\",\"in\":\"query\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"key_header\":{\"type\":\"apiKey\",\"name\":\"x-api-key\",\"in\":\"header\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"key_cookie\":{\"type\":\"apiKey\",\"name\":\"session\",\"in\":\"cookie\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"security\":[{\"key_query\":[]}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"security\":[{\"key_header\":[]}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"security\":[{\"key_cookie\":[]}]") != null);
}

test "openapi route security combines multiple schemes as AND and merges duplicate scopes" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "security-and-merge",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addSecurityScheme("auth_a", .{ .http = .{ .scheme = "bearer" } });
    try app.addSecurityScheme("auth_b", .{
        .api_key = .{
            .name = "x-api-key",
            .in = .header,
        },
    });

    try app.get("/secure-both", protected, .{
        .dependencies = &.{
            .{ .name = "auth_a", .scopes = &.{"items:read"} },
            .{ .name = "auth_b" },
            .{ .name = "auth_a", .scopes = &.{"items:write"} },
        },
    });

    const doc = try app.openapi();
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            doc,
            "\"security\":[{\"auth_a\":[\"items:read\",\"items:write\"],\"auth_b\":[]}]",
        ) != null,
    );
}

test "openapi deterministic mode sorts security schemes by name" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "security-order",
        .version = "0.0.1",
        .openapi_deterministic = true,
    });
    defer app.deinit();

    try app.addSecurityScheme("zeta", .{ .http = .{ .scheme = "bearer" } });
    try app.addSecurityScheme("alpha", .{ .http = .{ .scheme = "basic" } });
    try app.addSecurityScheme("mid", .{ .api_key = .{ .name = "x-mid", .in = .header } });

    const doc = try app.openapi();
    const alpha_idx = std.mem.indexOf(u8, doc, "\"alpha\":") orelse return error.TestUnexpectedResult;
    const mid_idx = std.mem.indexOf(u8, doc, "\"mid\":") orelse return error.TestUnexpectedResult;
    const zeta_idx = std.mem.indexOf(u8, doc, "\"zeta\":") orelse return error.TestUnexpectedResult;

    try std.testing.expect(alpha_idx < mid_idx);
    try std.testing.expect(mid_idx < zeta_idx);
}

test "openapi exposes websocket injected security dependencies" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "security-websocket",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addSecurityScheme("auth", .{ .http = .{ .scheme = "bearer", .bearer_format = "JWT" } });
    try app.websocket("/ws-secure", wsProtected, .{});

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"x-zigmund-websocket\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"dependencies\":[{\"name\":\"auth\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"security\":[{\"auth\":[\"items:read\"]}]") != null);
}
