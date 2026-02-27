const std = @import("std");

pub const BackgroundTasks = struct {
    allocator: std.mem.Allocator,
    tasks: std.ArrayListUnmanaged(Task) = .empty,

    pub const TaskFn = *const fn (ctx: *anyopaque) anyerror!void;

    pub const Task = struct {
        run: TaskFn,
        ctx: *anyopaque,
    };

    pub fn init(allocator: std.mem.Allocator) BackgroundTasks {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *BackgroundTasks) void {
        self.tasks.deinit(self.allocator);
    }

    pub fn add(self: *BackgroundTasks, run: TaskFn, ctx: *anyopaque) !void {
        try self.tasks.append(self.allocator, .{ .run = run, .ctx = ctx });
    }

    pub fn runAll(self: *BackgroundTasks) !void {
        for (self.tasks.items) |task| {
            try task.run(task.ctx);
        }
    }
};
