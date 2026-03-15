# Debugging

Enable structured observability sinks -- access logs, telemetry, and traces -- to diagnose request handling, inspect routing decisions, and troubleshoot issues during development.

## Overview

When something goes wrong in a web application, you need visibility into what the framework is doing: which routes matched, what parameters were extracted, how long the handler took, and what the response looked like. Zigmund provides three built-in observability sinks that emit structured JSON to standard output, giving you machine-readable logs that are easy to search and filter.

| Sink                     | Method                         | What It Logs                                    |
|--------------------------|--------------------------------|------------------------------------------------|
| Access log               | `enableJsonAccessLogSink()`    | HTTP method, path, status code, response time. |
| Telemetry                | `enableJsonTelemetrySink()`    | Parameter extraction, dependency resolution, handler timing. |
| Trace                    | `enableJsonTraceSink()`        | Low-level routing decisions, middleware chain, error details. |

Enable sinks selectively. Access logs are useful in all environments; telemetry and trace sinks are typically enabled only during development or debugging sessions.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn debugInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .request_id = req.requestId() orelse "none",
        .method = @tagName(req.method),
        .path = req.path,
        .debug = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Enable structured observability sinks for development debugging
    app.enableJsonAccessLogSink();
    app.enableJsonTelemetrySink();
    app.enableJsonTraceSink();

    try app.get("/tutorial/debugging", debugInfo, .{
        .summary = "Debug endpoint with verbose observability sinks enabled",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_debugging_info",
    });
}
```

## How It Works

1. **Enable sinks on the app.** Call `enableJsonAccessLogSink()`, `enableJsonTelemetrySink()`, and/or `enableJsonTraceSink()` on the `App` instance before starting the server. Each call activates the corresponding sink.

2. **Access log sink.** Emits one JSON line per request after the response is sent. Includes the HTTP method, path, response status code, and wall-clock duration. This is the minimum observability level for any deployed application.

3. **Telemetry sink.** Emits detailed timing information for each phase of request processing: parameter extraction, dependency resolution, handler execution, and serialization. Use this to identify bottlenecks.

4. **Trace sink.** Emits low-level diagnostic events: which routes were considered during routing, which middleware ran, and full error details for failed requests. This produces high-volume output and is intended for debugging specific issues, not continuous use.

5. **Request introspection.** The handler demonstrates accessing request metadata directly:
   - `req.requestId()` returns the framework-assigned request ID (useful for correlating log entries).
   - `req.method` is the HTTP method as an enum.
   - `req.path` is the raw request path.

## Key Points

- All sinks emit newline-delimited JSON (one JSON object per line), making them compatible with log aggregation tools like `jq`, Loki, Datadog, and Elasticsearch.
- Sinks are additive. You can enable any combination of the three. Each operates independently.
- The access log sink is lightweight and suitable for production. The telemetry and trace sinks add overhead and are intended for development or temporary debugging.
- `req.requestId()` returns an optional string. If request ID generation is disabled in the app configuration, it returns `null`.
- Sink output goes to standard output (`stdout`). Redirect it to a file or pipe it to a log collector as needed.
- Sinks do not affect response content or behavior. They are purely observational.

## See Also

- [Middleware](middleware.md) -- Add custom request/response logging or timing via middleware.
- [Handling Errors](handling-errors.md) -- Customize error responses and see how errors appear in trace logs.
- [Testing](testing.md) -- The `TestClient` captures log output for assertion in tests.
- [Background Tasks](background-tasks.md) -- Background task execution is also visible in telemetry and trace sinks.
