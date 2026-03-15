const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/fastapi/";

/// Demonstrates App.init with config, routing methods (get/post/put/delete),
/// and serving options -- the core FastAPI-equivalent entry point.
fn appOverview(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .app_config = .{
            .title = "Zigmund Reference",
            .version = "1.0.0",
            .description = "App.init accepts AppConfig with title, version, docs_url, openapi_url, etc.",
        },
        .routing_methods = &.{ "app.get", "app.post", "app.put", "app.patch", "app.delete", "app.head", "app.options", "app.trace" },
        .request = .{
            .method = @tagName(req.method),
            .path = req.path,
        },
        .lifecycle = &.{ "app.onStartup", "app.onShutdown", "app.lifespan", "app.serve" },
    });
}

fn appConfig(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .config_fields = .{
            .title = "required - application title",
            .version = "required - API version string",
            .summary = "optional short description",
            .description = "optional long description",
            .openapi_url = "default /openapi.json",
            .docs_url = "default /docs (Swagger UI)",
            .redoc_url = "default /redoc (ReDoc UI)",
            .redirect_slashes = "default true",
            .servers = "list of server URLs",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/fastapi", appOverview, .{
        .summary = "App init, config, and routing methods overview",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_fastapi_overview",
    });
    try app.get("/reference/fastapi/config", appConfig, .{
        .summary = "AppConfig fields reference",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_fastapi_config",
    });
}
