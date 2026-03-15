# WebSocket Reference

## Overview

Zigmund provides built-in WebSocket support with configurable timeouts, ping/pong management, subprotocol negotiation, and origin validation.

## Handler Signature

WebSocket handlers must conform to one of these signatures:

```zig
// Full signature with request access
fn handler(conn: *Connection, req: *Request, allocator: std.mem.Allocator) !void

// Legacy signature without request
fn handler(conn: *Connection, allocator: std.mem.Allocator) !void
```

The handler receives a `Connection` for sending and receiving messages.

## Connection

### Sending Messages

```zig
pub fn sendText(self: *Connection, text: []const u8) !void
pub fn sendBinary(self: *Connection, payload: []const u8) !void
pub fn ping(self: *Connection, payload: []const u8) !void
```

### Receiving Messages

```zig
pub fn receiveSmall(self: *Connection) !Message
pub fn receiveSmallWithTimeout(self: *Connection, timeout_ms: u64) !Message
```

Returns a `Message` with `opcode` and `data` fields.

### Message Type

```zig
pub const Message = struct {
    opcode: Opcode,
    data: []u8,
};
```

Opcode values include `.text`, `.binary`, `.ping`, `.pong`, `.close`.

### Connection Configuration

```zig
pub fn setIdleTimeoutMs(self: *Connection, timeout_ms: ?u64) void
pub fn setAutoPong(self: *Connection, enabled: bool) void
pub fn setPingPolicy(self: *Connection, ping_interval_ms: ?u64, pong_timeout_ms: ?u64) void
pub fn setMaxMessageBytes(self: *Connection, max: ?usize) void
pub fn setSendTimeoutMs(self: *Connection, timeout_ms: ?u64) void
```

### Subprotocol

```zig
pub fn subprotocol(self: *const Connection) ?[]const u8
```

Returns the negotiated subprotocol, if any.

### Close

```zig
pub fn closeWithCode(self: *Connection, code: u16, reason: []const u8) !void
pub fn lastCloseCode(self: *const Connection) ?u16
```

## Route Registration

```zig
try app.websocket("/ws", handler, .{
    .idle_timeout_ms = 30000,
    .auto_pong = true,
    .ping_interval_ms = 15000,
    .pong_timeout_ms = 5000,
    .max_message_bytes = 65536,
    .allowed_origins = &.{"https://example.com"},
    .subprotocols = &.{"graphql-ws"},
});
```

## WebSocketRouteOptions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `?[]const u8` | `null` | Route name |
| `summary` | `?[]const u8` | `null` | OpenAPI summary |
| `description` | `?[]const u8` | `null` | OpenAPI description |
| `idle_timeout_ms` | `?u64` | `null` | Disconnect after this many idle ms |
| `auto_pong` | `bool` | `true` | Automatically respond to pings |
| `ping_interval_ms` | `?u64` | `null` | Send pings at this interval |
| `pong_timeout_ms` | `?u64` | `null` | Timeout waiting for pong |
| `max_message_bytes` | `?usize` | `null` | Maximum message size |
| `max_pending_messages` | `?usize` | `null` | Maximum pending messages in queue |
| `send_timeout_ms` | `?u64` | `null` | Send operation timeout |
| `allowed_origins` | `[]const []const u8` | `&.{}` | Allowed Origin headers (empty = allow all) |
| `subprotocols` | `[]const []const u8` | `&.{}` | Supported subprotocols |
| `require_subprotocol` | `bool` | `false` | Reject if no subprotocol matches |
| `dependencies` | `[]const DependencySpec` | `&.{}` | Route dependencies |
| `openapi_security` | `[]const OpenApiSecurityAlternative` | `&.{}` | Security requirements |
| `deprecated` | `bool` | `false` | Mark as deprecated |
| `operation_id` | `?[]const u8` | `null` | OpenAPI operation ID |
| `openapi_extensions` | `[]const OpenApiExtension` | `&.{}` | x- extensions |

## Example

```zig
fn chatHandler(conn: *zigmund.runtime.websocket.Connection, req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    _ = req;
    _ = allocator;

    while (true) {
        const msg = conn.receiveSmall() catch |err| {
            if (err == error.ConnectionClosed) return;
            return err;
        };

        switch (msg.opcode) {
            .text => try conn.sendText(msg.data),
            .binary => try conn.sendBinary(msg.data),
            .close => return,
            else => {},
        }
    }
}
```
