const std = @import("std");
const zigmund = @import("zigmund");

const DbSessionProvider = zigmund.SqlSessionProvider("postgres://zigmund@localhost/parity");

fn readDbSession(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .session = req.dependency("db_session") orelse "",
        .active_sessions = DbSessionProvider.activeCount(),
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try DbSessionProvider.register(app, "db_session");
    try app.get("/tutorial/sql-databases/session", readDbSession, .{
        .summary = "SQL session dependency lifecycle example",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_sql_databases_session",
        .dependencies = &.{.{
            .name = "db_session",
        }},
    });
}
