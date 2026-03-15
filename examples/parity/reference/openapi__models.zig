const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/openapi/models/";

/// Demonstrates OpenAPI schema model types used for spec generation.
fn modelsOverview(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .schema_types = .{
            .OpenApiSchema = .{
                .schema_type = "string | integer | number | boolean | object | array",
                .schema_format = "optional: int32, int64, float, double, date-time, uri, etc.",
                .is_array = "true for array types",
                .fields = "[]OpenApiSchemaField for object types",
                .one_of = "union discriminator schemas",
            },
            .OpenApiSchemaField = .{
                .name = "field name",
                .required = "default true",
                .schema_type = "field type",
                .is_array = "true for array fields",
            },
            .OpenApiExample = .{
                .name = "example name",
                .summary = "optional short description",
                .value_json = "JSON string of the example value",
            },
            .OpenApiExtension = .{
                .key = "extension key (e.g. x-custom)",
                .value_json = "JSON string value",
            },
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/openapi__models", modelsOverview, .{
        .summary = "OpenAPI schema types: Schema, SchemaField, Example, Extension",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_openapi_models_overview",
    });
}
