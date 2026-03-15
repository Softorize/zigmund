# How to Customize Request Context and Route Wrapping

This recipe shows how to attach custom state to every request and wrap all routes with cross-cutting behavior.

## Problem

You want to enrich every incoming request with custom data (such as a trace ID) and wrap every route handler with additional logic (such as adding response headers).

## Solution

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const RequestInfo = struct {
    trace: []u8,
};

fn cleanupRequestInfo(raw: ?*anyopaque, allocator: std.mem.Allocator) void {
    const info: *RequestInfo = @ptrCast(@alignCast(raw orelse return));
    allocator.free(info.trace);
    allocator.destroy(info);
}

fn installCustomRequest(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    const info = try allocator.create(RequestInfo);
    errdefer allocator.destroy(info);

    info.trace = try allocator.dupe(u8, req.header("x-trace-id") orelse "generated-trace");
    errdefer allocator.free(info.trace);

    try req.setStateOwned("custom_request", info, cleanupRequestInfo);
}

fn traceWrappingRoute(
    req: *zigmund.Request,
    next: zigmund.core.HttpHandler,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const info = req.stateAs(*RequestInfo, "custom_request")
        orelse return error.MissingCustomRequestState;
    var response = try next(req, allocator);
    errdefer response.deinit(allocator);
    try response.setHeader(allocator, "x-route-trace", info.trace);
    return response;
}

fn myHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const info = req.stateAs(*RequestInfo, "custom_request")
        orelse return error.MissingCustomRequestState;
    return zigmund.Response.json(allocator, .{
        .trace = info.trace,
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try zigmund.App.init(allocator, .{
        .title = "My API",
        .version = "1.0.0",
    });
    defer app.deinit();

    app.setRequestCustomizer(installCustomRequest);
    app.setDefaultRouteWrapper(traceWrappingRoute);

    try app.get("/hello", myHandler, .{});

    try app.serve(.{ .port = 8080 });
}
```

## Explanation

Zigmund provides two extension points for cross-cutting concerns:

1. **Request customizer** (`app.setRequestCustomizer`) -- A function called on every incoming request before route dispatch. Use it to parse headers, create objects, and attach them to the request via `req.setStateOwned` or `req.setStateBorrowed`. The state is accessible later via `req.stateAs`.

2. **Default route wrapper** (`app.setDefaultRouteWrapper`) -- A function that wraps every route handler. It receives the request, the next handler in the chain, and the allocator. Call `next(req, allocator)` to invoke the actual handler, then modify the response before returning it.

The `setStateOwned` method takes a cleanup function that is called automatically when the request is freed, preventing memory leaks.

## See Also

- [Request Reference](../reference/request.md)
- [Middleware Reference](../reference/middleware.md)
- [App Reference](../reference/app.md)
