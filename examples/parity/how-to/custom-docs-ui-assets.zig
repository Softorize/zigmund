const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/custom-docs-ui-assets/";

/// Demonstrates custom documentation UI assets configuration.
/// Zigmund embeds Swagger UI and ReDoc assets at compile time,
/// but the docs endpoint URLs and UI configuration can be customized
/// through AppConfig fields (docs_url, redoc_url, docs, redoc).

fn customDocsInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "Zigmund serves documentation UIs with embedded assets",
        .swagger_ui = .{
            .default_url = "/docs",
            .configurable_via = "AppConfig.docs_url",
            .customization = "AppConfig.docs (SwaggerUiConfig)",
        },
        .redoc = .{
            .default_url = "/redoc",
            .configurable_via = "AppConfig.redoc_url",
            .customization = "AppConfig.redoc (RedocUiConfig)",
        },
        .redoc_options = .{
            .title = "Custom page title",
            .hide_download_button = "Hide the download button (default: false)",
            .disable_search = "Disable search functionality (default: false)",
            .theme = "UI color theme: light or dark (default: light)",
        },
        .note = "Assets are embedded at compile time; no external CDN needed",
    });
}

fn docsAvailability(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .endpoints = .{
            .swagger_ui = "/docs",
            .openapi_json = "/openapi.json",
            .redoc = "/redoc",
        },
        .message = "All documentation endpoints are available by default",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Custom docs UI configuration example:
    //
    //   var app = try zigmund.App.init(allocator, .{
    //       .title = "My API",
    //       .version = "1.0.0",
    //       .docs_url = "/swagger",     // Custom Swagger UI path
    //       .redoc_url = "/reference",   // Custom ReDoc path
    //       .docs = .{
    //           .title = "My API Docs",
    //           .theme = .dark,
    //       },
    //       .redoc = .{
    //           .title = "My API Reference",
    //           .hide_download_button = true,
    //           .theme = .dark,
    //       },
    //   });

    try app.get("/how-to/custom-docs-ui-assets", customDocsInfo, .{
        .summary = "Custom documentation UI assets and configuration",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_custom_docs_ui_assets_info",
    });

    try app.get("/how-to/custom-docs-ui-assets/availability", docsAvailability, .{
        .summary = "Documentation endpoint availability",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_custom_docs_ui_assets_availability",
    });
}
