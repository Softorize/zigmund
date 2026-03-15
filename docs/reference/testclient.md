# TestClient Reference

## Overview

`TestClient` provides an in-process HTTP and WebSocket test client for Zigmund applications. It dispatches requests through the full middleware and routing pipeline without starting a network server.

## TestClient

### Initialization

```zig
pub fn init(allocator: std.mem.Allocator, app: *App) TestClient
```

Creates a test client bound to the given application.

### `deinit`

```zig
pub fn deinit(self: *TestClient) void
```

Shuts down the client and frees resources, including running shutdown lifecycle hooks and clearing cookies.

### `start`

```zig
pub fn start(self: *TestClient) !void
```

Explicitly starts the application lifecycle (runs startup hooks). Called automatically on first request.

### `close`

```zig
pub fn close(self: *TestClient) !void
```

Runs shutdown hooks without fully deinitializing the client.

## HTTP Methods

### `get`

```zig
pub fn get(self: *TestClient, target: []const u8) !Response
```

Sends a GET request.

### `post`

```zig
pub fn post(self: *TestClient, target: []const u8, body: []const u8) !Response
```

Sends a POST request with the given body.

### `postWithHeaders`

```zig
pub fn postWithHeaders(self: *TestClient, target: []const u8, body: []const u8, headers: []const std.http.Header) !Response
```

Sends a POST request with custom headers.

### `request`

```zig
pub fn request(self: *TestClient, method: std.http.Method, target: []const u8, body: []const u8) !Response
```

Sends a request with any HTTP method.

### `requestWithHeaders`

```zig
pub fn requestWithHeaders(
    self: *TestClient,
    method: std.http.Method,
    target: []const u8,
    body: []const u8,
    headers: []const std.http.Header,
) !Response
```

Sends a request with custom headers.

## Cookie Management

The test client automatically tracks `Set-Cookie` headers from responses and includes them in subsequent requests.

### `cookie`

```zig
pub fn cookie(self: *const TestClient, name: []const u8) ?[]const u8
```

Returns the current value of a cookie by name.

### `clearCookies`

```zig
pub fn clearCookies(self: *TestClient) void
```

Clears all stored cookies.

## WebSocket Testing

### `websocketConnect`

```zig
pub fn websocketConnect(self: *TestClient, target: []const u8) !WebSocketSession
```

Establishes a WebSocket connection to the given path.

### `websocketConnectWithHeaders`

```zig
pub fn websocketConnectWithHeaders(
    self: *TestClient,
    target: []const u8,
    headers: []const std.http.Header,
) !WebSocketSession
```

Establishes a WebSocket connection with custom headers.

## WebSocketSession

Represents an active WebSocket connection for testing.

### `sendText`

```zig
pub fn sendText(self: *WebSocketSession, payload: []const u8) !void
```

Sends a text message.

### `sendBinary`

```zig
pub fn sendBinary(self: *WebSocketSession, payload: []const u8) !void
```

Sends a binary message.

### `ping`

```zig
pub fn ping(self: *WebSocketSession, payload: []const u8) !void
```

Sends a ping frame.

### `receiveSmall`

```zig
pub fn receiveSmall(self: *WebSocketSession) !Connection.Message
```

Receives the next message (blocks until available or timeout).

### `receiveSmallWithTimeout`

```zig
pub fn receiveSmallWithTimeout(self: *WebSocketSession, timeout_ms: u64) !Connection.Message
```

Receives with an explicit timeout.

### `subprotocol`

```zig
pub fn subprotocol(self: *const WebSocketSession) ?[]const u8
```

Returns the negotiated subprotocol, if any.

### `lastCloseCode`

```zig
pub fn lastCloseCode(self: *const WebSocketSession) ?u16
```

Returns the close code from the last close frame received.

### `close`

```zig
pub fn close(self: *WebSocketSession) void
```

Closes the WebSocket connection with code 1000.

### `closeWithCode`

```zig
pub fn closeWithCode(self: *WebSocketSession, code: u16, reason: []const u8) !void
```

Closes the connection with a specific code and reason.

### `handlerError`

```zig
pub fn handlerError(self: *const WebSocketSession) ?anyerror
```

Returns any error that occurred in the server-side handler.

### `deinit`

```zig
pub fn deinit(self: *WebSocketSession) void
```

Closes the session, joins the handler thread, and frees resources.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

test "GET /health returns 200" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "Test",
        .version = "0.1.0",
    });
    defer app.deinit();

    try app.get("/health", healthHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var res = try client.get("/health");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
}

test "WebSocket echo" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "Test",
        .version = "0.1.0",
    });
    defer app.deinit();

    try app.websocket("/ws", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var ws = try client.websocketConnect("/ws");
    defer ws.deinit();

    try ws.sendText("hello");
    const msg = try ws.receiveSmall();
    try std.testing.expectEqualStrings("hello", msg.data);
}
```
