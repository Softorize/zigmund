const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/openapi-webhooks/";

/// Demonstrates OpenAPI webhook definitions. Unlike callbacks (which are
/// per-route), webhooks are defined at the application level via
/// AppConfig.webhooks and appear in the top-level "webhooks" section of
/// the OpenAPI spec.

fn webhookInfo(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "This app defines a 'newUser' webhook in the OpenAPI spec",
        .webhook_name = "newUser",
        .description = "Fires when a new user signs up",
    });
}

/// To configure webhooks, pass them in AppConfig when creating the app:
///
///   var app = try zigmund.App.init(allocator, .{
///       .title = "Webhook Demo",
///       .version = "1.0",
///       .webhooks = &.{
///           .{
///               .name = "newUser",
///               .method = .POST,
///               .summary = "New user signup notification",
///               .description = "Sent when a user creates an account",
///               .request_body_schema = .{
///                   .schema_type = "object",
///                   .fields = &.{
///                       .{ .name = "user_id", .schema_type = "string" },
///                       .{ .name = "email", .schema_type = "string", .schema_format = "email" },
///                       .{ .name = "created_at", .schema_type = "string", .schema_format = "date-time" },
///                   },
///               },
///               .response_status = .ok,
///               .response_description = "Webhook received",
///           },
///       },
///   });

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/openapi-webhooks", webhookInfo, .{
        .summary = "OpenAPI webhook definition info",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_openapi_webhooks",
    });
}
