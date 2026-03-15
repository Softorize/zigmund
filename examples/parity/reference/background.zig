const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/background/";

var task_count: usize = 0;

fn logTask(_: *anyopaque) !void {
    task_count += 1;
}

/// Demonstrates BackgroundTasks: add tasks that run after the response is sent.
fn enqueueTask(
    req: *zigmund.Request,
    tasks: *zigmund.BackgroundTasks,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    try tasks.add(logTask, @ptrCast(&task_count));
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .queued = true,
        .api = .{
            .init = "BackgroundTasks.init(allocator)",
            .add = "tasks.add(fn, ctx) - enqueue a task",
            .run_all = "tasks.runAll() - execute all queued tasks",
        },
    });
}

fn taskStats(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .completed_tasks = task_count,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/reference/background/enqueue", enqueueTask, .{
        .summary = "Enqueue a background task to run after response",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_background_enqueue",
    });
    try app.get("/reference/background/stats", taskStats, .{
        .summary = "Check completed background task count",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_background_stats",
    });
}
