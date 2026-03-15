const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/";

/// Reference index: lists all reference pages and their topics.
fn referenceIndex(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .title = "Zigmund API Reference",
        .sections = .{
            .fastapi = "/reference/fastapi - App init, config, routing",
            .apirouter = "/reference/apirouter - Router, includeRouter",
            .request = "/reference/request - Request API (headers, params, body)",
            .response = "/reference/response - Response types (json, text, html, redirect, SSE)",
            .responses = "/reference/responses - ResponseSpec for additional responses",
            .parameters = "/reference/parameters - Query, Path, Header, Cookie, Body markers",
            .background = "/reference/background - BackgroundTasks API",
            .dependencies = "/reference/dependencies - Depends marker and DI",
            .exceptions = "/reference/exceptions - Exception handlers",
            .security = "/reference/security - Security schemes",
            .staticfiles = "/reference/staticfiles - StaticFilesIntegration",
            .uploadfile = "/reference/uploadfile - File marker and UploadFile",
            .websockets = "/reference/websockets - WebSocket connection API",
            .openapi = "/reference/openapi - OpenAPI generation",
            .openapi_docs = "/reference/openapi__docs - Docs UI config",
            .openapi_models = "/reference/openapi__models - Schema types",
            .httpconnection = "/reference/httpconnection - HTTP connection",
            .encoders = "/reference/encoders - JSON encoding",
            .status = "/reference/status - HTTP status codes",
            .templating = "/reference/templating - TemplatesIntegration",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/index", referenceIndex, .{
        .summary = "API reference overview and index",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_index",
    });
}
