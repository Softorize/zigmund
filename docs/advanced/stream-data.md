# Stream Data

Stream large responses using Server-Sent Events (SSE). Zigmund provides `Response.eventStream()` for sending structured event streams to clients.

## Overview

Server-Sent Events (SSE) enable the server to push data to clients over a long-lived HTTP connection. Unlike WebSockets, SSE is unidirectional (server-to-client) and uses standard HTTP, making it simpler to deploy behind proxies and load balancers. Common use cases include real-time notifications, progress updates, and live data feeds.

This is the Zig equivalent of FastAPI's `StreamingResponse` and SSE patterns.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn streamEvents(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    const events = [_]zigmund.Response.ServerSentEvent{
        .{
            .id = "1",
            .event = "parity",
            .retry_ms = 1500,
            .data = "{\"page\":\"advanced/stream-data/\",\"status\":\"ok\"}",
        },
        .{
            .id = "2",
            .event = "parity",
            .data = "{\"done\":true}",
        },
    };
    return zigmund.Response.eventStream(allocator, &events);
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/events", streamEvents, .{
        .summary = "Stream data via Server-Sent Events",
    });
}
```

## How It Works

### 1. Server-Sent Events Format

SSE uses a simple text-based protocol. Each event consists of named fields separated by newlines:

```
id: 1
event: parity
retry: 1500
data: {"page":"advanced/stream-data/","status":"ok"}

id: 2
event: parity
data: {"done":true}

```

Zigmund's `Response.eventStream()` formats events according to this protocol automatically.

### 2. Defining Events

Create an array of `ServerSentEvent` structs:

```zig
const events = [_]zigmund.Response.ServerSentEvent{
    .{
        .id = "1",                    // Event ID for client reconnection
        .event = "parity",            // Event type name
        .retry_ms = 1500,             // Reconnection interval hint (ms)
        .data = "{\"status\":\"ok\"}", // Event payload (any string)
    },
    .{
        .id = "2",
        .event = "parity",
        .data = "{\"done\":true}",
    },
};
```

Each field is optional:

| Field      | Type           | Description                                              |
|------------|----------------|----------------------------------------------------------|
| `id`       | `?[]const u8`  | Event ID. Clients send `Last-Event-ID` on reconnection.  |
| `event`    | `?[]const u8`  | Event type name. Clients listen with `addEventListener`. |
| `retry_ms` | `?u64`         | Milliseconds before client retries on disconnect.        |
| `data`     | `[]const u8`   | The event payload. Can be any string (often JSON).       |

### 3. Creating the Response

Pass the events array to `Response.eventStream()`:

```zig
return zigmund.Response.eventStream(allocator, &events);
```

This sets `Content-Type: text/event-stream` and formats all events according to the SSE specification.

### 4. Client-Side Consumption

Clients use the standard `EventSource` API in JavaScript:

```javascript
const source = new EventSource("/events");

source.addEventListener("parity", function(event) {
    const data = JSON.parse(event.data);
    console.log("Received:", data);
});

source.onerror = function() {
    console.log("Connection lost, will retry...");
};
```

The browser automatically reconnects on connection loss, using the `retry` interval and `Last-Event-ID` header.

### 5. SSE vs. WebSockets

| Feature          | SSE                          | WebSockets                    |
|------------------|------------------------------|-------------------------------|
| Direction        | Server-to-client only        | Bidirectional                 |
| Protocol         | HTTP                         | WS (upgraded from HTTP)       |
| Reconnection     | Automatic (built-in)         | Manual                        |
| Proxy support    | Standard HTTP proxies        | Requires WebSocket support    |
| Complexity       | Simple                       | More complex                  |
| Use case         | Notifications, feeds         | Chat, real-time collaboration |

## Key Points

- `Response.eventStream()` creates an SSE response with proper `Content-Type` and formatting.
- Events support `id`, `event`, `retry_ms`, and `data` fields.
- SSE is simpler than WebSockets and works through standard HTTP proxies.
- Clients automatically reconnect using the `EventSource` API.
- Use JSON strings as event data for structured payloads.
- SSE is unidirectional -- use WebSockets if you need client-to-server communication.

## See Also

- [WebSockets](websockets.md) -- bidirectional real-time communication.
- [Custom Response](custom-response.md) -- other response types.
- [Response Headers](response-headers.md) -- add custom headers to streaming responses.
