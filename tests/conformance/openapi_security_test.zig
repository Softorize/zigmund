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
