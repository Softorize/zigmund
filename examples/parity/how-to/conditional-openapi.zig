const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/conditional-openapi/";

/// Demonstrates conditionally disabling OpenAPI documentation in production.
/// By setting docs_url, openapi_url, and redoc_url to null in AppConfig,
/// the documentation endpoints are not registered. In Zigmund this is
/// configured at app creation time via AppConfig fields.

fn conditionalOpenApiInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "Conditionally disable OpenAPI docs by setting URL fields to null in AppConfig",
        .example_production_config = .{
            .docs_url = "null (disabled)",
            .openapi_url = "null (disabled)",
            .redoc_url = "null (disabled)",
        },
        .example_development_config = .{
            .docs_url = "/docs",
            .openapi_url = "/openapi.json",
            .redoc_url = "/redoc",
        },
        .note = "Set docs_url/openapi_url/redoc_url to null in AppConfig to disable in production",
    });
}

fn healthCheck(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .status = "healthy",
        .docs_enabled = true,
        .message = "This app has docs enabled; a production app would set docs_url = null",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Production config example (not applied here since we want docs for the parity suite):
    //
    //   var prod_app = try zigmund.App.init(allocator, .{
    //       .title = "My API",
    //       .version = "1.0.0",
    //       .docs_url = null,       // Disable Swagger UI
    //       .openapi_url = null,    // Disable OpenAPI JSON
    //       .redoc_url = null,      // Disable ReDoc
    //   });

    try app.get("/how-to/conditional-openapi", conditionalOpenApiInfo, .{
        .summary = "Conditionally disable OpenAPI documentation",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_conditional_openapi_info",
    });

    try app.get("/how-to/conditional-openapi/health", healthCheck, .{
        .summary = "Health check showing docs availability",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_conditional_openapi_health",
    });
}
