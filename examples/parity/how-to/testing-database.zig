const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/testing-database/";

/// Demonstrates database testing patterns with SqlSessionProvider.
/// SqlSessionProvider registers a dependency that provides database
/// sessions with automatic cleanup. For testing, dependency overrides
/// can replace the real database with a test double.

const DbSession = zigmund.SqlSessionProvider("postgres://app@localhost/mydb");

fn listUsers(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const db_session = req.dependency("db") orelse "no-session";
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .db_session = db_session,
        .users = &[_][]const u8{ "alice", "bob", "charlie" },
        .message = "Users fetched via database session dependency",
    });
}

fn createUser(
    req: *zigmund.Request,
    body: zigmund.Body(struct { name: []const u8, email: []const u8 }, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const db_session = req.dependency("db") orelse "no-session";
    return (try zigmund.Response.json(allocator, .{
        .page = source_page,
        .db_session = db_session,
        .created_user = .{
            .name = body.value.?.name,
            .email = body.value.?.email,
        },
        .message = "User created via database session dependency",
    })).withStatus(.created);
}

fn testingInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "Database testing patterns with SqlSessionProvider",
        .pattern = .{
            .register = "SqlSessionProvider(dsn).register(&app, \"db\")",
            .override_for_test = "app.overrideDependency(\"db\", mockResolver)",
            .cleanup = "Sessions are automatically cleaned up after each request",
            .reset = "DbSession.resetForTesting() resets counters between tests",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Register the database session provider
    try DbSession.register(app, "db");

    try app.get("/how-to/testing-database", testingInfo, .{
        .summary = "Database testing patterns overview",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_testing_database_info",
    });

    try app.get("/how-to/testing-database/users", listUsers, .{
        .summary = "List users using database session",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_testing_database_list_users",
        .dependencies = &.{.{ .name = "db" }},
    });

    try app.post("/how-to/testing-database/users", createUser, .{
        .summary = "Create user using database session",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_testing_database_create_user",
        .dependencies = &.{.{ .name = "db" }},
    });

    // Test example (commented out since this runs as part of the parity suite):
    //
    //   // Override with test double
    //   try app.overrideDependency("db", testDbResolver);
    //   defer app.clearDependencyOverride("db");
    //
    //   var res = try app.dispatchSynthetic(.GET, "/how-to/testing-database/users", "");
    //   defer res.deinit(allocator);
    //   // assert on res...
}
