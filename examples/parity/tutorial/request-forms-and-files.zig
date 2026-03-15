const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/request-forms-and-files/";

const ProfileForm = struct {
    username: []const u8,
    bio: []const u8,
};

fn updateProfile(
    form: zigmund.Form(ProfileForm, .{ .media_type = "multipart/form-data", .description = "Profile metadata" }),
    avatar: zigmund.File(zigmund.UploadFile, .{ .description = "Profile avatar image" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const data = form.value.?;
    const file = avatar.value.?;
    return zigmund.Response.json(allocator, .{
        .username = data.username,
        .bio = data.bio,
        .avatar_filename = file.filename,
        .avatar_content_type = file.content_type,
        .avatar_bytes = file.data.len,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/request-forms-and-files/profile", updateProfile, .{
        .summary = "Mixed form data and file upload in one request",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_request_forms_and_files_update_profile",
    });
}
