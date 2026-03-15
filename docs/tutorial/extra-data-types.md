# Extra Data Types

Use Zig's native numeric and boolean types for timestamps, durations, decimals, and flags without external libraries.

## Overview

In Python, representing dates, time intervals, and precise decimal numbers requires importing specialized types like `datetime`, `timedelta`, and `Decimal`. Zig takes a different approach: its standard integer and floating-point types are expressive enough to cover these use cases directly. An epoch timestamp is an `i64`, a duration in seconds is a `u64`, a decimal price is an `f64`, and a boolean flag is a `bool`. No extra libraries are needed.

This page shows how to use these native types in Zigmund request bodies and responses, and how they map to JSON.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const TimestampedItem = struct {
    name: []const u8,          // JSON string
    created_epoch: i64,        // Unix timestamp (seconds since 1970-01-01)
    duration_seconds: u64,     // Duration as unsigned integer
    weight_grams: f64,         // Decimal value
    is_active: bool,           // Boolean flag
};

fn createItem(
    body: zigmund.Body(TimestampedItem, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const item = body.value.?;
    return zigmund.Response.json(allocator, .{
        .name = item.name,
        .created_epoch = item.created_epoch,
        .duration_seconds = item.duration_seconds,
        .weight_grams = item.weight_grams,
        .is_active = item.is_active,
    });
}

// Registration:
// app.post("/items", createItem, .{})
```

### Request example

```bash
curl -X POST http://127.0.0.1:8000/items \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Sensor Module",
    "created_epoch": 1710460800,
    "duration_seconds": 86400,
    "weight_grams": 125.7,
    "is_active": true
  }'
```

Response:

```json
{
  "name": "Sensor Module",
  "created_epoch": 1710460800,
  "duration_seconds": 86400,
  "weight_grams": 125.7,
  "is_active": true
}
```

## How It Works

### 1. Type mapping: Python vs. Zig

| Python type         | Zig type       | JSON type | Notes                                       |
|---------------------|----------------|-----------|---------------------------------------------|
| `datetime`          | `i64`          | number    | Unix epoch in seconds (or milliseconds).     |
| `timedelta`         | `u64`          | number    | Duration in seconds (or any unit you choose).|
| `Decimal`           | `f64`          | number    | IEEE 754 double-precision floating point.    |
| `bool`              | `bool`         | boolean   | `true` or `false`.                           |
| `str`               | `[]const u8`   | string    | UTF-8 byte slice.                            |
| `int`               | `i32` / `i64`  | number    | Choose the width you need.                   |
| `float`             | `f32` / `f64`  | number    | Choose the precision you need.               |

### 2. Timestamps as i64

Zig has no built-in datetime type. Instead, represent timestamps as Unix epoch values:

```zig
const TimestampedItem = struct {
    created_epoch: i64,  // Seconds since 1970-01-01T00:00:00Z
};
```

Using `i64` (signed) lets you represent dates before 1970. If you only need dates after 1970, `u64` works too. Choose your unit (seconds, milliseconds, or microseconds) based on the precision your application requires, and document the convention.

### 3. Durations as u64

A duration is simply a count of time units. There is no need for a `timedelta` object:

```zig
const Config = struct {
    timeout_seconds: u64,        // How long to wait
    retry_interval_ms: u64,      // Retry every N milliseconds
    cache_ttl_seconds: u64,      // Cache time-to-live
};
```

The field name carries the unit (`_seconds`, `_ms`), making the code self-documenting.

### 4. Decimal values as f64

For prices, weights, measurements, and other decimal values, `f64` provides 15--17 significant digits of precision:

```zig
const Product = struct {
    price: f64,          // e.g., 9.99
    weight_grams: f64,   // e.g., 125.7
};
```

If your application requires exact decimal arithmetic (e.g., financial calculations where `0.1 + 0.2` must equal `0.3`), consider storing values as integer cents/basis points:

```zig
const Invoice = struct {
    amount_cents: i64,   // 999 = $9.99
};
```

### 5. Boolean flags

Zig's `bool` maps directly to JSON `true`/`false`:

```zig
const Item = struct {
    is_active: bool,
    is_featured: bool = false,  // Default to false if not provided.
};
```

### 6. Choosing integer widths

Zig offers integers from `u8` to `u128` (and their signed counterparts). Pick the smallest type that fits your domain:

| Type    | Range                                      | Typical use                    |
|---------|--------------------------------------------|--------------------------------|
| `u8`    | 0 to 255                                   | Status codes, small counters.  |
| `u16`   | 0 to 65,535                                | Port numbers.                  |
| `u32`   | 0 to 4,294,967,295                         | IDs, counts.                   |
| `u64`   | 0 to 18,446,744,073,709,551,615            | Timestamps, large counters.    |
| `i32`   | -2,147,483,648 to 2,147,483,647            | Signed IDs, offsets.           |
| `i64`   | -9,223,372,036,854,775,808 to ...          | Epoch timestamps, large signed.|

### 7. Zigmund extended types

For applications that need richer type semantics beyond raw numbers, Zigmund also provides extended types that carry additional meaning:

```zig
const zigmund = @import("zigmund");

// UUID type
const id: zigmund.Uuid = ...;

// ISO 8601 datetime
const dt: zigmund.DateTime = ...;

// ISO 8601 duration
const dur: zigmund.Duration = ...;
```

These are available via the `schema` module and provide parsing, validation, and proper OpenAPI schema generation. The native Zig types covered on this page are sufficient for most use cases.

## Key Points

- Zig does not have specialized datetime, timedelta, or decimal types. Use `i64`, `u64`, `f64`, and `bool` directly.
- Encode timestamps as Unix epoch integers. Include the unit in the field name (`_seconds`, `_ms`) for clarity.
- Encode durations as unsigned integers representing a count of time units.
- Use `f64` for decimal values. For exact arithmetic, consider integer-based representations (e.g., cents).
- All these types serialize to JSON numbers or booleans with no extra conversion step.
- Zigmund also provides `Uuid`, `DateTime`, and `Duration` extended types for cases that need richer semantics.

## See Also

- [Request Body](request-body.md) -- using structs as input models.
- [Response Model](response-model.md) -- filtering output fields.
- [First Steps](first-steps.md) -- the basic application structure.
