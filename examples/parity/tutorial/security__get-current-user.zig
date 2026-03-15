const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/security/get-current-user/";

/// Represents a resolved user from the security token.
const User = struct {
    username: []const u8,
    email: []const u8,
    full_name: []const u8,
    disabled: bool,
};

/// Fake user database — maps tokens to user records.
const fake_users = [_]struct { token: []const u8, user: User }{
    .{
        .token = "alice-secret-token",
        .user = .{
            .username = "alice",
            .email = "alice@example.com",
            .full_name = "Alice Wonderson",
            .disabled = false,
        },
    },
    .{
        .token = "bob-secret-token",
        .user = .{
            .username = "bob",
            .email = "bob@example.com",
            .full_name = "Bob Builder",
            .disabled = true,
        },
    },
};

/// Security provider that extracts a bearer token and resolves it to a User.
/// Returns null (triggering a 401) when the token is missing or unrecognised.
fn getCurrentUser(req: *zigmund.Request, allocator: std.mem.Allocator) !?User {
    _ = allocator;
    const bearer = zigmund.HTTPBearer{};
    const auth = (try bearer.resolve(req)) orelse return null;

    for (&fake_users) |*entry| {
        if (std.mem.eql(u8, auth.credentials, entry.token)) {
            return entry.user;
        }
    }
    return null;
}

/// Returns the current user derived from the bearer token.
fn readCurrentUser(
    current_user: zigmund.Security(getCurrentUser, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user = current_user.value.?;
    return zigmund.Response.json(allocator, .{
        .username = user.username,
        .email = user.email,
        .full_name = user.full_name,
        .disabled = user.disabled,
    });
}

/// Returns items belonging to the current user.
fn readOwnItems(
    current_user: zigmund.Security(getCurrentUser, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user = current_user.value.?;
    return zigmund.Response.json(allocator, .{
        .owner = user.username,
        .items = &[_]struct { item_id: []const u8, title: []const u8 }{
            .{ .item_id = "item-1", .title = "My first item" },
            .{ .item_id = "item-2", .title = "My second item" },
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addSecurityScheme("bearerAuth", .{
        .http = .{
            .scheme = "bearer",
            .bearer_format = "opaque",
        },
    });

    try app.get("/tutorial/security/get-current-user/me", readCurrentUser, .{
        .summary = "Resolve a bearer token to a User and return their profile",
        .operation_id = "tutorial_security_get_current_user_me",
        .tags = &.{ "parity", "tutorial" },
    });

    try app.get("/tutorial/security/get-current-user/me/items", readOwnItems, .{
        .summary = "List items belonging to the authenticated user",
        .operation_id = "tutorial_security_get_current_user_items",
        .tags = &.{ "parity", "tutorial" },
    });
}
