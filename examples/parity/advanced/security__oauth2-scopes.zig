const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/security/oauth2-scopes/";

/// OAuth2 with scope enforcement: the handler requires both "read" and "write"
/// scopes to be present in the bearer token. The Security parameter enforces
/// the scopes at the framework level.
const oauth2_scheme = zigmund.OAuth2PasswordBearer{
    .token_url = "/token",
    .scopes = &.{ "read", "write" },
};

fn scopedEndpoint(
    token: zigmund.Security(oauth2_scheme, &.{ "read", "write" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .token = token.value.?,
        .required_scopes = &[_][]const u8{ "read", "write" },
        .message = "Authorized with read and write scopes",
    });
}

fn readOnlyEndpoint(
    token: zigmund.Security(oauth2_scheme, &.{"read"}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .token = token.value.?,
        .required_scopes = &[_][]const u8{"read"},
        .message = "Authorized with read scope only",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addSecurityScheme("oauth2Scopes", .{
        .oauth2 = .{
            .flows = .{
                .password = .{
                    .token_url = "/token",
                    .scopes = &.{
                        .{ .name = "read", .description = "Read access" },
                        .{ .name = "write", .description = "Write access" },
                    },
                },
            },
        },
    });

    try app.get("/advanced/security__oauth2-scopes", scopedEndpoint, .{
        .summary = "OAuth2 endpoint requiring read and write scopes",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_oauth2_read_write",
    });

    try app.get("/advanced/security__oauth2-scopes/read", readOnlyEndpoint, .{
        .summary = "OAuth2 endpoint requiring read scope only",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_oauth2_read_only",
    });
}
