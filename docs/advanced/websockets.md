# WebSockets

Zigmund provides first-class WebSocket support, allowing you to register WebSocket handlers alongside standard HTTP routes. Handlers receive a persistent connection object for full-duplex message exchange.

## Overview

WebSocket connections upgrade from HTTP to a persistent, bidirectional channel. In Zigmund, you register a WebSocket handler with `app.websocket()`, which receives a `Connection` object, the original `Request`, and an allocator. The handler runs in a loop, receiving messages and sending responses until the client disconnects.

This is the Zig equivalent of FastAPI's `@app.websocket()` decorator with `WebSocket` parameter injection.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// WebSocket chat-style handler: receives text messages and echoes them
/// back with a prefix. Demonstrates app.websocket() registration,
/// Connection.receiveSmall(), and Connection.sendText().
fn chatHandler(conn: *zigmund.runtime.websocket.Connection, _: *zigmund.Request, _: std.mem.Allocator) anyerror!void {
    // Send a welcome message on connect
    try conn.sendText("connected");

    while (true) {
        const msg = conn.receiveSmall() catch |err| switch (err) {
            error.ConnectionClosed => return,
            error.Timeout => continue,
            else => return err,
        };

        if (msg.opcode == .text) {
            // Echo with prefix
            var buf: [256]u8 = undefined;
            const reply = std.fmt.bufPrint(&buf, "echo: {s}", .{msg.data}) catch msg.data;
            try conn.sendText(reply);
        }
    }
}

fn websocketInfo(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .message = "WebSocket echo server — connect at /ws",
    });
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    var app = try zigmund.App.init(gpa.allocator(), .{
        .title = "WebSocket Demo",
        .version = "1.0",
    });
    defer app.deinit();

    try app.get("/info", websocketInfo, .{
        .summary = "WebSocket route info endpoint",
    });

    try app.websocket("/ws", chatHandler, .{
        .summary = "WebSocket echo handler with message prefix",
        .idle_timeout_ms = 30_000,
        .max_message_bytes = 4096,
    });

    try app.serve(.{});
}
```

## How It Works

### 1. Handler Signature

A WebSocket handler has the following signature:

```zig
fn handler(conn: *zigmund.runtime.websocket.Connection, req: *zigmund.Request, allocator: std.mem.Allocator) anyerror!void
```

- `conn` -- the WebSocket connection object, used to send and receive messages.
- `req` -- the original HTTP request that initiated the upgrade. Useful for reading headers, query parameters, or authentication tokens.
- `allocator` -- a per-connection arena allocator.

The handler runs for the lifetime of the connection. When the function returns, the connection is closed.

### 2. Registering a WebSocket Route

Use `app.websocket()` instead of `app.get()` or `app.post()`:

```zig
try app.websocket("/ws", chatHandler, .{
    .summary = "WebSocket echo handler",
    .idle_timeout_ms = 30_000,
    .max_message_bytes = 4096,
});
```

The options struct accepts:

| Field              | Type    | Description                                        |
|--------------------|---------|----------------------------------------------------|
| `summary`          | `[]const u8` | OpenAPI summary for the endpoint.             |
| `idle_timeout_ms`  | `u32`   | Milliseconds of inactivity before timeout.         |
| `max_message_bytes`| `u32`   | Maximum size of a single WebSocket message.        |

### 3. Receiving Messages

`conn.receiveSmall()` blocks until a message arrives or an error occurs. The returned message has two fields:

- `msg.opcode` -- the WebSocket frame type (`.text`, `.binary`, `.ping`, `.pong`, `.close`).
- `msg.data` -- the payload as a byte slice.

Always handle `error.ConnectionClosed` to exit the loop gracefully when the client disconnects. Handle `error.Timeout` to continue waiting if idle timeout is configured.

### 4. Sending Messages

- `conn.sendText(data)` -- send a text frame.
- `conn.sendBinary(data)` -- send a binary frame.

Both return an error if the connection has been closed.

### 5. Connection Lifecycle

The typical pattern is a `while (true)` loop that receives messages, processes them, and sends replies. The loop exits when the client disconnects (caught via `error.ConnectionClosed`). Any cleanup needed at disconnect can be placed after the loop or in a `defer` block.

## Key Points

- WebSocket routes are registered with `app.websocket()`, not the standard HTTP verb methods.
- The handler runs in its own execution context for the lifetime of the connection.
- `receiveSmall()` is suitable for messages that fit in a stack buffer. For large messages, use `receive()` with heap allocation.
- Always handle `error.ConnectionClosed` to avoid crashing when clients disconnect.
- You can send a welcome message immediately upon connection before entering the receive loop.
- WebSocket routes appear in the OpenAPI documentation with their summary and configuration.

## See Also

- [Testing WebSockets](testing-websockets.md) -- test WebSocket handlers with `TestClient`.
- [Stream Data](stream-data.md) -- server-sent events as an alternative to WebSockets.
- [Using the Request Directly](using-request-directly.md) -- access request headers and query parameters in handlers.
