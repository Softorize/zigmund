# Request Form Models

Zigmund lets you map form submissions to structured Zig models with metadata like descriptions. This gives you type-safe form handling with automatic OpenAPI documentation.

## Overview

While basic form handling with `zigmund.Form()` covers simple cases, real applications benefit from attaching metadata to the form model -- descriptions, validation hints, and documentation. The `Form()` marker accepts an options struct where you can configure these details, making the generated OpenAPI schema more informative for API consumers.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const ContactForm = struct {
    name: []const u8,
    email: []const u8,
    subject: []const u8,
    message: []const u8,
};

fn submitContact(
    form: zigmund.Form(ContactForm, .{
        .description = "Contact form submission",
    }),
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
```

Register the route:

```zig
try app.post("/contact", submitContact, .{});
```

## How It Works

1. **Define the form model.** `ContactForm` is a plain Zig struct with one field per form input. Each field name matches the HTML form field name the client submits.
2. **Attach metadata.** The `Form()` options struct accepts `.description`, which is included in the OpenAPI schema. This description appears in documentation tools like Swagger UI.
3. **Parse and validate.** When a POST request arrives with `Content-Type: application/x-www-form-urlencoded`, Zigmund parses the body and populates the `ContactForm` struct. All non-optional fields are required.
4. **Access the data.** `form.value.?` gives you the fully populated struct with type-safe field access.

## Key Points

- **Model-driven forms.** Defining a struct for each form centralizes the field definitions. If you add or remove a field, the struct and all handlers that use it are updated together.
- **Description for documentation.** The `.description` option on `Form()` adds a human-readable summary to the OpenAPI request body schema. Use it to explain what the form is for.
- **Required vs. optional fields.** Non-optional struct fields (`[]const u8`, `u32`) are required -- Zigmund returns a 422 error if they are missing. Optional fields (`?[]const u8`) are allowed to be absent.
- **Multiple forms.** Different endpoints can use different form models. Define as many form structs as you need, each tailored to its specific use case.
- **Content type.** By default, `Form()` expects `application/x-www-form-urlencoded`. For multipart forms (needed when combining with file uploads), set `.media_type = "multipart/form-data"` in the options.
- **Reusable models.** The same form struct can be reused across multiple handlers if several endpoints accept identical form data.

## See Also

- [Request Forms](request-forms.md) -- Basic form handling without model metadata.
- [Request Files](request-files.md) -- Handling file uploads.
- [Forms and Files](request-forms-and-files.md) -- Combining form data and file uploads.
- [Body Fields](body-fields.md) -- Validation constraints for JSON bodies (similar concepts apply to forms).
