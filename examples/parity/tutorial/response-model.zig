const std = @import("std");
const zigmund = @import("zigmund");

const PublicUser = struct {
    id: u32,
    username: []const u8,
};

fn readUser(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .id = 7,
        .username = "alice",
        .email = "alice@example.com",
        .admin = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/response-model/users/me", readUser, .{
        .summary = "Filter response data through response_model",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_response_model_users_me",
        .response_model = PublicUser,
    });
}
