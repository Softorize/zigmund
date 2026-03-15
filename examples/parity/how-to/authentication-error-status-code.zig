const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/authentication-error-status-code/";

/// Demonstrates custom authentication error status codes.
/// When a request fails authentication, the unauthorized handler
/// returns a 403 Forbidden instead of the default 401 Unauthorized.

fn customUnauthorizedHandler(_: *const zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return (try zigmund.Response.json(allocator, .{
        .detail = "Access denied: invalid or missing credentials",
        .page = source_page,
    })).withStatus(.forbidden);
}

const bearer_scheme = zigmund.HTTPBearer{};

fn protectedRoute(
    token: zigmund.Security(bearer_scheme, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .token = token.value.?,
        .message = "Authenticated successfully",
    });
}

fn publicRoute(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "This endpoint demonstrates custom auth error status codes. " ++
            "Missing credentials on /protected returns 403 instead of 401.",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Set custom unauthorized handler that returns 403 Forbidden
    app.setUnauthorizedHandler(customUnauthorizedHandler);

    try app.addSecurityScheme("bearerAuth", .{
        .http = .{ .scheme = "bearer", .bearer_format = "JWT" },
    });

    try app.get("/how-to/authentication-error-status-code", publicRoute, .{
        .summary = "Custom auth error status codes overview",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_auth_error_status_code_overview",
    });

    try app.get("/how-to/authentication-error-status-code/protected", protectedRoute, .{
        .summary = "Protected endpoint returning 403 on auth failure",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_auth_error_status_code_protected",
    });
}
