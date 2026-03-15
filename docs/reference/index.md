# API Reference

Complete reference documentation for all public types, functions, and configuration options in Zigmund.

For introductory material and usage examples, see the [Tutorial](../tutorial/index.md). For advanced patterns, see the [Advanced](../advanced/index.md) section.

---

## Core

- [App](app.md) -- The main application type: initialization, route registration, configuration, and server startup.
- [Router](router.md) -- The `Router` type for composing route groups with shared prefixes, tags, and dependencies.
- [Request](request.md) -- The `Request` object: headers, body, path parameters, query parameters, cookies, client info, and state.
- [Response](response.md) -- The `Response` type: JSON, HTML, plain text, redirect, streaming, and file responses.
- [Responses](responses.md) -- Pre-built response types and response class helpers.

## Parameters

- [Parameters](parameters.md) -- Parameter marker functions: `Query`, `Path`, `Header`, `Cookie`, `Body`, `Form`, `File`, and their configuration options.

## Dependencies

- [Dependencies](dependencies.md) -- The `Depends` marker, dependency resolution, scoped lifetimes, and the dependency registry API.

## Security

- [Security](security.md) -- Security scheme types: `APIKey`, `HTTPAuth`, `OAuth2`, `OpenIDConnect`, and the `Security` marker function.

## Middleware

- [Middleware](middleware.md) -- Built-in middleware reference: CORS, compression, rate limiting, CSRF, sessions, timeouts, HTTPS redirect, trusted hosts, and correlation IDs.

## Error Handling

- [Exceptions](exceptions.md) -- Exception handler registration, `HTTPException`, validation error format, and custom error responses.

## HTTP

- [Status](status.md) -- HTTP status code constants and helpers.
- [HTTP Connection](httpconnection.md) -- Low-level HTTP connection details and the `HTTPConnection` type.

## OpenAPI

- [OpenAPI](openapi.md) -- OpenAPI 3.1 schema generation, customization options, and the docs UI configuration.

## Testing

- [TestClient](testclient.md) -- The in-process `TestClient` for integration testing: making requests, inspecting responses, cookie persistence, and WebSocket sessions.

## File Handling

- [UploadFile](uploadfile.md) -- The `UploadFile` type for handling multipart file uploads: reading, streaming, and metadata.
- [Static Files](staticfiles.md) -- The `StaticFiles` integration for serving static assets from directories.

## Background Processing

- [Background](background.md) -- The background task API: scheduling tasks, passing arguments, and execution guarantees.

## Templating

- [Templating](templating.md) -- The built-in template engine: loading templates, rendering with context, filters, and template inheritance.

## Serialization

- [Encoders](encoders.md) -- JSON encoding customization, custom serializers, and response body encoding.

## WebSockets

- [WebSockets](websockets.md) -- WebSocket upgrade handling, message types, connection lifecycle, and the WebSocket API.
