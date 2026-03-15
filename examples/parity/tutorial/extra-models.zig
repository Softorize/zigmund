const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/extra-models/";

const UserIn = struct {
    username: []const u8,
    email: []const u8,
    full_name: ?[]const u8 = null,
};

const UserOut = struct {
    username: []const u8,
    email: []const u8,
    full_name: ?[]const u8 = null,
    id: u32,
};

fn createUser(
    body: zigmund.Body(UserIn, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user_in = body.value.?;
    return zigmund.Response.json(allocator, UserOut{
        .username = user_in.username,
        .email = user_in.email,
        .full_name = user_in.full_name,
        .id = 1001,
    });
}

fn getUser(
    user_id: zigmund.Path(u32, .{ .alias = "user_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, UserOut{
        .username = "alice",
        .email = "alice@example.com",
        .full_name = "Alice Wonderland",
        .id = user_id.value.?,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/extra-models/users", createUser, .{
        .summary = "Create user with separate input/output models",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_extra_models_create_user",
        .response_model = UserOut,
    });
    try app.get("/tutorial/extra-models/users/{user_id}", getUser, .{
        .summary = "Get user by ID with typed response model",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_extra_models_get_user",
        .response_model = UserOut,
    });
}
