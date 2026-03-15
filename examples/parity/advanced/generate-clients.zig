const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/generate-clients/";

/// Demonstrates how to access the OpenAPI JSON spec for client generation.
/// Use app.openapi() to retrieve the full OpenAPI JSON document, which can
/// be fed to code generators (openapi-generator, oapi-codegen, etc.).
fn openapiSpec(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    // In a real scenario you would serve the spec or write it to a file:
    //   const spec = try app.openapi();
    //   // feed `spec` to openapi-generator or similar tool
    //
    // The default /openapi.json endpoint already serves the spec.
    // This handler shows how to use it programmatically.

    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .openapi_url = "/openapi.json",
        .message = "Access /openapi.json for the full OpenAPI spec; use app.openapi() programmatically for client generation",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/generate-clients", openapiSpec, .{
        .summary = "OpenAPI spec access for client code generation",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_generate_clients",
    });
}
