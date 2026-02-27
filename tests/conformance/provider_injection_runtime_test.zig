const std = @import("std");
const zigmund = @import("zigmund");

var cache_calls: usize = 0;
var no_cache_calls: usize = 0;
var tenant_calls: usize = 0;
var cleanup_provider_calls: usize = 0;
var cleanup_calls: usize = 0;
var cleanup_key_non_empty: bool = false;
var cleanup_value_matches: bool = false;

fn tokenProvider(req: *zigmund.Request) ?[]const u8 {
    return req.queryParam("token");
}

fn userProvider(
    req: *zigmund.Request,
    token_dep: zigmund.Depends(tokenProvider, .{ .name = "token_dep" }),
) !?[]const u8 {
    const token = token_dep.value orelse return null;
    if (std.mem.eql(u8, token, "secret")) {
        try zigmund.security.setGrantedScopes(req, &.{"items:read"});
        return "alice";
    }
    return null;
}

fn limitedUserProvider(
    req: *zigmund.Request,
    token_dep: zigmund.Depends(tokenProvider, .{ .name = "token_dep" }),
) !?[]const u8 {
    const token = token_dep.value orelse return null;
    if (std.mem.eql(u8, token, "secret")) {
        try zigmund.security.setGrantedScopes(req, &.{"profile:read"});
        return "alice";
    }
    return null;
}

fn nestedSecurityHandler(
    user: zigmund.SecurityNamed(userProvider, "auth", &.{"items:read"}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{ .user = user.value.? });
}

fn nestedMissingScopeHandler(
    user: zigmund.SecurityNamed(limitedUserProvider, "auth", &.{"items:write"}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{ .user = user.value.? });
}

fn cachedProvider(req: *zigmund.Request) ?[]const u8 {
    _ = req;
    cache_calls += 1;
    return "cached";
}

fn cacheHandler(
    one: zigmund.Depends(cachedProvider, .{ .name = "cache_dep" }),
    two: zigmund.Depends(cachedProvider, .{ .name = "cache_dep" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .one = one.value orelse "",
        .two = two.value orelse "",
    });
}

fn nonCachedProvider(req: *zigmund.Request) ?[]const u8 {
    _ = req;
    no_cache_calls += 1;
    return "fresh";
}

fn noCacheHandler(
    one: zigmund.Depends(nonCachedProvider, .{ .name = "fresh_dep", .use_cache = false }),
    two: zigmund.Depends(nonCachedProvider, .{ .name = "fresh_dep", .use_cache = false }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .one = one.value orelse "",
        .two = two.value orelse "",
    });
}

fn cleanupProvider(req: *zigmund.Request) ?[]const u8 {
    _ = req;
    cleanup_provider_calls += 1;
    return "resource";
}

fn cleanupHook(req: *zigmund.Request, key: []const u8, value: []const u8, allocator: std.mem.Allocator) !void {
    _ = req;
    _ = allocator;
    cleanup_calls += 1;
    cleanup_key_non_empty = key.len != 0;
    cleanup_value_matches = std.mem.eql(u8, value, "resource");
}

fn cleanupHandler(
    one: zigmund.Depends(cleanupProvider, .{ .cleanup = cleanupHook }),
    two: zigmund.Depends(cleanupProvider, .{ .cleanup = cleanupHook }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .one = one.value orelse "",
        .two = two.value orelse "",
    });
}

fn cleanupErrorHandler(
    dep: zigmund.Depends(cleanupProvider, .{ .cleanup = cleanupHook }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = dep;
    _ = allocator;
    return error.Outage;
}

fn tenantProvider(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    tenant_calls += 1;
    return req.queryParam("tenant") orelse "default";
}

fn tenantHandler(
    tenant: zigmund.Depends(tenantProvider, .{ .name = "tenant", .cache_scope = .app }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .tenant = tenant.value orelse "",
    });
}

fn optionalSecurityProvider(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    return req.queryParam("token");
}

fn optionalScopedSecurityProvider(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const token = req.queryParam("token") orelse return null;
    if (std.mem.eql(u8, token, "secret")) {
        try zigmund.security.setGrantedScopes(req, &.{"items:read"});
        return "alice";
    }
    return null;
}

fn optionalSecurityHandler(
    auth: zigmund.SecurityOptional(optionalSecurityProvider, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .auth = auth.value orelse "none",
    });
}

fn optionalScopedSecurityHandler(
    auth: zigmund.SecurityNamedOptional(optionalScopedSecurityProvider, "auth_opt", &.{"items:read"}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .auth = auth.value orelse "none",
    });
}

test "nested provider dependencies resolve for security marker" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "nested-provider",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addSecurityScheme("auth", .{ .http = .{ .scheme = "bearer", .bearer_format = "JWT" } });
    try app.get("/nested", nestedSecurityHandler, .{});
    try app.get("/nested-missing-scope", nestedMissingScopeHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var unauthorized = try client.get("/nested?token=bad");
    defer unauthorized.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unauthorized, unauthorized.status);

    var ok = try client.get("/nested?token=secret");
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok.status);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"user\":\"alice\"") != null);

    var missing_scope = try client.get("/nested-missing-scope?token=secret");
    defer missing_scope.deinit(std.testing.allocator);
    try std.testing.expectEqual(.forbidden, missing_scope.status);
    try std.testing.expect(missing_scope.header("www-authenticate") != null);
    try std.testing.expect(std.mem.indexOf(u8, missing_scope.header("www-authenticate").?, "insufficient_scope") != null);
    try std.testing.expect(std.mem.indexOf(u8, missing_scope.header("www-authenticate").?, "items:write") != null);
}

test "depends use_cache true executes provider once per request" {
    cache_calls = 0;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "cache-provider",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/cache", cacheHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var res = try client.get("/cache");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expectEqual(@as(usize, 1), cache_calls);
}

test "depends use_cache false executes provider for each marker" {
    no_cache_calls = 0;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "no-cache-provider",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/nocache", noCacheHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var res = try client.get("/nocache");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expectEqual(@as(usize, 2), no_cache_calls);
}

test "app scoped cache works for named injected dependency when registered" {
    tenant_calls = 0;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "tenant-cache",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("tenant", tenantProvider);
    try app.get("/tenant", tenantHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var first = try client.get("/tenant?tenant=acme");
    defer first.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, first.status);
    try std.testing.expect(std.mem.indexOf(u8, first.body, "\"tenant\":\"acme\"") != null);

    var second = try client.get("/tenant?tenant=other");
    defer second.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, second.status);
    try std.testing.expect(std.mem.indexOf(u8, second.body, "\"tenant\":\"acme\"") != null);

    try std.testing.expectEqual(@as(usize, 1), tenant_calls);
}

test "unnamed depends markers use callable cache key and run cleanup once" {
    cleanup_provider_calls = 0;
    cleanup_calls = 0;
    cleanup_key_non_empty = false;
    cleanup_value_matches = false;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "depends-cleanup-cache",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/cleanup", cleanupHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var res = try client.get("/cleanup");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"one\":\"resource\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"two\":\"resource\"") != null);
    try std.testing.expectEqual(@as(usize, 1), cleanup_provider_calls);
    try std.testing.expectEqual(@as(usize, 1), cleanup_calls);
    try std.testing.expect(cleanup_key_non_empty);
    try std.testing.expect(cleanup_value_matches);
}

test "depends cleanup runs for error responses" {
    cleanup_provider_calls = 0;
    cleanup_calls = 0;
    cleanup_key_non_empty = false;
    cleanup_value_matches = false;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "depends-cleanup-error",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/cleanup-error", cleanupErrorHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var res = try client.get("/cleanup-error");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.internal_server_error, res.status);
    try std.testing.expectEqual(@as(usize, 1), cleanup_provider_calls);
    try std.testing.expectEqual(@as(usize, 1), cleanup_calls);
    try std.testing.expect(cleanup_key_non_empty);
    try std.testing.expect(cleanup_value_matches);
}

test "optional security marker allows unauthenticated access when scopes are empty" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "optional-security",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/optional", optionalSecurityHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var no_auth = try client.get("/optional");
    defer no_auth.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, no_auth.status);
    try std.testing.expect(std.mem.indexOf(u8, no_auth.body, "\"auth\":\"none\"") != null);

    var with_auth = try client.get("/optional?token=abc123");
    defer with_auth.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, with_auth.status);
    try std.testing.expect(std.mem.indexOf(u8, with_auth.body, "\"auth\":\"abc123\"") != null);
}

test "optional security marker still enforces auth when scopes are required" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "optional-security-scoped",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addSecurityScheme("auth_opt", .{
        .oauth2 = .{
            .flows = .{
                .password = .{
                    .token_url = "/token",
                    .scopes = &.{.{ .name = "items:read" }},
                },
            },
        },
    });
    try app.get("/optional-scoped", optionalScopedSecurityHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var missing = try client.get("/optional-scoped");
    defer missing.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unauthorized, missing.status);
    try std.testing.expectEqualStrings("Bearer", missing.header("www-authenticate").?);

    var bad = try client.get("/optional-scoped?token=bad");
    defer bad.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unauthorized, bad.status);

    var ok = try client.get("/optional-scoped?token=secret");
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok.status);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"auth\":\"alice\"") != null);
}
