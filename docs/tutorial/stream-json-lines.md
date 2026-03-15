# Stream JSON Lines

Stream newline-delimited JSON (NDJSON) responses for large datasets, real-time feeds, or progressive loading, sending data to the client incrementally instead of buffering the entire response in memory.

## Overview

Standard JSON responses require the entire payload to be serialized into memory before sending. For large result sets or real-time event streams, this is impractical. Newline-delimited JSON (NDJSON, also called JSON Lines) solves this by sending one complete JSON object per line, allowing the client to process each object as it arrives.

Zigmund supports NDJSON through `Response.streamChunks`, which accepts a list of pre-serialized chunks and streams them to the client with the `application/x-ndjson` content type. The response uses chunked transfer encoding, so the client begins receiving data before the server finishes sending.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    const chunks = [_][]const u8{
        "{\"page\":\"tutorial/stream-json-lines/\",\"step\":1}\n",
        "{\"page\":\"tutorial/stream-json-lines/\",\"step\":2}\n",
        "{\"done\":true}\n",
    };
    return zigmund.Response.streamChunks(allocator, &chunks, "application/x-ndjson");
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/stream-json-lines", implemented, .{
        .summary = "Parity implementation for tutorial/stream-json-lines/",
        .tags = &.{ "parity", "tutorial" },
    });
}
```

## How It Works

1. **Prepare the chunks.** Each element in the `chunks` array is a complete JSON object followed by a newline character (`\n`). The newline is the delimiter that separates objects in the NDJSON format.

2. **Call `streamChunks`.** `zigmund.Response.streamChunks(allocator, &chunks, "application/x-ndjson")` creates a streaming response. The three arguments are:
   - `allocator` -- Used internally for response bookkeeping.
   - `&chunks` -- A pointer to the array of byte slices to stream.
   - `"application/x-ndjson"` -- The content type header, signaling to clients that this is a newline-delimited JSON stream.

3. **Chunked transfer.** The framework sends each chunk as a separate HTTP chunk using chunked transfer encoding. The client can begin parsing the first JSON object while subsequent objects are still being sent.

4. **Client processing.** On the client side, each line can be parsed independently as a complete JSON object. This works naturally with tools like `curl`, JavaScript's `fetch` with a streaming reader, or server-sent event libraries.

The example produces three lines of output:

```
{"page":"tutorial/stream-json-lines/","step":1}
{"page":"tutorial/stream-json-lines/","step":2}
{"done":true}
```

## Key Points

- Each chunk must be a complete, self-contained JSON object followed by a newline. Do not split a single JSON object across multiple chunks.
- The content type `application/x-ndjson` is the standard MIME type for newline-delimited JSON. Some clients may also accept `application/jsonl` or `text/plain`.
- Streaming is particularly useful for:
  - **Large query results** where buffering the entire response would consume too much memory.
  - **Real-time feeds** where new data arrives continuously.
  - **Progress reporting** where each chunk represents a step in a long-running operation.
- In this example, chunks are static arrays. In production, you would typically generate chunks dynamically from a database cursor, event stream, or computation pipeline.
- The allocator is used for internal response management, not for the chunk data itself. The chunks must remain valid until the response is fully sent.
- Streaming responses bypass the standard `Response.json` serialization path. You are responsible for ensuring each chunk is valid JSON.

## See Also

- [Custom JSON Encoding](encoder.md) -- Serialize Zig structs to JSON for use as stream chunks.
- [Response Model](response-model.md) -- Standard (non-streaming) response shaping.
- [Background Tasks](background-tasks.md) -- An alternative for deferred processing when streaming is not needed.
- [Middleware](middleware.md) -- Middleware runs before and after streaming responses, just like regular responses.
