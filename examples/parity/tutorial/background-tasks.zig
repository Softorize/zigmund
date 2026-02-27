const std = @import("std");
const zigmund = @import("zigmund");

var queued_notifications: usize = 0;

fn sendNotification(_: *anyopaque) !void {
    queued_notifications += 1;
}

fn queueNotification(
    req: *zigmund.Request,
    tasks: *zigmund.BackgroundTasks,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    try tasks.add(sendNotification, @ptrCast(&queued_notifications));
    return zigmund.Response.json(allocator, .{
        .queued = true,
    });
}

fn backgroundStats(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .notifications_sent = queued_notifications,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/background-tasks/notifications", queueNotification, .{
        .summary = "Queue a background notification task",
        .tags = &.{ "parity", "tutorial" },
    });
    try app.get("/tutorial/background-tasks/stats", backgroundStats, .{
        .summary = "Inspect background task side effects",
        .tags = &.{ "parity", "tutorial" },
    });
}
