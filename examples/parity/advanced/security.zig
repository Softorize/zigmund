const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/security/";

/// Multi-scheme security: require both an API key header and a Bearer token.
/// Demonstrates combining multiple security providers on a single handler.
const api_key_scheme = zigmund.APIKeyHeader{ .name = "x-api-key" };
const bearer_scheme = zigmund.HTTPBearer{};

fn securedEndpoint(
    api_key: zigmund.Security(api_key_scheme, &.{}),
    token: zigmund.Security(bearer_scheme, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .api_key = api_key.value.?,
        .bearer_token = token.value.?,
        .message = "Authenticated with both API key and Bearer token",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Register both security schemes in OpenAPI documentation
    try app.addSecurityScheme("apiKeyHeader", .{
        .api_key = .{ .name = "x-api-key", .in = .header },
    });
    try app.addSecurityScheme("bearerAuth", .{
        .http = .{ .scheme = "bearer", .bearer_format = "JWT" },
    });

    try app.get("/advanced/security", securedEndpoint, .{
        .summary = "Multi-scheme security requiring API key and Bearer token",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_multi_scheme_security",
    });
}
