const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/security/simple-oauth2/";

/// User record for the demo.
const User = struct {
    username: []const u8,
    email: []const u8,
    full_name: []const u8,
    disabled: bool,
    hashed_password: []const u8,
};

/// Fake user database keyed by username.
const fake_users = [_]User{
    .{
        .username = "johndoe",
        .email = "johndoe@example.com",
        .full_name = "John Doe",
        .disabled = false,
        .hashed_password = "fakehashedsecret",
    },
    .{
        .username = "alice",
        .email = "alice@example.com",
        .full_name = "Alice Wonderson",
        .disabled = true,
        .hashed_password = "fakehashedsecret2",
    },
};

fn findUser(username: []const u8) ?User {
    for (&fake_users) |*u| {
        if (std.mem.eql(u8, u.username, username)) return u.*;
    }
    return null;
}

/// Trivial fake hash: "fakehashed" ++ password. In production use bcrypt/scrypt.
fn fakeHashPassword(password: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, "fakehashedsecret", "fakehashed")) {
        // We just check prefix for the demo
        _ = password;
    }
    return null;
}

fn verifyPassword(plain: []const u8, hashed: []const u8) bool {
    // In a real app this would use bcrypt/scrypt. Here we just check that
    // the hashed password equals "fakehashed" ++ plain.
    const prefix = "fakehashed";
    if (!std.mem.startsWith(u8, hashed, prefix)) return false;
    return std.mem.eql(u8, hashed[prefix.len..], plain);
}

/// Security provider using OAuth2PasswordBearer — extracts the bearer token
/// and looks up the corresponding user.
fn getCurrentUser(req: *zigmund.Request, allocator: std.mem.Allocator) !?User {
    _ = allocator;
    const oauth2 = zigmund.OAuth2PasswordBearer{ .token_url = "/tutorial/security/simple-oauth2/token" };
    const token = (try oauth2.resolve(req)) orelse return null;

    // In this simplified demo the token IS the username (issued by /token).
    return findUser(token);
}

/// POST /token — accepts OAuth2 password-grant form data and returns a token.
fn loginForAccessToken(
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const form = try zigmund.OAuth2PasswordRequestForm.fromRequest(req);

    const user = findUser(form.username) orelse {
        return zigmund.Response.json(allocator, .{
            .@"error" = "invalid_credentials",
            .detail = "Incorrect username or password",
        });
    };

    if (!verifyPassword(form.password, user.hashed_password)) {
        return zigmund.Response.json(allocator, .{
            .@"error" = "invalid_credentials",
            .detail = "Incorrect username or password",
        });
    }

    // In a real app, mint a JWT here. For the demo we return the username
    // as the access token, matching FastAPI's simple-oauth2 tutorial.
    return zigmund.Response.json(allocator, .{
        .access_token = user.username,
        .token_type = "bearer",
    });
}

/// Protected endpoint — requires a valid bearer token.
fn readCurrentUser(
    current_user: zigmund.Security(getCurrentUser, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user = current_user.value.?;
    if (user.disabled) {
        return zigmund.Response.json(allocator, .{
            .@"error" = "inactive_user",
            .detail = "User account is disabled",
        });
    }
    return zigmund.Response.json(allocator, .{
        .username = user.username,
        .email = user.email,
        .full_name = user.full_name,
        .disabled = user.disabled,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addSecurityScheme("oauth2PasswordBearer", .{
        .oauth2 = .{
            .flows = .{
                .password = .{
                    .token_url = "/tutorial/security/simple-oauth2/token",
                },
            },
        },
    });

    try app.post("/tutorial/security/simple-oauth2/token", loginForAccessToken, .{
        .summary = "OAuth2 password-grant login — returns an access token",
        .operation_id = "tutorial_security_simple_oauth2_token",
        .tags = &.{ "parity", "tutorial" },
    });

    try app.get("/tutorial/security/simple-oauth2/me", readCurrentUser, .{
        .summary = "Get current user via OAuth2 password-flow bearer token",
        .operation_id = "tutorial_security_simple_oauth2_me",
        .tags = &.{ "parity", "tutorial" },
    });
}
