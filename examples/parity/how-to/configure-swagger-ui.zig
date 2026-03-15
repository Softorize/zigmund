const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/configure-swagger-ui/";

/// Demonstrates Swagger UI customization through SwaggerUiConfig.
/// Available fields: title, persist_authorization, deep_linking,
/// display_operation_id, doc_expansion (.list/.full/.none), theme (.light/.dark).

fn swaggerConfigInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "Swagger UI is configured via the docs field of AppConfig",
        .available_options = .{
            .title = "Custom page title (default: null, uses app title)",
            .persist_authorization = "Remember auth credentials across refreshes (default: false)",
            .deep_linking = "Enable deep linking to operations (default: true)",
            .display_operation_id = "Show operation IDs in the UI (default: false)",
            .doc_expansion = "How operations are displayed: list, full, or none (default: list)",
            .theme = "UI color theme: light or dark (default: light)",
        },
        .current_config = .{
            .title = "Zigmund Parity Examples",
            .deep_linking = true,
            .display_operation_id = true,
            .doc_expansion = "full",
            .theme = "dark",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Swagger UI is configured at app creation via AppConfig.docs:
    //
    //   var app = try zigmund.App.init(allocator, .{
    //       .title = "My API",
    //       .version = "1.0.0",
    //       .docs = .{
    //           .title = "My Custom Docs",
    //           .persist_authorization = true,
    //           .deep_linking = true,
    //           .display_operation_id = true,
    //           .doc_expansion = .full,
    //           .theme = .dark,
    //       },
    //   });

    try app.get("/how-to/configure-swagger-ui", swaggerConfigInfo, .{
        .summary = "Swagger UI customization options",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_configure_swagger_ui_info",
    });
}
