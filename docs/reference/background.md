# BackgroundTasks Reference

## Overview

`BackgroundTasks` allows scheduling work that runs after the response has been sent. This is useful for operations like sending emails, updating caches, or logging analytics that should not block the response.

## Type Definition

```zig
pub const BackgroundTasks = struct {
    pub const TaskFn = *const fn (ctx: *anyopaque) anyerror!void;

    pub const Task = struct {
        run: TaskFn,
        ctx: *anyopaque,
    };

    pub fn init(allocator: std.mem.Allocator) BackgroundTasks;
    pub fn deinit(self: *BackgroundTasks) void;
    pub fn add(self: *BackgroundTasks, run: TaskFn, ctx: *anyopaque) !void;
    pub fn runAll(self: *BackgroundTasks) !void;
};
```

## Methods

### `init`

```zig
pub fn init(allocator: std.mem.Allocator) BackgroundTasks
```

Creates a new background tasks queue.

### `add`

```zig
pub fn add(self: *BackgroundTasks, run: TaskFn, ctx: *anyopaque) !void
```

Enqueues a task function with its context pointer. Tasks are executed in order after the response is sent.

### `runAll`

```zig
pub fn runAll(self: *BackgroundTasks) !void
```

Executes all enqueued tasks. Called automatically by the framework after response dispatch.

### `deinit`

```zig
pub fn deinit(self: *BackgroundTasks) void
```

Frees internal storage.

## Usage

Background tasks are accessible through `Request.background_tasks`:

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const EmailContext = struct {
    to: []const u8,
    subject: []const u8,

    fn send(raw: *anyopaque) !void {
        const self: *EmailContext = @ptrCast(@alignCast(raw));
        // Send the email
        std.log.info("Sending email to {s}: {s}", .{ self.to, self.subject });
    }
};

fn createOrder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const ctx = try allocator.create(EmailContext);
    ctx.* = .{
        .to = "user@example.com",
        .subject = "Order confirmed",
    };

    try req.background_tasks.add(EmailContext.send, ctx);

    return zigmund.Response.json(allocator, .{ .status = "created" });
}
```

Tasks run after the response is fully sent, so they do not affect response latency.
