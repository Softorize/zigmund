const std = @import("std");
const zigmund = @import("zigmund");

const LoginForm = struct {
    username: []const u8,
    password: []const u8,
};

fn login(
    form: zigmund.Form(LoginForm, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .username = form.value.?.username,
        .accepted = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/request-forms/login", login, .{
        .summary = "Submit form-urlencoded login payload",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_request_forms_login",
    });
}
