const std = @import("std");
const zigmund = @import("zigmund");

fn tokenProvider(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const bearer = zigmund.HTTPBearer{};
    const auth = (try bearer.resolve(req)) orelse return null;
    return auth.credentials;
}

fn readCurrentToken(
    token: zigmund.Security(tokenProvider, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .token = token.value.?,
        .authenticated = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addSecurityScheme("bearerAuth", .{
        .http = .{
            .scheme = "bearer",
            .bearer_format = "JWT",
        },
    });

    try app.get("/tutorial/security/first-steps/me", readCurrentToken, .{
        .summary = "Extract bearer token from Authorization header",
        .tags = &.{ "parity", "tutorial", "security" },
        .operation_id = "tutorial_security_first_steps_me",
    });
}
