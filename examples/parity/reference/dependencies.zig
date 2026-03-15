const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/dependencies/";

/// A dependency provider function -- returns a value extracted from the request.
fn currentUser(req: *zigmund.Request) ?[]const u8 {
    return req.header("x-user");
}

/// Handler that uses the Depends marker for dependency injection.
fn protectedRoute(
    user: zigmund.Depends(currentUser, .{ .name = "current_user" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .user = user.value,
        .api = .{
            .Depends = "zigmund.Depends(provider_fn, DependsOptions)",
            .DependsOptions = .{
                .use_cache = "default true - cache result per request",
                .cache_scope = "request or app scope",
                .name = "optional dependency name",
                .depends_on = "list of dependency names this depends on",
            },
        },
    });
}

/// Another dependency to demonstrate chaining.
fn dbSession(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    return "db-session-abc123";
}

fn withDbSession(
    session: zigmund.Depends(dbSession, .{ .name = "db" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .session = session.value,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/dependencies", protectedRoute, .{
        .summary = "Depends marker and dependency injection",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_dependencies_depends",
    });
    try app.get("/reference/dependencies/session", withDbSession, .{
        .summary = "Dependency provider returning a session value",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_dependencies_session",
    });
}
