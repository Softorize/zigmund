const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/openapi-callbacks/";

/// Demonstrates OpenAPI callback definitions. Callbacks describe
/// out-of-band HTTP requests the API will make to a caller-provided URL,
/// such as webhook-style notifications after an invoice is created.

fn createInvoice(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var response = try zigmund.Response.json(allocator, .{
        .page = source_page,
        .invoice_id = "inv-001",
        .status = "pending",
        .message = "Invoice created; callback will fire when paid",
    });
    return response.withStatus(.created);
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/advanced/openapi-callbacks/invoices", createInvoice, .{
        .summary = "Create invoice with payment callback notification",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_create_invoice_callback",
        .openapi_callbacks = &.{
            .{
                .name = "invoicePaid",
                .expression = "{$request.body#/callback_url}",
                .method = .POST,
                .operation_id = "invoice_paid_callback",
                .summary = "Notification sent when invoice is paid",
                .description = "The API sends a POST to the callback URL with payment details",
                .request_body_schema = .{
                    .schema_type = "object",
                    .fields = &.{
                        .{ .name = "invoice_id", .schema_type = "string" },
                        .{ .name = "paid_at", .schema_type = "string", .schema_format = "date-time" },
                        .{ .name = "amount", .schema_type = "number" },
                    },
                },
                .response_status = .ok,
                .response_description = "Callback acknowledged",
            },
        },
    });
}
