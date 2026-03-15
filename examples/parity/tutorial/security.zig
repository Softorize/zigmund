const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/security/";

/// Security provider that extracts an API key from the "x-api-key" header.
fn apiKeyProvider(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const scheme = zigmund.APIKeyHeader{ .name = "x-api-key" };
    return scheme.resolve(req);
}

/// Protected endpoint that requires a valid API key header.
fn readApiKey(
    api_key: zigmund.Security(apiKeyProvider, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .api_key = api_key.value.?,
        .authenticated = true,
        .scheme = "apiKey",
        .location = "header",
    });
}

/// Alternative provider using HTTPBearer for bearer-token protection.
fn bearerProvider(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const bearer = zigmund.HTTPBearer{};
    const auth = (try bearer.resolve(req)) orelse return null;
    return auth.credentials;
}

/// Protected endpoint that requires a bearer token.
fn readBearerToken(
    token: zigmund.Security(bearerProvider, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .token = token.value.?,
        .authenticated = true,
        .scheme = "bearer",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addSecurityScheme("apiKeyAuth", .{
        .api_key = .{
            .name = "x-api-key",
            .in = .header,
        },
    });

    try app.addSecurityScheme("bearerAuth", .{
        .http = .{
            .scheme = "bearer",
            .bearer_format = "opaque",
        },
    });

    try app.get("/tutorial/security/api-key", readApiKey, .{
        .summary = "Protect an endpoint with an API key in the x-api-key header",
        .operation_id = "tutorial_security_api_key",
        .tags = &.{ "parity", "tutorial" },
    });

    try app.get("/tutorial/security/bearer", readBearerToken, .{
        .summary = "Protect an endpoint with a Bearer token",
        .operation_id = "tutorial_security_bearer",
        .tags = &.{ "parity", "tutorial" },
    });
}
