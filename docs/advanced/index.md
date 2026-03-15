# Advanced

This section covers advanced features and patterns for experienced Zigmund users. These topics assume familiarity with the concepts covered in the [Tutorial](../tutorial/index.md).

---

## Responses

- [Additional Status Codes](additional-status-codes.md) -- Return different response models for different HTTP status codes.
- [Additional Responses](additional-responses.md) -- Document additional response types in OpenAPI beyond the default.
- [Response Directly](response-directly.md) -- Bypass response models and return raw `Response` objects.
- [Custom Response](custom-response.md) -- Create custom response types: HTML, plain text, streaming, file downloads, and redirects.
- [Response Headers](response-headers.md) -- Set custom response headers.
- [Response Cookies](response-cookies.md) -- Set, update, and delete cookies in responses.
- [Response Change Status Code](response-change-status-code.md) -- Modify the status code dynamically within a handler.

## Advanced Dependencies

- [Advanced Dependencies](advanced-dependencies.md) -- Complex dependency patterns: parameterized dependencies, factory functions, and advanced scoping.
- [Testing Dependencies](testing-dependencies.md) -- Override dependencies in tests for mocking and isolation.

## Security

- [Security](security.md) -- Advanced security configuration beyond the tutorial basics.
- [HTTP Basic Auth](security-http-basic-auth.md) -- HTTP Basic authentication scheme.
- [OAuth2 Scopes](security-oauth2-scopes.md) -- Fine-grained permission control with OAuth2 scopes.

## Middleware

- [Middleware](middleware.md) -- Advanced middleware patterns: ordering, conditional application, and custom middleware classes.

## WebSockets

- [WebSockets](websockets.md) -- Full-duplex WebSocket connections: upgrade handling, message loops, and broadcasting.
- [Testing WebSockets](testing-websockets.md) -- Test WebSocket handlers with the `TestClient`.

## OpenAPI

- [Path Operation Advanced Configuration](path-operation-advanced-configuration.md) -- Advanced OpenAPI path operation settings: operation IDs, callbacks, and schema overrides.
- [OpenAPI Callbacks](openapi-callbacks.md) -- Document webhook-style callback URLs in your OpenAPI spec.
- [OpenAPI Webhooks](openapi-webhooks.md) -- Define webhook event schemas for OpenAPI 3.1.

## Application Architecture

- [Sub-Applications](sub-applications.md) -- Mount independent Zigmund applications at sub-paths.
- [Behind a Proxy](behind-a-proxy.md) -- Configure Zigmund to work behind reverse proxies (Nginx, Caddy, load balancers).
- [Using the Request Directly](using-request-directly.md) -- Access the raw request object for low-level control.
- [Strict Content Type](strict-content-type.md) -- Enforce strict `Content-Type` validation on incoming requests.

## Streaming

- [Stream Data](stream-data.md) -- Stream large responses: chunked transfer encoding, server-sent events, and generator patterns.

## Serialization

- [JSON, Base64, and Bytes](json-base64-bytes.md) -- Handle binary data, Base64 encoding, and raw byte responses.
- [Advanced Python Types](advanced-python-types.md) -- Zig equivalents of advanced Python/Pydantic types.
- [Dataclasses](dataclasses.md) -- Zig struct patterns that correspond to Python dataclasses.

## Lifecycle

- [Events](events.md) -- Startup and shutdown event hooks for initialization and cleanup.
- [Testing Events](testing-events.md) -- Test startup/shutdown event handlers.
- [Async Tests](async-tests.md) -- Patterns for testing concurrent and async behavior.

## Client Generation

- [Generate Clients](generate-clients.md) -- Generate typed API clients from your OpenAPI spec.

## Interoperability

- [WSGI](wsgi.md) -- Interoperability notes for WSGI-based systems (Python migration context).
