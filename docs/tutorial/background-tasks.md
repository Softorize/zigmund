# Background Tasks

Run tasks after the HTTP response has been sent, keeping response times fast while performing deferred work like sending notifications, writing audit logs, or updating caches.

## Overview

Some operations should not block the response: sending an email, pushing a metric, or writing to a slow external service. Zigmund provides a `BackgroundTasks` mechanism that lets you queue work during request handling. The response is sent to the client immediately, and the queued tasks execute afterward in the same server process.

Background tasks are registered by adding a `*zigmund.BackgroundTasks` parameter to your handler. The framework injects a task queue scoped to the current request. You call `tasks.add(function, context)` to enqueue work, and Zigmund runs all queued tasks after the response is flushed.

## Example

```zig
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
```

## How It Works

1. **Inject the task queue.** Adding `tasks: *zigmund.BackgroundTasks` to the handler signature tells Zigmund to inject a per-request task queue. No additional configuration is needed.

2. **Define a task function.** `sendNotification` is a function with the signature `fn(*anyopaque) !void`. It receives an opaque context pointer that you provide when enqueuing.

3. **Enqueue work.** `tasks.add(sendNotification, @ptrCast(&queued_notifications))` registers the function and context. You can call `tasks.add` multiple times to queue several tasks for the same request.

4. **Response is sent first.** The handler returns `Response.json(allocator, .{ .queued = true })` immediately. The client receives the response without waiting for the background work.

5. **Tasks execute after the response.** Once the response bytes are flushed to the client, Zigmund runs each queued task in order. In this example, `sendNotification` increments a counter.

6. **Observe side effects.** The `/stats` endpoint reads the counter, demonstrating that the background task has run. In a production application, this might be a database query or metrics dashboard.

## Key Points

- Background tasks run in the server process, not in a separate worker or job queue. They are suitable for lightweight, fast operations. For heavy or unreliable work (e.g., sending emails to an external SMTP server), consider a dedicated job queue.
- Tasks execute sequentially in the order they were added. If one task returns an error, subsequent tasks may still run depending on the error handling strategy.
- The context pointer passed to `tasks.add` must remain valid until after the task executes. Global or heap-allocated state works; stack-local data from the handler does not (it is freed when the handler returns).
- Multiple tasks can be queued per request. Each call to `tasks.add` appends to the queue.
- Background tasks have access to the allocator and any state you pass through the context pointer, but they do not have access to the original `Request` or `Response`.

## See Also

- [Dependencies](dependencies.md) -- Dependency injection provides an alternative for setup/teardown work (e.g., database connections that need cleanup).
- [Middleware](middleware.md) -- Middleware can also run logic after the response, but applies to all routes rather than specific handlers.
- [Debugging](debugging.md) -- Use observability sinks to trace background task execution.
