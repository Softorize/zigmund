# API Metadata and Tags

Set API-level metadata -- title, description, version -- and organize routes with tags to produce well-structured, professional OpenAPI documentation.

## Overview

Zigmund generates an OpenAPI specification automatically from your route registrations. The API-level metadata (title, version, description) and tag definitions control how documentation tools like Swagger UI and Redoc present your API at the top level. Route-level configuration (summaries, operation IDs, tags) fills in the details for each endpoint.

This page focuses on route-level metadata fields and how they contribute to the overall API documentation. API-level metadata is set when initializing the `App` (see the [First Steps](first-steps.md) tutorial for `App.init` options).

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn readMetadata(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .name = "zigmund",
        .docs = "/docs",
        .openapi = "/openapi.json",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/metadata", readMetadata, .{
        .name = "tutorial_metadata",
        .summary = "Read API metadata",
        .description = "Demonstrates metadata, tags, and operation IDs in route configuration.",
        .tags = &.{ "parity", "tutorial", "metadata" },
        .operation_id = "tutorial_read_metadata",
    });
}
```

## How It Works

1. **Route name.** `.name = "tutorial_metadata"` gives the route an internal identifier. This is used for programmatic URL reversal (generating a URL from a route name) and does not appear in the OpenAPI output.

2. **Summary.** `.summary = "Read API metadata"` provides a one-line description displayed next to the HTTP method and path in Swagger UI. Keep summaries concise.

3. **Description.** `.description = "Demonstrates metadata, tags, and operation IDs..."` supports Markdown and appears in the expanded operation detail panel. Use it for implementation notes, expected behavior, or example workflows.

4. **Tags.** `.tags = &.{ "parity", "tutorial", "metadata" }` assigns the route to one or more tag groups. In Swagger UI, tags become collapsible sections in the sidebar. A route can belong to multiple tags. The first tag typically determines the primary grouping.

5. **Operation ID.** `.operation_id = "tutorial_read_metadata"` sets a unique, stable identifier for the operation in the OpenAPI schema. Client code generators use this to name functions (e.g., `tutorialReadMetadata()` in a generated TypeScript client).

6. **Built-in documentation endpoints.** Zigmund serves interactive documentation at `/docs` (Swagger UI) and the raw OpenAPI specification at `/openapi.json`. The metadata you configure here directly controls what appears at those URLs.

## Key Points

- API-level metadata (title, version, description) is set once in `App.init`. Route-level metadata is set per route in the configuration struct. Together, they produce a complete OpenAPI document.
- Tags defined on routes are automatically collected into the top-level `tags` array of the OpenAPI schema. You do not need to declare them separately.
- Operation IDs must be unique across the entire API. If two routes share an operation ID, the OpenAPI spec is invalid. Zigmund derives a default from the handler name if you omit it.
- The `/docs` endpoint serves Swagger UI with no additional setup. The `/openapi.json` endpoint returns the raw JSON specification for consumption by code generators, API gateways, or other tools.
- All metadata fields are optional. You can register a route with `.{}` and get working defaults, then add metadata incrementally as your API matures.

## See Also

- [First Steps](first-steps.md) -- Setting API-level metadata in `App.init`.
- [Path Operation Configuration](path-operation-configuration.md) -- The full set of route configuration options, including `.responses`.
- [Schema Examples](schema-extra-example.md) -- Add example payloads to enrich your OpenAPI documentation further.
- [Bigger Applications](bigger-applications.md) -- Organizing tags and metadata across multiple routers.
