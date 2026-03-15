const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/security/http-basic-auth/";

/// HTTP Basic authentication: extracts and validates username/password
/// from the Authorization header using the HTTPBasic security scheme.
const basic_scheme = zigmund.HTTPBasic{};

fn basicAuthEndpoint(
    credentials: zigmund.Security(basic_scheme, &.{}),
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // credentials.value is the raw HTTPAuthorizationCredentials
    // For decoded username/password, use decodeBasicCredentials
    const raw_creds = credentials.value.?;
    var decoded = try zigmund.decodeBasicCredentials(allocator, raw_creds.credentials);
    defer decoded.deinit(allocator);

    _ = req;

    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .username = decoded.username,
        .message = "Authenticated via HTTP Basic",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addSecurityScheme("basicAuth", .{
        .http = .{ .scheme = "basic" },
    });

    try app.get("/advanced/security__http-basic-auth", basicAuthEndpoint, .{
        .summary = "HTTP Basic authentication with credential decoding",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_http_basic_auth",
    });
}
