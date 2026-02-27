const std = @import("std");
const zigmund = @import("zigmund");

const DogSchema: zigmund.OpenApiSchema = .{
    .schema_type = "object",
    .fields = &.{
        .{ .name = "kind", .schema_type = "string", .required = true },
        .{ .name = "dog_name", .schema_type = "string", .required = true },
    },
};

const CatSchema: zigmund.OpenApiSchema = .{
    .schema_type = "object",
    .fields = &.{
        .{ .name = "kind", .schema_type = "string", .required = true },
        .{ .name = "cat_name", .schema_type = "string", .required = true },
    },
};

const PetEventSchema: zigmund.OpenApiSchema = .{
    .schema_type = "object",
    .one_of = &.{ DogSchema, CatSchema },
    .discriminator_property_name = "kind",
    .discriminator_mapping = &.{
        .{ .value = "dog", .schema_ref = "#/components/schemas/Dog" },
        .{ .value = "cat", .schema_ref = "#/components/schemas/Cat" },
    },
};

const EventPayload = struct {
    kind: []const u8,
    dog_name: ?[]const u8 = null,
    cat_name: ?[]const u8 = null,
};

fn publishEvent(
    payload: zigmund.Body(EventPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .kind = payload.value.?.kind,
        .dog_name = payload.value.?.dog_name orelse "",
    });
}

test "openapi supports callbacks webhooks examples and composed schemas" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-advanced",
        .version = "0.0.1",
        .webhooks = &.{.{
            .name = "pet.updated",
            .method = .POST,
            .operation_id = "webhook_pet_updated",
            .summary = "Pet updated webhook",
            .request_body_schema = PetEventSchema,
            .response_status = .ok,
        }},
    });
    defer app.deinit();

    try app.post("/events", publishEvent, .{
        .openapi_response_schema = PetEventSchema,
        .openapi_request_examples = &.{.{
            .name = "pet_event",
            .summary = "Dog event",
            .value_json = "{\"kind\":\"dog\",\"dog_name\":\"fido\"}",
        }},
        .openapi_response_examples = &.{.{
            .status_code = .ok,
            .content_type = "application/json",
            .examples = &.{.{
                .name = "pet_ok",
                .value_json = "{\"kind\":\"cat\",\"cat_name\":\"milo\"}",
            }},
        }},
        .openapi_callbacks = &.{.{
            .name = "pet_delivered",
            .expression = "{$request.body#/callback_url}",
            .method = .POST,
            .operation_id = "post_pet_callback",
            .summary = "Delivery callback",
            .request_body_schema = PetEventSchema,
            .response_status = .accepted,
            .response_description = "Accepted",
            .response_schema = .{ .schema_type = "string" },
        }},
    });

    const doc = try app.openapi();

    try std.testing.expect(std.mem.indexOf(u8, doc, "\"oneOf\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"discriminator\":{\"propertyName\":\"kind\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"mapping\":{\"dog\":\"#/components/schemas/Dog\",\"cat\":\"#/components/schemas/Cat\"}") != null);

    try std.testing.expect(std.mem.indexOf(u8, doc, "\"callbacks\":{\"pet_delivered\":{\"{$request.body#/callback_url}\":{\"post\":{\"operationId\":\"post_pet_callback\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"webhooks\":{\"pet.updated\":{\"post\":{\"operationId\":\"webhook_pet_updated\"") != null);

    try std.testing.expect(std.mem.indexOf(u8, doc, "\"examples\":{\"pet_event\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"summary\":\"Dog event\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"value\":{\"kind\":\"dog\",\"dog_name\":\"fido\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"examples\":{\"pet_ok\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"value\":{\"kind\":\"cat\",\"cat_name\":\"milo\"}") != null);
}
