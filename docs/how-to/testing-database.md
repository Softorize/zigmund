# How to Test Database-Dependent Routes

This recipe shows how to use `SqlSessionProvider` for database access and override it with test doubles during testing.

## Problem

You want routes that depend on database sessions, with the ability to swap in test doubles for testing without hitting a real database.

## Solution

```zig
const std = @import("std");
const zigmund = @import("zigmund");

// Define a database session provider
const DbSession = zigmund.SqlSessionProvider("postgres://app@localhost/mydb");

fn listUsers(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const db_session = req.dependency("db") orelse "no-session";
    return zigmund.Response.json(allocator, .{
        .db_session = db_session,
        .users = &[_][]const u8{ "alice", "bob", "charlie" },
    });
}

fn createUser(
    req: *zigmund.Request,
    body: zigmund.Body(struct { name: []const u8, email: []const u8 }, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const db_session = req.dependency("db") orelse "no-session";
    _ = db_session;
    return (try zigmund.Response.json(allocator, .{
        .name = body.value.?.name,
        .email = body.value.?.email,
    })).withStatus(.created);
}

pub fn setup(app: *zigmund.App) !void {
    // Register the database session provider as a named dependency
    try DbSession.register(app, "db");

    try app.get("/users", listUsers, .{
        .summary = "List users",
        .dependencies = &.{.{ .name = "db" }},
    });

    try app.post("/users", createUser, .{
        .summary = "Create user",
        .dependencies = &.{.{ .name = "db" }},
    });
}

// In tests:
test "list users with mock database" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "Test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try setup(&app);

    // Override with a test double
    try app.overrideDependency("db", testDbResolver);
    defer _ = app.clearDependencyOverride("db");

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var res = try client.get("/users");
    defer res.deinit(std.testing.allocator);
    // Assert on response...
}

fn testDbResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    return "test-session";
}
```

## Explanation

The database testing pattern in Zigmund uses the dependency injection system:

1. **Register a provider** -- `SqlSessionProvider(dsn).register(&app, "db")` registers a named dependency that provides database sessions.
2. **Declare dependencies on routes** -- The `dependencies` field in `RouteOptions` lists the named dependencies a route needs. The framework resolves them before calling the handler.
3. **Access in handlers** -- Use `req.dependency("db")` to retrieve the resolved value.
4. **Override for testing** -- `app.overrideDependency("db", testResolver)` replaces the real resolver with a test double. Use `app.clearDependencyOverride("db")` to restore the original.
5. **Automatic cleanup** -- Sessions registered with cleanup functions are automatically cleaned up after each request.

## See Also

- [Dependencies Reference](../reference/dependencies.md)
- [TestClient Reference](../reference/testclient.md)
- [App Reference](../reference/app.md)
