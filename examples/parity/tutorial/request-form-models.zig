const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/request-form-models/";

const ContactForm = struct {
    name: []const u8,
    email: []const u8,
    subject: []const u8,
    message: []const u8,
};

fn submitContact(
    form: zigmund.Form(ContactForm, .{ .description = "Contact form submission" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const data = form.value.?;
    return zigmund.Response.json(allocator, .{
        .received = true,
        .name = data.name,
        .email = data.email,
        .subject = data.subject,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/request-form-models/contact", submitContact, .{
        .summary = "Submit structured form data via model binding",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_request_form_models_submit_contact",
    });
}
