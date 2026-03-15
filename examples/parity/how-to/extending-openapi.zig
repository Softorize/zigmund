const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/extending-openapi/";

/// Demonstrates OpenAPI extensions using x- prefixed custom fields.
/// Extensions can be added at the app level (AppConfig.openapi_extensions)
/// and at the route level (RouteOptions.openapi_extensions).

fn appExtensionsInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "This app has app-level and route-level OpenAPI extensions",
        .app_extensions = .{
            .@"x-api-team" = "platform",
            .@"x-stability" = "stable",
        },
    });
}

fn routeWithExtension(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "This route has custom OpenAPI extensions attached",
        .route_extensions = .{
            .@"x-rate-limit" = "100 req/min",
            .@"x-internal" = false,
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // App-level extensions are set via AppConfig.openapi_extensions:
    //
    //   var app = try zigmund.App.init(allocator, .{
    //       .title = "My API",
    //       .version = "1.0.0",
    //       .openapi_extensions = &.{
    //           .{ .key = "x-api-team", .value_json = "\"platform\"" },
    //           .{ .key = "x-stability", .value_json = "\"stable\"" },
    //       },
    //   });

    try app.get("/how-to/extending-openapi", appExtensionsInfo, .{
        .summary = "App-level OpenAPI extensions overview",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_extending_openapi_app_info",
    });

    // Route-level extensions are set via RouteOptions.openapi_extensions
    try app.get("/how-to/extending-openapi/extended-route", routeWithExtension, .{
        .summary = "Route with custom x- OpenAPI extensions",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_extending_openapi_route",
        .openapi_extensions = &.{
            .{ .key = "x-rate-limit", .value_json = "\"100 req/min\"" },
            .{ .key = "x-internal", .value_json = "false" },
        },
    });
}
