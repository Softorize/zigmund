# JSON, Base64, and Bytes

Handle binary data in JSON responses using Base64 encoding. Zigmund uses Zig's standard library `std.base64` for encoding and decoding, providing the equivalent of Python's base64-bytes handling in JSON APIs.

## Overview

JSON does not support binary data natively. The standard approach is to encode binary data as Base64 strings for inclusion in JSON payloads. Zigmund handlers can use `std.base64` to encode raw bytes before serialization and decode Base64 input from query parameters or request bodies.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// Demonstrates base64 encoding/decoding of binary data in JSON responses.
fn encodeBase64(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const raw_data = "Hello, binary world!";

    // Encode to base64
    const encoded_len = std.base64.standard.Encoder.calcSize(raw_data.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, raw_data);

    return zigmund.Response.json(allocator, .{
        .raw_length = raw_data.len,
        .base64_data = encoded,
        .message = "Binary data encoded as base64 in JSON response",
    });
}

fn decodeBase64(
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // Read base64-encoded data from query parameter
    const input = req.queryParam("data") orelse "SGVsbG8=";

    const decoded_len = std.base64.standard.Decoder.calcSizeUpperBound(input.len);
    const decoded_buf = try allocator.alloc(u8, decoded_len);
    const actual_len = std.base64.standard.Decoder.decode(decoded_buf, input) catch {
        var response = try zigmund.Response.json(allocator, .{
            .@"error" = "Invalid base64 input",
        });
        return response.withStatus(.bad_request);
    };

    return zigmund.Response.json(allocator, .{
        .input_base64 = input,
        .decoded_text = decoded_buf[0..actual_len],
        .decoded_length = actual_len,
        .message = "Base64 data decoded from query parameter",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/encode", encodeBase64, .{
        .summary = "Encode binary data as base64 in JSON response",
    });

    try app.get("/decode", decodeBase64, .{
        .summary = "Decode base64 data from query parameter",
    });
}
```

## How It Works

### 1. Encoding Binary Data to Base64

Use `std.base64.standard.Encoder` to convert raw bytes to a Base64 string:

```zig
const raw_data = "Hello, binary world!";

// Calculate the encoded length
const encoded_len = std.base64.standard.Encoder.calcSize(raw_data.len);

// Allocate a buffer for the encoded data
const encoded = try allocator.alloc(u8, encoded_len);

// Encode
_ = std.base64.standard.Encoder.encode(encoded, raw_data);
```

The encoded string can then be included in a JSON response as a regular string field.

### 2. Decoding Base64 Input

Use `std.base64.standard.Decoder` to convert Base64 strings back to raw bytes:

```zig
const input = "SGVsbG8=";  // Base64 for "Hello"

// Calculate upper bound for decoded length
const decoded_len = std.base64.standard.Decoder.calcSizeUpperBound(input.len);

// Allocate a buffer
const decoded_buf = try allocator.alloc(u8, decoded_len);

// Decode (may fail for invalid input)
const actual_len = std.base64.standard.Decoder.decode(decoded_buf, input) catch {
    // Handle invalid base64 input
    return (try zigmund.Response.json(allocator, .{
        .@"error" = "Invalid base64 input",
    })).withStatus(.bad_request);
};

// Use decoded_buf[0..actual_len]
```

### 3. Error Handling

Base64 decoding can fail if the input contains invalid characters. Always handle the error case:

```zig
const actual_len = std.base64.standard.Decoder.decode(decoded_buf, input) catch {
    var response = try zigmund.Response.json(allocator, .{
        .@"error" = "Invalid base64 input",
    });
    return response.withStatus(.bad_request);
};
```

### 4. Memory Management

Both encoding and decoding require buffer allocation. Use the per-request allocator provided by Zigmund -- the memory is automatically freed after the response is sent:

```zig
const encoded = try allocator.alloc(u8, encoded_len);
// No need to free -- the per-request arena handles cleanup
```

### 5. Common Base64 Variants

Zig's standard library supports multiple Base64 variants:

| Variant                        | Alphabet      | Use Case                  |
|-------------------------------|---------------|---------------------------|
| `std.base64.standard`         | A-Z, a-z, 0-9, +, / | Standard Base64 (RFC 4648)   |
| `std.base64.url_safe`         | A-Z, a-z, 0-9, -, _ | URL-safe Base64              |

Use `url_safe` for data that appears in URLs or filenames.

## Key Points

- Use `std.base64.standard.Encoder` to encode binary data for JSON inclusion.
- Use `std.base64.standard.Decoder` to decode Base64 input from requests.
- Always handle decoding errors -- invalid Base64 should return a 400 Bad Request.
- The per-request allocator manages buffer memory automatically.
- Use `std.base64.url_safe` for URL-safe encoding when data appears in URLs.
- Base64 encoding increases data size by approximately 33%.

## See Also

- [Custom Response](custom-response.md) -- return different response types.
- [Using the Request Directly](using-request-directly.md) -- read raw query parameters and body.
- [Strict Content Type](strict-content-type.md) -- validate content types for incoming data.
