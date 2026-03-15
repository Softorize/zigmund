const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/openapi/docs/";

/// Demonstrates docs UI configuration: Swagger and ReDoc settings.
fn docsConfig(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .swagger_ui = .{
            .config_type = "SwaggerUiConfig",
            .title = "optional custom page title",
            .persist_authorization = "default false",
            .deep_linking = "default true",
            .display_operation_id = "default false",
            .doc_expansion = "list | full | none (default list)",
            .theme = "light | dark (default light)",
        },
        .redoc_ui = .{
            .config_type = "RedocUiConfig",
            .title = "optional custom page title",
            .hide_download_button = "default false",
            .disable_search = "default false",
            .theme = "light | dark (default light)",
        },
        .app_config_fields = .{
            .docs_url = "default /docs - set null to disable",
            .redoc_url = "default /redoc - set null to disable",
            .openapi_url = "default /openapi.json - set null to disable all",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/openapi__docs", docsConfig, .{
        .summary = "Swagger and ReDoc UI configuration",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_openapi_docs_config",
    });
}
