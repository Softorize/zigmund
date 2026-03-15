const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/json-base64-bytes/";

/// Demonstrates base64 encoding/decoding of binary data in JSON responses.
/// Uses std.base64 to encode raw bytes and return them in a JSON field,
/// providing the Zig equivalent of Python's base64-bytes handling.
fn encodeBase64(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const raw_data = "Hello, binary world!";

    // Encode to base64
    const encoded_len = std.base64.standard.Encoder.calcSize(raw_data.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, raw_data);

    return zigmund.Response.json(allocator, .{
        .page = source_page,
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
            .page = source_page,
            .@"error" = "Invalid base64 input",
        });
        return response.withStatus(.bad_request);
    };

    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .input_base64 = input,
        .decoded_text = decoded_buf[0..actual_len],
        .decoded_length = actual_len,
        .message = "Base64 data decoded from query parameter",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/json-base64-bytes/encode", encodeBase64, .{
        .summary = "Encode binary data as base64 in JSON response",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_base64_encode",
    });

    try app.get("/advanced/json-base64-bytes", decodeBase64, .{
        .summary = "Decode base64 data from query parameter",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_base64_decode",
    });
}
