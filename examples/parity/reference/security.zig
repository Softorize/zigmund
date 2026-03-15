const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/security/";

/// Bearer token provider using HTTPBearer.
fn bearerProvider(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const bearer = zigmund.HTTPBearer{};
    const auth = (try bearer.resolve(req)) orelse return null;
    return auth.credentials;
}

/// Demonstrates Security marker with HTTPBearer scheme.
fn securedEndpoint(
    token: zigmund.Security(bearerProvider, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .token = token.value.?,
        .schemes = .{
            .HTTPBearer = "Bearer token from Authorization header",
            .HTTPBasic = "Basic credentials (username:password)",
            .APIKeyHeader = "API key from a named header",
            .APIKeyQuery = "API key from a query parameter",
            .APIKeyCookie = "API key from a cookie",
            .OAuth2PasswordBearer = "OAuth2 password flow bearer token",
            .VerifiedHS256Bearer = "JWT with HS256 signature verification",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addSecurityScheme("bearerAuth", .{
        .http = .{
            .scheme = "bearer",
            .bearer_format = "JWT",
        },
    });

    try app.get("/reference/security", securedEndpoint, .{
        .summary = "Security schemes overview: bearer, basic, API key, OAuth2",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_security_overview",
    });
}
