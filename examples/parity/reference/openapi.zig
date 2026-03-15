const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/openapi/";

/// Demonstrates OpenAPI schema generation and access.
fn openapiInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .auto_generation = "OpenAPI spec is auto-generated from routes and parameter markers",
        .access_urls = .{
            .openapi_json = "AppConfig.openapi_url (default /openapi.json)",
            .swagger_ui = "AppConfig.docs_url (default /docs)",
            .redoc_ui = "AppConfig.redoc_url (default /redoc)",
        },
        .generation_api = .{
            .generate = "openapi.generate(allocator, cfg, http_routes, ws_routes, security_schemes)",
            .route_options = "RouteOptions: summary, description, tags, operation_id, deprecated",
            .response_model = "RouteOptions.response_model = MyStruct auto-derives schema",
            .openapi_callbacks = "RouteOptions.openapi_callbacks for callback definitions",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/openapi", openapiInfo, .{
        .summary = "OpenAPI generation and schema access",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_openapi_overview",
    });
}
