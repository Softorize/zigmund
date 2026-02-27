const std = @import("std");
const zigmund = @import("zigmund");

fn bearerScopedDependency(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;

    const bearer = zigmund.HTTPBearer{};
    const credentials = (try bearer.resolve(req)) orelse return null;

    const raw_scopes = req.header("x-scopes") orelse "";
    try zigmund.security.setGrantedScopesRaw(req, raw_scopes);
    return credentials.credentials;
}

fn securedHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

test "route dependency security scopes enforce insufficient_scope with bearer challenge" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "security-scope",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("authz", bearerScopedDependency);
    try app.addSecurityScheme("authz", .{
        .oauth2 = .{
            .flows = .{
                .password = .{
                    .token_url = "/token",
                    .scopes = &.{
                        .{ .name = "items:read" },
                        .{ .name = "items:write" },
                    },
                },
            },
        },
    });

    try app.get("/secure", securedHandler, .{
        .dependencies = &.{.{
            .name = "authz",
            .scopes = &.{"items:write"},
        }},
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var unauthorized = try client.get("/secure");
    defer unauthorized.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unauthorized, unauthorized.status);
    try std.testing.expectEqualStrings("Bearer", unauthorized.header("www-authenticate").?);

    var insufficient = try client.requestWithHeaders(.GET, "/secure", "", &.{
        .{ .name = "authorization", .value = "Bearer token-1" },
        .{ .name = "x-scopes", .value = "items:read" },
    });
    defer insufficient.deinit(std.testing.allocator);

    try std.testing.expectEqual(.forbidden, insufficient.status);
    try std.testing.expect(insufficient.header("www-authenticate") != null);
    try std.testing.expect(std.mem.indexOf(u8, insufficient.header("www-authenticate").?, "insufficient_scope") != null);
    try std.testing.expect(std.mem.indexOf(u8, insufficient.header("www-authenticate").?, "items:write") != null);

    var ok = try client.requestWithHeaders(.GET, "/secure", "", &.{
        .{ .name = "authorization", .value = "Bearer token-2" },
        .{ .name = "x-scopes", .value = "items:read items:write" },
    });
    defer ok.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, ok.status);
}

test "oauth2 password request form helper parses valid form and rejects invalid grant type" {
    var good_req = try zigmund.Request.initSyntheticWithHeaders(
        std.testing.allocator,
        .POST,
        "/token",
        "username=alice&password=secret&scope=items%3Aread+profile%3Aread&grant_type=password&client_id=spa-client&client_secret=topsecret",
        &.{.{
            .name = "content-type",
            .value = "application/x-www-form-urlencoded",
        }},
    );
    defer good_req.deinit();

    const form = try zigmund.security.parseOAuth2PasswordRequestForm(&good_req);
    try std.testing.expectEqualStrings("alice", form.username);
    try std.testing.expectEqualStrings("secret", form.password);
    try std.testing.expectEqualStrings("items:read profile:read", form.scope);
    try std.testing.expectEqualStrings("password", form.grant_type);
    try std.testing.expectEqualStrings("spa-client", form.client_id.?);
    try std.testing.expectEqualStrings("topsecret", form.client_secret.?);

    var bad_req = try zigmund.Request.initSyntheticWithHeaders(
        std.testing.allocator,
        .POST,
        "/token",
        "username=alice&password=secret&grant_type=client_credentials",
        &.{.{
            .name = "content-type",
            .value = "application/x-www-form-urlencoded",
        }},
    );
    defer bad_req.deinit();

    try std.testing.expectError(
        error.InvalidGrantType,
        zigmund.security.parseOAuth2PasswordRequestForm(&bad_req),
    );
    try std.testing.expect(bad_req.validationIssues().len > 0);
    try std.testing.expectEqualStrings("invalid_grant_type", bad_req.validationIssues()[0].issue_type);
}

test "oauth2 bearer helpers resolve client-credentials implicit authorization-code and openid consistently" {
    var req = try zigmund.Request.initSyntheticWithHeaders(
        std.testing.allocator,
        .GET,
        "/secure",
        "",
        &.{.{
            .name = "authorization",
            .value = "Bearer tok-client-1",
        }},
    );
    defer req.deinit();

    const client_credentials = zigmund.OAuth2ClientCredentialsBearer{
        .token_url = "/token",
        .scopes = &.{"items:read"},
    };
    const implicit = zigmund.OAuth2ImplicitBearer{
        .authorization_url = "/authorize",
        .scopes = &.{"items:read"},
    };
    const authorization_code = zigmund.OAuth2AuthorizationCodeBearer{
        .authorization_url = "/authorize",
        .token_url = "/token",
        .scopes = &.{"items:read"},
    };
    const openid = zigmund.OpenIdConnect{
        .openid_connect_url = "https://issuer.example/.well-known/openid-configuration",
    };

    try std.testing.expectEqualStrings("tok-client-1", (try client_credentials.resolve(&req)).?);
    try std.testing.expectEqualStrings("tok-client-1", (try implicit.resolve(&req)).?);
    try std.testing.expectEqualStrings("tok-client-1", (try authorization_code.resolve(&req)).?);
    try std.testing.expectEqualStrings("tok-client-1", (try openid.resolve(&req)).?);

    var missing_auth_req = try zigmund.Request.initSynthetic(std.testing.allocator, .GET, "/secure", "");
    defer missing_auth_req.deinit();

    const no_auto_error = zigmund.OAuth2ClientCredentialsBearer{
        .token_url = "/token",
        .auto_error = false,
    };
    try std.testing.expect((try no_auto_error.resolve(&missing_auth_req)) == null);

    const openid_no_auto_error = zigmund.OpenIdConnect{
        .openid_connect_url = "https://issuer.example/.well-known/openid-configuration",
        .auto_error = false,
    };
    try std.testing.expect((try openid_no_auto_error.resolve(&missing_auth_req)) == null);

    const auth_code_no_auto_error = zigmund.OAuth2AuthorizationCodeBearer{
        .authorization_url = "/authorize",
        .token_url = "/token",
        .auto_error = false,
    };
    try std.testing.expect((try auth_code_no_auto_error.resolve(&missing_auth_req)) == null);
}

test "api key helpers resolve query header and cookie credentials with auto_error parity" {
    var req = try zigmund.Request.initSyntheticWithHeaders(
        std.testing.allocator,
        .GET,
        "/secure?api_key=q-key-1",
        "",
        &.{
            .{ .name = "x-api-key", .value = "h-key-1" },
            .{ .name = "cookie", .value = "session=sess-1; api_key=c-key-1" },
        },
    );
    defer req.deinit();

    const query = zigmund.APIKeyQuery{ .name = "api_key" };
    const header = zigmund.APIKeyHeader{ .name = "x-api-key" };
    const cookie = zigmund.APIKeyCookie{ .name = "api_key" };

    try std.testing.expectEqualStrings("q-key-1", (try query.resolve(&req)).?);
    try std.testing.expectEqualStrings("h-key-1", (try header.resolve(&req)).?);
    try std.testing.expectEqualStrings("c-key-1", (try cookie.resolve(&req)).?);

    var missing_req = try zigmund.Request.initSynthetic(std.testing.allocator, .GET, "/secure", "");
    defer missing_req.deinit();

    try std.testing.expectError(error.Unauthorized, query.resolve(&missing_req));
    try std.testing.expectError(error.Unauthorized, header.resolve(&missing_req));
    try std.testing.expectError(error.Unauthorized, cookie.resolve(&missing_req));

    const query_no_error = zigmund.APIKeyQuery{ .name = "api_key", .auto_error = false };
    const header_no_error = zigmund.APIKeyHeader{ .name = "x-api-key", .auto_error = false };
    const cookie_no_error = zigmund.APIKeyCookie{ .name = "api_key", .auto_error = false };
    try std.testing.expect((try query_no_error.resolve(&missing_req)) == null);
    try std.testing.expect((try header_no_error.resolve(&missing_req)) == null);
    try std.testing.expect((try cookie_no_error.resolve(&missing_req)) == null);
}
