# SQL Databases

Integrate with SQL databases using Zigmund's session provider, which manages connection lifecycle as a dependency so your handlers receive ready-to-use database sessions.

## Overview

Database access in a web application requires careful lifecycle management: connections must be acquired before the handler runs and released afterward, even if the handler errors. Zigmund's `SqlSessionProvider` wraps this pattern as a dependency, registering itself with the application and injecting a database session into any route that declares the dependency.

The session provider handles:

- **Connection pooling.** Sessions are drawn from a pool, reducing the overhead of establishing new connections per request.
- **Automatic cleanup.** Sessions are returned to the pool after the handler completes, whether it succeeds or fails.
- **Dependency integration.** The session appears as a named dependency, compatible with Zigmund's standard dependency injection system.

## Example

```zig
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
```

## How It Works

1. **Create a session provider.** `zigmund.SqlSessionProvider("postgres://zigmund@localhost/parity")` creates a comptime type configured with a database connection string. The connection string format follows the standard PostgreSQL URI scheme (`postgres://user@host/database`).

2. **Register the provider.** `DbSessionProvider.register(app, "db_session")` registers the provider as a named dependency called `"db_session"`. This makes it available to any route that declares the dependency.

3. **Declare the dependency on a route.** The `.dependencies` route option lists `"db_session"` as a required dependency. Zigmund ensures the session is acquired before the handler runs and released afterward.

4. **Access the session.** Inside the handler, `req.dependency("db_session")` retrieves the injected session. The return type is optional -- it returns `null` if the dependency is not registered or not available.

5. **Monitor active sessions.** `DbSessionProvider.activeCount()` returns the number of currently active (in-use) sessions across the pool. This is useful for health checks and diagnostics.

## Key Points

- The connection string is a comptime parameter, so it is embedded at compile time. For runtime configuration, use environment variables or a configuration file and pass the result to the provider at startup.
- Session lifecycle is tied to the request. The session is acquired when the dependency is resolved (before the handler) and released when the request completes (after the handler and any [background tasks](background-tasks.md)).
- The dependency name (`"db_session"`) is a plain string. You can register multiple providers with different names for different databases (e.g., `"read_db"`, `"write_db"`).
- If the database is unreachable when a session is requested, the dependency resolution fails and the framework returns a `500 Internal Server Error` to the client.
- `SqlSessionProvider` integrates with Zigmund's dependency system, so it works with sub-dependencies, global dependencies, and all other dependency features documented in [Dependencies](dependencies.md).

## See Also

- [Dependencies](dependencies.md) -- The full dependency injection system, including sub-dependencies and scoped lifetimes.
- [Background Tasks](background-tasks.md) -- Run deferred work after the response, with awareness of session lifecycle.
- [Bigger Applications](bigger-applications.md) -- Organize database access patterns across multiple routers.
- [Testing](testing.md) -- Test database-dependent handlers using the in-process `TestClient`.
