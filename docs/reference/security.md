# Security Reference

## Overview

Zigmund provides a comprehensive set of security scheme types that integrate with both the dependency injection system and OpenAPI security definitions. Each scheme type can resolve credentials from incoming requests and is used as a compile-time parameter via the `Security` marker.

## Security Marker

### `Security`

```zig
pub fn Security(comptime provider: anytype, scopes: []const []const u8) type
```

Declares a required security dependency. If the provider fails to resolve, the request is rejected with 401 Unauthorized.

### `SecurityOptional`

```zig
pub fn SecurityOptional(comptime provider: anytype, scopes: []const []const u8) type
```

Same as `Security`, but the request proceeds even if credentials are missing (the value will be `null`).

### `SecurityNamed`

```zig
pub fn SecurityNamed(comptime provider: anytype, name: []const u8, scopes: []const []const u8) type
```

Like `Security`, but registers the resolved value under a named dependency key.

### `SecurityNamedOptional`

```zig
pub fn SecurityNamedOptional(comptime provider: anytype, name: []const u8, scopes: []const []const u8) type
```

Combines named registration with optional resolution.

## API Key Schemes

### `APIKeyQuery`

```zig
pub const APIKeyQuery = struct {
    name: []const u8,
    auto_error: bool = true,
};
```

Extracts an API key from a query parameter.

### `APIKeyHeader`

```zig
pub const APIKeyHeader = struct {
    name: []const u8,
    auto_error: bool = true,
};
```

Extracts an API key from a request header.

### `APIKeyCookie`

```zig
pub const APIKeyCookie = struct {
    name: []const u8,
    auto_error: bool = true,
};
```

Extracts an API key from a cookie.

## HTTP Authentication Schemes

### `HTTPBasic`

```zig
pub const HTTPBasic = struct {
    auto_error: bool = true,
};
```

Resolves HTTP Basic authentication credentials. Use `resolveDecoded` to get parsed username/password.

**HTTPBasicCredentials:**

| Field | Type | Description |
|-------|------|-------------|
| `username` | `[]const u8` | Decoded username |
| `password` | `[]const u8` | Decoded password |
| `decoded` | `[]u8` | Owned decoded buffer (must call `deinit`) |

### `HTTPBearer`

```zig
pub const HTTPBearer = struct {
    auto_error: bool = true,
};
```

Resolves Bearer token from the `Authorization` header.

### `HTTPDigest`

```zig
pub const HTTPDigest = struct {
    auto_error: bool = true,
};
```

Resolves Digest authentication credentials from the `Authorization` header.

### `VerifiedHS256Bearer`

```zig
pub const VerifiedHS256Bearer = struct {
    secret: []const u8,
    validation: JwtValidationOptions = .{},
    auto_error: bool = true,
};
```

Resolves and validates an HS256-signed JWT bearer token.

**JwtValidationOptions:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `issuer` | `?[]const u8` | `null` | Expected issuer claim |
| `audience` | `?[]const u8` | `null` | Expected audience claim |
| `required_scopes` | `[]const []const u8` | `&.{}` | Scopes that must be present |
| `clock_skew_seconds` | `i64` | `60` | Allowed clock skew |
| `current_time_seconds` | `?i64` | `null` | Override current time (for testing) |

## OAuth2 Schemes

### `OAuth2PasswordBearer`

```zig
pub const OAuth2PasswordBearer = struct {
    token_url: []const u8,
    scopes: []const []const u8 = &.{},
    auto_error: bool = true,
};
```

### `OAuth2ClientCredentialsBearer`

```zig
pub const OAuth2ClientCredentialsBearer = struct {
    token_url: []const u8,
    scopes: []const []const u8 = &.{},
    auto_error: bool = true,
};
```

### `OAuth2ImplicitBearer`

```zig
pub const OAuth2ImplicitBearer = struct {
    authorization_url: []const u8,
    scopes: []const []const u8 = &.{},
    auto_error: bool = true,
};
```

### `OAuth2AuthorizationCodeBearer`

```zig
pub const OAuth2AuthorizationCodeBearer = struct {
    authorization_url: []const u8,
    token_url: []const u8,
    scopes: []const []const u8 = &.{},
    auto_error: bool = true,
};
```

### `OAuth2PasswordRequestForm`

```zig
pub const OAuth2PasswordRequestForm = struct {
    username: []const u8,
    password: []const u8,
    scope: []const u8 = "",
    grant_type: []const u8 = "password",
    client_id: ?[]const u8 = null,
    client_secret: ?[]const u8 = null,
};
```

Parse from a request with `OAuth2PasswordRequestForm.fromRequest(req)`.

## OpenID Connect

### `OpenIdConnect`

```zig
pub const OpenIdConnect = struct {
    openid_connect_url: []const u8,
    auto_error: bool = true,
};
```

## OpenAPI Security Scheme Registration

```zig
try app.addSecurityScheme("bearerAuth", .{
    .http = .{ .scheme = "bearer", .bearer_format = "JWT" },
});

try app.addSecurityScheme("apiKey", .{
    .api_key = .{ .name = "X-API-Key", .in = .header },
});

try app.addSecurityScheme("oauth2", .{
    .oauth2 = .{ .flows = .{
        .password = .{
            .token_url = "/token",
            .scopes = &.{
                .{ .name = "read", .description = "Read access" },
            },
        },
    }},
});
```

## Helper Functions

### `parseAuthorizationHeader`

```zig
pub fn parseAuthorizationHeader(raw: ?[]const u8) ?HTTPAuthorizationCredentials
```

Parses an `Authorization` header into scheme and credentials.

### `bearerTokenFromHeader`

```zig
pub fn bearerTokenFromHeader(raw: ?[]const u8) ?[]const u8
```

Extracts a bearer token from an `Authorization` header.

### `decodeBasicCredentials`

```zig
pub fn decodeBasicCredentials(allocator: std.mem.Allocator, encoded: []const u8) !HTTPBasicCredentials
```

Decodes base64-encoded Basic auth credentials into username and password.

### `validateHs256JwtToken`

```zig
pub fn validateHs256JwtToken(token: []const u8, secret: []const u8, options: JwtValidationOptions) !void
```

Validates an HS256 JWT token's signature, expiration, issuer, audience, and scopes.

### `signHs256JwtToken`

```zig
pub fn signHs256JwtToken(allocator: std.mem.Allocator, claims: anytype, secret: []const u8) ![]u8
```

Signs a claims payload as an HS256 JWT token.

### `parseScopesRawAlloc`

```zig
pub fn parseScopesRawAlloc(allocator: std.mem.Allocator, raw_scopes: []const u8) ![][]const u8
```

Splits a space/comma-separated scope string into individual scope values.

## Example

```zig
const bearer = zigmund.HTTPBearer{};

fn protectedHandler(
    token: zigmund.Security(bearer, &.{"read"}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .token = token.value.?,
    });
}
```
