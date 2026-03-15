# Tutorial

This tutorial walks you through every major feature of Zigmund, step by step. Each page builds on concepts introduced earlier, so working through them in order is recommended if you are new to the framework.

If you have not set up your project yet, start with the [Installation Guide](../installation.md).

---

## Foundations

- [First Steps](first-steps.md) -- Your first Zigmund application: create an app, register a route, and run the server.
- [Path Parameters](path-parameters.md) -- Extract typed values from URL paths using `{name}` placeholders.
- [Query Parameters](query-parameters.md) -- Handle query string parameters with automatic type conversion.
- [Request Body](request-body.md) -- Parse JSON request bodies into Zig structs.

## Parameter Validation

- [Query Parameter String Validations](query-params-str-validations.md) -- Apply min/max length, regex patterns, and other string constraints to query parameters.
- [Path Parameter Numeric Validations](path-params-numeric-validations.md) -- Apply min/max value, multiple-of, and other numeric constraints to path parameters.
- [Query Parameter Models](query-param-models.md) -- Group related query parameters into a single struct model.

## Request Body Deep Dive

- [Multiple Body Parameters](body-multiple-params.md) -- Accept multiple distinct body parameters in a single endpoint.
- [Body Fields](body-fields.md) -- Apply field-level validation rules to body struct fields.
- [Nested Models](body-nested-models.md) -- Use nested Zig structs to model complex JSON payloads.
- [Partial Updates](body-updates.md) -- Handle PATCH requests with optional fields for partial updates.

## Additional Parameter Sources

- [Extra Data Types](extra-data-types.md) -- Work with timestamps, durations, and specialized numeric types.
- [Cookie Parameters](cookie-params.md) -- Read and validate browser cookies.
- [Cookie Parameter Models](cookie-param-models.md) -- Group cookie parameters into structured models.
- [Header Parameters](header-params.md) -- Extract and validate HTTP request headers.
- [Header Parameter Models](header-param-models.md) -- Group header parameters into structured models.

## Responses

- [Response Model](response-model.md) -- Filter and shape response fields using response models.
- [Extra Models](extra-models.md) -- Define multiple response models for different status codes.
- [Response Status Code](response-status-code.md) -- Set custom HTTP status codes on responses.
- [Custom JSON Encoding](encoder.md) -- Customize how values are serialized to JSON.

## Form Data and File Uploads

- [Request Forms](request-forms.md) -- Handle HTML form submissions with `application/x-www-form-urlencoded` data.
- [Request Form Models](request-form-models.md) -- Map form fields to Zig struct models.
- [Request Files](request-files.md) -- Handle file uploads with `multipart/form-data`.
- [Forms and Files](request-forms-and-files.md) -- Combine form fields and file uploads in a single request.

## Error Handling

- [Handling Errors](handling-errors.md) -- Define custom exception handlers, return structured error responses, and override default error behavior.

## Route Configuration

- [Path Operation Configuration](path-operation-configuration.md) -- Configure route summaries, descriptions, tags, deprecation, and OpenAPI metadata.
- [Schema Examples](schema-extra-example.md) -- Add example values to your OpenAPI schema for documentation.
- [API Metadata and Tags](metadata.md) -- Set API-level title, description, version, and organize routes with tags.

## Dependency Injection

- [Dependencies](dependencies.md) -- The dependency injection system: declare dependencies, use sub-dependencies, apply them globally or per-route, and manage cleanup with scoped lifetimes.

## Security and Authentication

- [Security](security.md) -- Authentication and authorization: OAuth2 password flow, JWT tokens, API keys, HTTP Basic auth, and security scopes.

## Middleware

- [Middleware](middleware.md) -- Add request/response middleware for logging, timing, headers, and custom processing.
- [CORS](cors.md) -- Configure Cross-Origin Resource Sharing for browser clients.

## Background Processing

- [Background Tasks](background-tasks.md) -- Run tasks after the response is sent, for email notifications, logging, and other deferred work.

## Static Files and Templates

- [Static Files](static-files.md) -- Serve static assets (CSS, JS, images) from a directory.

## Database Integration

- [SQL Databases](sql-databases.md) -- Integrate with SQL databases using Zigmund's database helpers.

## Application Structure

- [Bigger Applications](bigger-applications.md) -- Organize large applications with multiple routers, file structure conventions, and router composition.
- [Custom Index Page](index-page.md) -- Replace the default root page with a custom handler or static file.

## Development and Testing

- [Debugging](debugging.md) -- Debug helpers, request logging, and troubleshooting techniques.
- [Testing](testing.md) -- Write integration tests using the in-process `TestClient` without starting a real server.

## Streaming

- [Stream JSON Lines](stream-json-lines.md) -- Stream newline-delimited JSON responses for large datasets or real-time feeds.
