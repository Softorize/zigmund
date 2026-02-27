const std = @import("std");
const zigmund = @import("zigmund");

fn protected(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
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
