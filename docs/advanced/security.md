# Security

Advanced security configuration in Zigmund: multi-scheme authentication, HTTP Basic Auth, and OAuth2 with scope enforcement. This page covers all three advanced security patterns.

## Overview

Zigmund provides a compile-time security system built around typed `Security()` parameters. Security schemes are declared as constants, registered with the application for OpenAPI documentation, and injected into handlers as parameters. The framework extracts credentials from requests automatically and passes them to the handler.

This page covers three advanced security patterns:

1. **Multi-scheme security** -- requiring multiple credentials (e.g., API key + Bearer token).
2. **HTTP Basic Auth** -- username/password authentication via the `Authorization` header.
3. **OAuth2 with scopes** -- token-based authentication with fine-grained permission control.

---

## Multi-Scheme Security

Require multiple security credentials on a single endpoint by declaring multiple `Security()` parameters.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// Multi-scheme security: require both an API key header and a Bearer token.
const api_key_scheme = zigmund.APIKeyHeader{ .name = "x-api-key" };
const bearer_scheme = zigmund.HTTPBearer{};

fn securedEndpoint(
    api_key: zigmund.Security(api_key_scheme, &.{}),
    token: zigmund.Security(bearer_scheme, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .api_key = api_key.value.?,
        .bearer_token = token.value.?,
        .message = "Authenticated with both API key and Bearer token",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Register both security schemes in OpenAPI documentation
    try app.addSecurityScheme("apiKeyHeader", .{
        .api_key = .{ .name = "x-api-key", .in = .header },
    });
    try app.addSecurityScheme("bearerAuth", .{
        .http = .{ .scheme = "bearer", .bearer_format = "JWT" },
    });

    try app.get("/secured", securedEndpoint, .{
        .summary = "Multi-scheme security requiring API key and Bearer token",
    });
}
```

### How It Works

1. **Declare scheme constants** -- define the security scheme as a compile-time constant:
   ```zig
   const api_key_scheme = zigmund.APIKeyHeader{ .name = "x-api-key" };
   const bearer_scheme = zigmund.HTTPBearer{};
   ```

2. **Use Security() parameters** -- declare one `Security()` parameter per required scheme:
   ```zig
   fn handler(
       api_key: zigmund.Security(api_key_scheme, &.{}),
       token: zigmund.Security(bearer_scheme, &.{}),
       allocator: std.mem.Allocator,
   ) !zigmund.Response { ... }
   ```

3. **Register schemes for OpenAPI** -- call `app.addSecurityScheme()` to make the schemes appear in the OpenAPI spec:
   ```zig
   try app.addSecurityScheme("apiKeyHeader", .{
       .api_key = .{ .name = "x-api-key", .in = .header },
   });
   ```

4. **Access credentials** -- use `security_param.value.?` to get the extracted credential value.

Available scheme types:

| Type                | Description                                  |
|---------------------|----------------------------------------------|
| `APIKeyHeader`      | API key sent in a custom header.             |
| `APIKeyQuery`       | API key sent as a query parameter.           |
| `HTTPBearer`        | Bearer token in the `Authorization` header.  |
| `HTTPBasic`         | Basic credentials in the `Authorization` header. |
| `OAuth2PasswordBearer` | OAuth2 password flow with token URL.      |

---

## HTTP Basic Auth

Extract and validate username/password credentials from the HTTP Basic `Authorization` header.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// HTTP Basic authentication: extracts and validates username/password
/// from the Authorization header using the HTTPBasic security scheme.
const basic_scheme = zigmund.HTTPBasic{};

fn basicAuthEndpoint(
    credentials: zigmund.Security(basic_scheme, &.{}),
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // credentials.value is the raw HTTPAuthorizationCredentials
    // For decoded username/password, use decodeBasicCredentials
    const raw_creds = credentials.value.?;
    var decoded = try zigmund.decodeBasicCredentials(allocator, raw_creds.credentials);
    defer decoded.deinit(allocator);

    _ = req;

    return zigmund.Response.json(allocator, .{
        .username = decoded.username,
        .message = "Authenticated via HTTP Basic",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addSecurityScheme("basicAuth", .{
        .http = .{ .scheme = "basic" },
    });

    try app.get("/basic-auth", basicAuthEndpoint, .{
        .summary = "HTTP Basic authentication with credential decoding",
    });
}
```

### How It Works

1. **Declare the HTTPBasic scheme**:
   ```zig
   const basic_scheme = zigmund.HTTPBasic{};
   ```

2. **Inject credentials** -- the `Security()` parameter extracts the raw `Authorization` header value:
   ```zig
   const raw_creds = credentials.value.?;
   ```

3. **Decode Base64 credentials** -- use `zigmund.decodeBasicCredentials()` to decode the Base64-encoded `username:password` string:
   ```zig
   var decoded = try zigmund.decodeBasicCredentials(allocator, raw_creds.credentials);
   defer decoded.deinit(allocator);
   ```

4. **Access username and password**:
   ```zig
   const username = decoded.username;
   // decoded.password is also available for validation
   ```

5. **Clean up** -- always call `decoded.deinit(allocator)` to release the decoded credential memory (use `defer`).

### Security Considerations

- Never store passwords in plain text. Compare the decoded password against a hashed value.
- HTTP Basic Auth sends credentials in Base64 (not encrypted). Always use HTTPS in production.
- Consider rate-limiting Basic Auth endpoints to prevent brute-force attacks.

---

## OAuth2 Scopes

Enforce fine-grained permissions using OAuth2 scopes. Handlers can require specific scopes, and the framework validates that the token includes the necessary permissions.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// OAuth2 with scope enforcement: the handler requires both "read" and "write"
/// scopes to be present in the bearer token.
const oauth2_scheme = zigmund.OAuth2PasswordBearer{
    .token_url = "/token",
    .scopes = &.{ "read", "write" },
};

fn scopedEndpoint(
    token: zigmund.Security(oauth2_scheme, &.{ "read", "write" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .token = token.value.?,
        .required_scopes = &[_][]const u8{ "read", "write" },
        .message = "Authorized with read and write scopes",
    });
}

fn readOnlyEndpoint(
    token: zigmund.Security(oauth2_scheme, &.{"read"}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .token = token.value.?,
        .required_scopes = &[_][]const u8{"read"},
        .message = "Authorized with read scope only",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addSecurityScheme("oauth2Scopes", .{
        .oauth2 = .{
            .flows = .{
                .password = .{
                    .token_url = "/token",
                    .scopes = &.{
                        .{ .name = "read", .description = "Read access" },
                        .{ .name = "write", .description = "Write access" },
                    },
                },
            },
        },
    });

    try app.get("/items", scopedEndpoint, .{
        .summary = "OAuth2 endpoint requiring read and write scopes",
    });

    try app.get("/items/read", readOnlyEndpoint, .{
        .summary = "OAuth2 endpoint requiring read scope only",
    });
}
```

### How It Works

1. **Define the OAuth2 scheme** with available scopes:
   ```zig
   const oauth2_scheme = zigmund.OAuth2PasswordBearer{
       .token_url = "/token",
       .scopes = &.{ "read", "write" },
   };
   ```

2. **Require specific scopes per handler** -- the second argument to `Security()` specifies the required scopes:
   ```zig
   // Requires both "read" and "write"
   token: zigmund.Security(oauth2_scheme, &.{ "read", "write" }),

   // Requires only "read"
   token: zigmund.Security(oauth2_scheme, &.{"read"}),
   ```

3. **Register the scheme for OpenAPI** -- the `scopes` field documents available scopes with descriptions:
   ```zig
   try app.addSecurityScheme("oauth2Scopes", .{
       .oauth2 = .{
           .flows = .{
               .password = .{
                   .token_url = "/token",
                   .scopes = &.{
                       .{ .name = "read", .description = "Read access" },
                       .{ .name = "write", .description = "Write access" },
                   },
               },
           },
       },
   });
   ```

4. **Access the token** -- `token.value.?` contains the bearer token string for further validation (JWT decoding, database lookup, etc.).

### Scope Enforcement Pattern

Different endpoints can require different subsets of scopes from the same OAuth2 scheme:

| Endpoint       | Required Scopes      | Access Level       |
|----------------|---------------------|--------------------|
| `GET /items`   | `read`, `write`     | Full access        |
| `GET /items/read` | `read`           | Read-only access   |

---

## Key Points

- Zigmund supports multiple security schemes on a single endpoint via multiple `Security()` parameters.
- `app.addSecurityScheme()` registers schemes for OpenAPI documentation (Swagger UI "Authorize" button).
- HTTP Basic credentials must be decoded with `zigmund.decodeBasicCredentials()` and cleaned up with `defer`.
- OAuth2 scopes are specified per-handler as the second argument to `Security()`.
- All security extraction and validation happens at the framework level before the handler runs.
- The actual credential validation (password checking, JWT verification) is the application's responsibility.

## See Also

- [Advanced Dependencies](advanced-dependencies.md) -- security schemes can be used as dependencies.
- [Middleware](middleware.md) -- apply security checks globally via middleware.
- [Testing Dependencies](testing-dependencies.md) -- mock security providers in tests.
