# Testing WebSockets

Test WebSocket handlers using `TestClient.websocketConnect()`. The test client creates an in-memory duplex connection that exercises the full WebSocket handler without a real network socket.

## Overview

WebSocket handlers need to be tested for correct message handling, echo behavior, error handling, and connection lifecycle. Zigmund's `TestClient` provides `websocketConnect()`, which returns an in-memory WebSocket connection that can send and receive messages synchronously -- no network stack required.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// Demonstrates WebSocket testing using TestClient.websocketConnect().
/// The test client creates an in-memory duplex connection that exercises
/// the full WebSocket handler without a real network socket.

fn echoHandler(conn: *zigmund.runtime.websocket.Connection, _: *zigmund.Request, _: std.mem.Allocator) anyerror!void {
    while (true) {
        const msg = conn.receiveSmall() catch |err| switch (err) {
            error.ConnectionClosed => return,
            else => return err,
        };

        switch (msg.opcode) {
            .text => try conn.sendText(msg.data),
            .binary => try conn.sendBinary(msg.data),
            else => {},
        }
    }
}

fn wsTestInfo(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .message = "WebSocket echo server for testing — connect at /ws",
    });
}

/// Example test usage:
///
///   var client = zigmund.TestClient.init(std.testing.allocator, &app);
///   defer client.deinit();
///
///   var ws = try client.websocketConnect("/ws");
///   defer ws.deinit();
///
///   try ws.sendText("hello");
///   const reply = try ws.receiveSmall();
///   // reply.data == "hello", reply.opcode == .text

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/ws/info", wsTestInfo, .{
        .summary = "WebSocket testing info endpoint",
    });

    try app.websocket("/ws", echoHandler, .{
        .summary = "WebSocket echo handler for TestClient testing",
    });
}
```

## How It Works

### 1. Setting Up a WebSocket Test

Create a `TestClient` and connect to a WebSocket endpoint:

```zig
var client = zigmund.TestClient.init(std.testing.allocator, &app);
defer client.deinit();

var ws = try client.websocketConnect("/ws");
defer ws.deinit();
```

The `websocketConnect()` method returns a test WebSocket connection that bypasses the network layer.

### 2. Sending Messages

Use the same API as production WebSocket connections:

```zig
try ws.sendText("hello");       // Send a text frame
try ws.sendBinary(&data_bytes); // Send a binary frame
```

### 3. Receiving Messages

Receive messages synchronously:

```zig
const reply = try ws.receiveSmall();
```

The returned message has:
- `reply.opcode` -- the frame type (`.text`, `.binary`, etc.).
- `reply.data` -- the payload as a byte slice.

### 4. Full Test Pattern

```zig
test "echo WebSocket handler" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "Test", .version = "1.0",
    });
    defer app.deinit();
    try buildExample(&app);

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var ws = try client.websocketConnect("/ws");
    defer ws.deinit();

    // Test text echo
    try ws.sendText("hello");
    const text_reply = try ws.receiveSmall();
    try std.testing.expectEqualStrings("hello", text_reply.data);
    try std.testing.expectEqual(.text, text_reply.opcode);

    // Test binary echo
    const binary_data = &[_]u8{ 0x01, 0x02, 0x03 };
    try ws.sendBinary(binary_data);
    const binary_reply = try ws.receiveSmall();
    try std.testing.expectEqualSlices(u8, binary_data, binary_reply.data);
    try std.testing.expectEqual(.binary, binary_reply.opcode);
}
```

### 5. Testing Connection Lifecycle

Test that the handler properly handles disconnections:

```zig
var ws = try client.websocketConnect("/ws");
// ws.deinit() closes the connection, which should cause
// the handler to receive error.ConnectionClosed and return cleanly
ws.deinit();
```

### 6. Testing Multiple Messages

Send and receive multiple messages in sequence to verify stateful handler behavior:

```zig
try ws.sendText("first");
const r1 = try ws.receiveSmall();

try ws.sendText("second");
const r2 = try ws.receiveSmall();

try ws.sendText("third");
const r3 = try ws.receiveSmall();
```

## Key Points

- `TestClient.websocketConnect()` creates an in-memory WebSocket connection for testing.
- The test connection uses the same API as production connections (`sendText`, `receiveSmall`, etc.).
- No network stack is involved -- tests run entirely in-process.
- Always use `defer ws.deinit()` to properly close the connection and clean up resources.
- Test both text and binary message types to ensure full handler coverage.
- Test the disconnection path by closing the connection and verifying graceful handler exit.

## See Also

- [WebSockets](websockets.md) -- production WebSocket handler patterns.
- [Testing Events](testing-events.md) -- test lifecycle hooks.
- [Async Tests](async-tests.md) -- integration testing patterns.
