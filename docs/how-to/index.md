# How-To Guides

Quick recipes for common tasks. Each guide focuses on a specific problem and provides a concise, copy-paste-ready solution.

These guides assume you are already familiar with Zigmund basics from the [Tutorial](../tutorial/index.md).

---

## OpenAPI and Documentation

- [Conditional OpenAPI](conditional-openapi.md) -- Enable or disable OpenAPI documentation based on environment or configuration.
- [Configure Swagger UI](configure-swagger-ui.md) -- Customize the Swagger UI appearance, behavior, and authentication settings.
- [Custom Docs UI Assets](custom-docs-ui-assets.md) -- Serve Swagger UI and ReDoc assets from your own CDN or local files.
- [Extending OpenAPI](extending-openapi.md) -- Add custom fields, vendor extensions, and additional metadata to the generated OpenAPI schema.
- [Separate OpenAPI Schemas](separate-openapi-schemas.md) -- Generate separate input and output schemas for request and response models.

## Authentication

- [Authentication Error Status Code](authentication-error-status-code.md) -- Customize the HTTP status code returned for authentication failures.

## Integration

- [GraphQL](graphql.md) -- Integrate a GraphQL endpoint alongside your REST API.

## Testing

- [Testing with Databases](testing-database.md) -- Set up test databases, transactions, and fixtures for integration tests.

## Migration

- [General Tips](general.md) -- General tips and patterns for building Zigmund applications.
- [Migrate from Pydantic v1 to v2](migrate-from-pydantic-v1-to-pydantic-v2.md) -- Migration notes for users coming from Python FastAPI with Pydantic model patterns.

## Custom Behavior

- [Custom Request and Route](custom-request-and-route.md) -- Extend the default `Request` and route handling with custom logic.
