const std = @import("std");
const zigmund = @import("zigmund");

const TaskPayload = struct {
    title: []const u8,
};

fn createTask(
    payload: zigmund.Body(TaskPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    var response = try zigmund.Response.json(allocator, .{
        .title = payload.value.?.title,
        .status = "created",
    });
    response.status = .created;
    return response;
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/response-status-code/tasks", createTask, .{
        .summary = "Create with explicit 201 response status",
        .tags = &.{ "parity", "tutorial" },
        .status_code = .created,
        .operation_id = "tutorial_create_task_with_created_status",
    });
}
