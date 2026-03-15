# Generate Clients

Generate typed API clients from your Zigmund application's OpenAPI specification. Use the built-in `/openapi.json` endpoint or `app.openapi()` method to produce the spec, then feed it to a code generator.

## Overview

Zigmund automatically generates a complete OpenAPI specification from your route definitions, parameter types, response models, and security schemes. This spec can be used with code generation tools to produce typed API clients in any language -- TypeScript, Python, Go, Rust, Java, and more.

This is the Zig equivalent of FastAPI's approach to client generation using the auto-generated OpenAPI spec.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// Demonstrates how to access the OpenAPI JSON spec for client generation.
/// Use app.openapi() to retrieve the full OpenAPI JSON document, which can
/// be fed to code generators (openapi-generator, oapi-codegen, etc.).
fn openapiSpec(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .openapi_url = "/openapi.json",
        .message = "Access /openapi.json for the full OpenAPI spec; use app.openapi() programmatically for client generation",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/client-info", openapiSpec, .{
        .summary = "OpenAPI spec access for client code generation",
    });
}
```

## How It Works

### 1. Accessing the OpenAPI Spec

Zigmund serves the OpenAPI specification at `/openapi.json` by default. You can also access it programmatically:

```zig
// Via HTTP (default endpoint)
// GET /openapi.json

// Programmatically
const spec = try app.openapi();
```

### 2. Popular Code Generators

Feed the OpenAPI spec to any compatible code generator:

| Tool                  | Target Languages              | Command Example                                           |
|-----------------------|-------------------------------|-----------------------------------------------------------|
| openapi-generator     | TypeScript, Python, Java, etc.| `openapi-generator generate -i openapi.json -g typescript-fetch -o client/` |
| oapi-codegen          | Go                            | `oapi-codegen -generate types,client openapi.json > client.go` |
| openapi-typescript    | TypeScript types              | `npx openapi-typescript openapi.json -o types.ts`         |
| swagger-codegen       | Many languages                | `swagger-codegen generate -i openapi.json -l python -o client/` |

### 3. Workflow

The typical workflow for generating clients:

1. **Start your Zigmund application** (or use the spec file directly).
2. **Download the OpenAPI spec**:
   ```bash
   curl http://localhost:8000/openapi.json -o openapi.json
   ```
3. **Run the code generator**:
   ```bash
   openapi-generator generate -i openapi.json -g typescript-fetch -o ./client
   ```
4. **Use the generated client** in your frontend or other services.

### 4. Improving Generated Code

The quality of generated clients depends on the quality of your OpenAPI spec. Zigmund features that improve generated code:

- **`operation_id`** -- controls method names in generated clients.
- **`response_model`** -- generates typed response schemas.
- **`tags`** -- groups operations into logical modules.
- **`summary` and `description`** -- become documentation comments in generated code.
- **`responses`** -- generates error handling types.

```zig
try app.get("/items/{item_id}", getItem, .{
    .operation_id = "getItem",           // becomes the method name
    .response_model = ItemResponse,       // generates a typed return type
    .tags = &.{"items"},                  // groups into an "items" module
    .summary = "Get a single item",       // becomes a doc comment
    .responses = &.{
        .{ .status_code = .not_found, .description = "Item not found" },
    },
});
```

### 5. Build-Time Spec Generation

For CI/CD pipelines, generate the spec at build time without starting a server:

```zig
// In a build script or CLI tool
var app = try zigmund.App.init(allocator, .{ ... });
defer app.deinit();

// Register all routes...

const spec = try app.openapi();
// Write spec to file or pipe to generator
```

## Key Points

- Zigmund automatically generates a complete OpenAPI spec from your route definitions.
- The spec is served at `/openapi.json` by default and can be accessed programmatically via `app.openapi()`.
- Use `operation_id`, `response_model`, `tags`, and `responses` to produce high-quality generated clients.
- Any OpenAPI-compatible code generator can consume the spec.
- Generate specs at build time for CI/CD integration without running a server.

## See Also

- [Path Operation Advanced Configuration](path-operation-advanced-configuration.md) -- configure operation IDs and response models.
- [OpenAPI Callbacks](openapi-callbacks.md) -- document callback URLs in the spec.
- [OpenAPI Webhooks](openapi-webhooks.md) -- document webhook events in the spec.
