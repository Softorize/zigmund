const std = @import("std");
const core = @import("../core/mod.zig");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const SqlIntegration = struct {
    dsn: []const u8,
    session_counter: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    active_sessions: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    pub fn init(dsn: []const u8) SqlIntegration {
        return .{
            .dsn = dsn,
        };
    }

    pub fn openSession(self: *SqlIntegration, allocator: std.mem.Allocator) ![]u8 {
        const next = self.session_counter.fetchAdd(1, .monotonic) + 1;
        _ = self.active_sessions.fetchAdd(1, .monotonic);
        return std.fmt.allocPrint(allocator, "{s}#session-{d}", .{ self.dsn, next });
    }

    pub fn closeSession(self: *SqlIntegration, session_token: []const u8) void {
        _ = session_token;
        const active = self.active_sessions.load(.monotonic);
        if (active > 0) {
            _ = self.active_sessions.fetchSub(1, .monotonic);
        }
    }

    pub fn activeSessionCount(self: *const SqlIntegration) usize {
        return self.active_sessions.load(.monotonic);
    }
};

pub fn SqlSessionProvider(comptime dsn: []const u8) type {
    return struct {
        var counter: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
        var active_sessions: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

        pub fn resolver(req: *Request, allocator: std.mem.Allocator) !?[]const u8 {
            _ = req;
            _ = allocator;
            const next = counter.fetchAdd(1, .monotonic) + 1;
            _ = next;
            _ = active_sessions.fetchAdd(1, .monotonic);
            return dsn;
        }

        pub fn cleanup(
            req: *Request,
            key: []const u8,
            value: []const u8,
            allocator: std.mem.Allocator,
        ) !void {
            _ = req;
            _ = key;
            _ = value;
            _ = allocator;

            const active = active_sessions.load(.monotonic);
            if (active > 0) {
                _ = active_sessions.fetchSub(1, .monotonic);
            }
        }

        pub fn register(app: *core.App, dependency_name: []const u8) !void {
            try app.addDependencyWithCleanup(dependency_name, resolver, cleanup);
        }

        pub fn activeCount() usize {
            return active_sessions.load(.monotonic);
        }

        pub fn resetForTesting() void {
            counter.store(0, .monotonic);
            active_sessions.store(0, .monotonic);
        }
    };
}

test "sql session provider cleanup decrements active sessions" {
    const Provider = SqlSessionProvider("postgres://app@localhost/db");
    Provider.resetForTesting();

    var app = try core.App.init(std.testing.allocator, .{
        .title = "sql-session",
        .version = "0.0.1",
    });
    defer app.deinit();

    try Provider.register(&app, "db_session");

    const H = struct {
        fn run(req: *Request, allocator: std.mem.Allocator) !Response {
            return Response.json(allocator, .{
                .db_session = req.dependency("db_session") orelse "",
            });
        }
    };

    try app.get("/db", H.run, .{
        .dependencies = &.{.{ .name = "db_session" }},
    });

    var res = try app.dispatchSynthetic(.GET, "/db", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "postgres://app@localhost/db") != null);
    try std.testing.expectEqual(@as(usize, 0), Provider.activeCount());
}
