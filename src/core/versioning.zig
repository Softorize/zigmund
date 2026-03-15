const std = @import("std");
const App = @import("app.zig").App;
const Router = @import("router.zig").Router;
const Request = @import("../http/request.zig").Request;

/// Configuration for URL-prefix-based API versioning.
pub const VersionConfig = struct {
    /// URL prefix placed before the version number (e.g. "/v" yields "/v1", "/v2").
    prefix: []const u8 = "/v",

    /// Version to use when none is specified (reserved for future default-routing).
    default_version: u32 = 1,
};

/// Pairs a semantic version number with the router that serves it.
pub const VersionedRouter = struct {
    version: u32,
    router: *const Router,
    /// Optional include-router options forwarded to `App.includeRouter`.
    options: @import("types.zig").IncludeRouterOptions = .{},
};

/// Mount versioned routers onto an app with automatic prefix routing.
///
/// Each router's routes are registered under `{config.prefix}{version}`
/// (e.g. `/v1`, `/v2`), delegating to `App.includeRouter` so that
/// tags, dependencies, and OpenAPI schema merging work as expected.
///
/// Example:
/// ```zig
/// var v1 = Router.init(allocator);
/// var v2 = Router.init(allocator);
/// // ... register routes on v1 and v2 ...
/// try mountVersionedRouters(&app, .{}, &.{
///     .{ .version = 1, .router = &v1 },
///     .{ .version = 2, .router = &v2 },
/// });
/// ```
pub fn mountVersionedRouters(
    app: *App,
    config: VersionConfig,
    versioned_routers: []const VersionedRouter,
) !void {
    for (versioned_routers) |vr| {
        var buf: [64]u8 = undefined;
        const prefix = std.fmt.bufPrint(&buf, "{s}{d}", .{ config.prefix, vr.version }) catch
            return error.VersionPrefixTooLong;
        try app.includeRouter(prefix, vr.router, vr.options);
    }
}

/// Extract an API version number from request headers.
///
/// Checks `Accept-Version` first, then falls back to `X-API-Version`.
/// Returns `null` when neither header is present or the value is not a
/// valid unsigned integer.
pub fn versionFromHeader(req: *const Request) ?u32 {
    const value = req.header("Accept-Version") orelse
        req.header("X-API-Version") orelse
        return null;
    return std.fmt.parseInt(u32, value, 10) catch null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "mountVersionedRouters registers routes under versioned prefixes" {
    const allocator = std.testing.allocator;

    // -- v1 router --
    var v1 = Router.init(allocator);
    defer v1.deinit();

    const V1 = struct {
        fn handler(req: *Request, alloc: std.mem.Allocator) !@import("../http/response.zig").Response {
            _ = req;
            _ = alloc;
            return @import("../http/response.zig").Response.text("v1");
        }
    };
    try v1.addHttpRoute(.GET, "/items", V1.handler, .{});

    // -- v2 router --
    var v2 = Router.init(allocator);
    defer v2.deinit();

    const V2 = struct {
        fn handler(req: *Request, alloc: std.mem.Allocator) !@import("../http/response.zig").Response {
            _ = req;
            _ = alloc;
            return @import("../http/response.zig").Response.text("v2");
        }
    };
    try v2.addHttpRoute(.GET, "/items", V2.handler, .{});

    // -- app --
    var app = try App.init(allocator, .{ .title = "version-test", .version = "0.1.0" });
    defer app.deinit();

    try mountVersionedRouters(&app, .{}, &.{
        .{ .version = 1, .router = &v1 },
        .{ .version = 2, .router = &v2 },
    });

    // Verify routes are registered under /v1/items and /v2/items.
    const routes = app.router.httpRoutes();
    try std.testing.expect(routes.len >= 2);

    var found_v1 = false;
    var found_v2 = false;
    for (routes) |route| {
        if (std.mem.eql(u8, route.path, "/v1/items")) found_v1 = true;
        if (std.mem.eql(u8, route.path, "/v2/items")) found_v2 = true;
    }
    try std.testing.expect(found_v1);
    try std.testing.expect(found_v2);
}

test "mountVersionedRouters respects custom prefix" {
    const allocator = std.testing.allocator;

    var r = Router.init(allocator);
    defer r.deinit();

    const H = struct {
        fn handler(req: *Request, alloc: std.mem.Allocator) !@import("../http/response.zig").Response {
            _ = req;
            _ = alloc;
            return @import("../http/response.zig").Response.text("ok");
        }
    };
    try r.addHttpRoute(.GET, "/status", H.handler, .{});

    var app = try App.init(allocator, .{ .title = "custom-prefix", .version = "0.1.0" });
    defer app.deinit();

    try mountVersionedRouters(&app, .{ .prefix = "/api/v" }, &.{
        .{ .version = 3, .router = &r },
    });

    const routes = app.router.httpRoutes();
    var found = false;
    for (routes) |route| {
        if (std.mem.eql(u8, route.path, "/api/v3/status")) found = true;
    }
    try std.testing.expect(found);
}

test "versionFromHeader parses Accept-Version" {
    const allocator = std.testing.allocator;
    var req = try Request.initSyntheticWithHeaders(
        allocator,
        .GET,
        "/items",
        "",
        &.{.{ .name = "Accept-Version", .value = "2" }},
    );
    defer req.deinit();

    try std.testing.expectEqual(@as(?u32, 2), versionFromHeader(&req));
}

test "versionFromHeader falls back to X-API-Version" {
    const allocator = std.testing.allocator;
    var req = try Request.initSyntheticWithHeaders(
        allocator,
        .GET,
        "/items",
        "",
        &.{.{ .name = "X-API-Version", .value = "5" }},
    );
    defer req.deinit();

    try std.testing.expectEqual(@as(?u32, 5), versionFromHeader(&req));
}

test "versionFromHeader returns null when no header present" {
    const allocator = std.testing.allocator;
    var req = try Request.initSynthetic(allocator, .GET, "/items", "");
    defer req.deinit();

    try std.testing.expectEqual(@as(?u32, null), versionFromHeader(&req));
}

test "versionFromHeader returns null for non-numeric value" {
    const allocator = std.testing.allocator;
    var req = try Request.initSyntheticWithHeaders(
        allocator,
        .GET,
        "/items",
        "",
        &.{.{ .name = "Accept-Version", .value = "latest" }},
    );
    defer req.deinit();

    try std.testing.expectEqual(@as(?u32, null), versionFromHeader(&req));
}
