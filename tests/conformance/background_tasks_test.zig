const std = @import("std");
const zigmund = @import("zigmund");

var success_task_runs: usize = 0;
var failing_task_runs: usize = 0;
var error_path_task_runs: usize = 0;

fn resetTaskCounters() void {
    success_task_runs = 0;
    failing_task_runs = 0;
    error_path_task_runs = 0;
}

fn runSuccessTask(ctx: *anyopaque) !void {
    _ = ctx;
    success_task_runs += 1;
}

fn runFailingTask(ctx: *anyopaque) !void {
    _ = ctx;
    failing_task_runs += 1;
    return error.BackgroundTaskFailure;
}

fn runErrorPathTask(ctx: *anyopaque) !void {
    _ = ctx;
    error_path_task_runs += 1;
}

fn queueSuccessTask(
    req: *zigmund.Request,
    tasks: *zigmund.BackgroundTasks,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    try tasks.add(runSuccessTask, @ptrCast(&success_task_runs));
    return zigmund.Response.json(allocator, .{ .queued = true });
}

fn queueFailingTask(
    req: *zigmund.Request,
    tasks: *zigmund.BackgroundTasks,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    try tasks.add(runFailingTask, @ptrCast(&failing_task_runs));
    return zigmund.Response.json(allocator, .{ .queued = true });
}

fn queueTaskThenFail(
    req: *zigmund.Request,
    tasks: *zigmund.BackgroundTasks,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    _ = allocator;
    try tasks.add(runErrorPathTask, @ptrCast(&error_path_task_runs));
    return error.Outage;
}

test "background tasks run after successful responses" {
    resetTaskCounters();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "background-success",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/task", queueSuccessTask, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/task");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqual(@as(usize, 1), success_task_runs);
}

test "background task failures do not fail route responses" {
    resetTaskCounters();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "background-failure",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/task", queueFailingTask, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/task");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqual(@as(usize, 1), failing_task_runs);
}

test "background tasks still run when handlers error" {
    resetTaskCounters();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "background-error-path",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/task", queueTaskThenFail, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/task");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.internal_server_error, response.status);
    try std.testing.expectEqual(@as(usize, 1), error_path_task_runs);
}
