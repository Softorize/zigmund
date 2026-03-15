# Partial Updates

Zigmund supports both full replacement (PUT) and partial updates (PATCH) on resources. Use a struct with all required fields for PUT, and a struct with all optional fields for PATCH.

## Overview

REST APIs typically offer two update strategies:

- **PUT** -- replaces the entire resource. The client sends all fields; missing fields are reset to defaults.
- **PATCH** -- updates only the provided fields. The client sends a subset of fields; omitted fields remain unchanged.

In Zigmund, you model these as two separate structs: one with required fields for PUT, and one with all-optional fields for PATCH. Zigmund parses the JSON body into the appropriate struct based on which handler is called.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const ItemFull = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
    tax: ?f64 = null,
};

const ItemPartial = struct {
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    price: ?f64 = null,
    tax: ?f64 = null,
};

fn replaceItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    item: zigmund.Body(ItemFull, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const body = item.value.?;
    return zigmund.Response.json(allocator, .{
        .operation = "replace",
        .item_id = item_id.value.?,
        .name = body.name,
        .description = body.description,
        .price = body.price,
        .tax = body.tax,
    });
}

fn patchItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    item: zigmund.Body(ItemPartial, .{
        .description = "Partial item update: only provided fields are changed",
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const body = item.value.?;
    return zigmund.Response.json(allocator, .{
        .operation = "partial_update",
        .item_id = item_id.value.?,
        .name = body.name,
        .description = body.description,
        .price = body.price,
        .tax = body.tax,
    });
}
```

Register both routes:

```zig
try app.put("/items/{item_id}", replaceItem, .{});
try app.patch("/items/{item_id}", patchItem, .{});
```

## How It Works

1. **Full replacement (PUT).** `ItemFull` has required fields (`name`, `price`) and optional fields (`description`, `tax`). A PUT request must include all required fields. The handler receives the complete new state of the resource.
2. **Partial update (PATCH).** `ItemPartial` has all fields as optional (`?` types with `= null` defaults). A PATCH request can include any subset of fields. Fields set to `null` in the parsed struct were not provided by the client.
3. **Separate handlers.** Each HTTP method maps to its own handler with the appropriate body struct, making the intent explicit in the code.

### Applying Partial Updates

In the PATCH handler, check which fields are non-null and apply only those:

```zig
fn patchItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    item: zigmund.Body(ItemPartial, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const body = item.value.?;

    // Load existing item from database
    var existing = try loadItem(item_id.value.?);

    // Apply only the fields that were provided
    if (body.name) |name| existing.name = name;
    if (body.description) |desc| existing.description = desc;
    if (body.price) |price| existing.price = price;
    if (body.tax) |tax| existing.tax = tax;

    // Save and return
    try saveItem(existing);
    return zigmund.Response.json(allocator, existing);
}
```

## Key Points

- **Two structs, two routes.** Define a "full" struct for PUT and a "partial" struct for PATCH. This makes validation automatic: PUT rejects incomplete payloads; PATCH accepts any subset.
- **Null means "not provided".** In the partial struct, a `null` value means the client did not include that field. This is distinct from the client explicitly sending `null` to clear a field.
- **Same path, different methods.** Both PUT and PATCH can share the same URL path. Zigmund routes to the correct handler based on the HTTP method.
- **OpenAPI documentation.** The generated OpenAPI schema clearly distinguishes between the PUT body (with required fields) and the PATCH body (all optional), helping API consumers understand the contract.
- **Merge logic is yours.** Zigmund handles parsing; the merge logic (applying non-null fields to the existing resource) is the handler's responsibility.

## See Also

- [Request Body](request-body.md) -- Basic JSON body parsing.
- [Body Fields](body-fields.md) -- Adding validation constraints to body fields.
- [Nested Models](body-nested-models.md) -- Handling nested objects in update payloads.
- [Response Status Code](response-status-code.md) -- Returning appropriate status codes for updates (200, 204).
