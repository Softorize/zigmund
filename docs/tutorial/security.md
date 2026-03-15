# Security

Zigmund provides a type-safe security system for protecting endpoints with API keys, bearer tokens, OAuth2 password flows, and JWT validation. Security providers are declared as handler parameters using the `zigmund.Security()` marker type.

## Overview

Security in Zigmund follows the same pattern as dependency injection: you write a provider function that extracts and validates credentials from the request, then declare it in your handler's parameter list with `zigmund.Security()`. Zigmund resolves the provider before the handler runs. If the provider returns `null`, Zigmund responds with `401 Unauthorized` automatically.

Security schemes are also registered with the application so they appear in the generated OpenAPI documentation, giving API consumers clear instructions on how to authenticate.

---

## Security First Steps

The simplest security setup is a provider function that extracts a token from the request. The `zigmund.Security()` marker tells Zigmund to treat the parameter as a security dependency.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn tokenProvider(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const bearer = zigmund.HTTPBearer{};
    const auth = (try bearer.resolve(req)) orelse return null;
    return auth.credentials;
}

fn readCurrentToken(
    token: zigmund.Security(tokenProvider, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .token = token.value.?,
        .authenticated = true,
    });
}
```

Register the security scheme and route:

```zig
try app.addSecurityScheme("bearerAuth", .{
    .http = .{
        .scheme = "bearer",
        .bearer_format = "JWT",
    },
});

try app.get("/me", readCurrentToken, .{});
```

### How It Works

1. `tokenProvider` uses `zigmund.HTTPBearer{}` to extract the `Authorization: Bearer <token>` header.
2. If no token is present, the provider returns `null`, and Zigmund responds with 401.
3. The handler receives the resolved token through `token.value.?`.
4. `addSecurityScheme` registers the scheme in the OpenAPI spec so Swagger UI shows the "Authorize" button.

### Key Points

- The provider function must return an optional type (`!?T`). Returning `null` triggers a 401 response.
- The second argument to `Security()` is a tuple of scope strings (`&.{}`). Use `&.{}` when no scopes are required.
- Always register a matching security scheme with `addSecurityScheme` so the OpenAPI documentation is accurate.

---

## API Key Authentication

API keys can be sent in headers, query parameters, or cookies. Zigmund provides built-in helpers for each location.

### Header API Key

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn apiKeyProvider(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const scheme = zigmund.APIKeyHeader{ .name = "x-api-key" };
    return scheme.resolve(req);
}

fn readApiKey(
    api_key: zigmund.Security(apiKeyProvider, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .api_key = api_key.value.?,
        .authenticated = true,
    });
}
```

Register the scheme:

```zig
try app.addSecurityScheme("apiKeyAuth", .{
    .api_key = .{
        .name = "x-api-key",
        .in = .header,
    },
});

try app.get("/api-key", readApiKey, .{});
```

### How It Works

1. `zigmund.APIKeyHeader{ .name = "x-api-key" }` creates a resolver that looks for the `x-api-key` request header.
2. `scheme.resolve(req)` returns the header value or `null` if missing.
3. The security scheme registration tells OpenAPI that clients must send the `x-api-key` header.

### Key Points

- Use `zigmund.APIKeyHeader` for header-based keys, `zigmund.APIKeyQuery` for query parameter keys, and `zigmund.APIKeyCookie` for cookie-based keys.
- The `.in` field in the security scheme registration (`.header`, `.query`, `.cookie`) must match the resolver you use.
- API key validation logic (checking against a database, for instance) goes inside the provider function after extracting the key.

---

## HTTP Bearer

Bearer token authentication uses the standard `Authorization: Bearer <token>` header. Zigmund's `HTTPBearer` helper extracts and parses this header.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn bearerProvider(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const bearer = zigmund.HTTPBearer{};
    const auth = (try bearer.resolve(req)) orelse return null;
    return auth.credentials;
}

fn readBearerToken(
    token: zigmund.Security(bearerProvider, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .token = token.value.?,
        .authenticated = true,
        .scheme = "bearer",
    });
}
```

Register the scheme:

```zig
try app.addSecurityScheme("bearerAuth", .{
    .http = .{
        .scheme = "bearer",
        .bearer_format = "opaque",
    },
});
```

### How It Works

1. `zigmund.HTTPBearer{}` creates a resolver for the `Authorization` header.
2. `bearer.resolve(req)` parses the header and returns a struct with a `.credentials` field containing the raw token string.
3. If the header is missing or does not start with `Bearer `, the resolver returns `null`.

### Key Points

- The `.bearer_format` field is informational for OpenAPI documentation. Common values are `"JWT"`, `"opaque"`, or any string describing your token format.
- The `auth` struct returned by `resolve` contains the `.credentials` field. You can use this to look up users, validate signatures, or perform any custom logic.

---

## Get Current User

A common pattern is to resolve a bearer token into a full user object. The provider looks up the token in a user store and returns the matching user record.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const User = struct {
    username: []const u8,
    email: []const u8,
    full_name: []const u8,
    disabled: bool,
};

const fake_users = [_]struct { token: []const u8, user: User }{
    .{
        .token = "alice-secret-token",
        .user = .{
            .username = "alice",
            .email = "alice@example.com",
            .full_name = "Alice Wonderson",
            .disabled = false,
        },
    },
    .{
        .token = "bob-secret-token",
        .user = .{
            .username = "bob",
            .email = "bob@example.com",
            .full_name = "Bob Builder",
            .disabled = true,
        },
    },
};

fn getCurrentUser(req: *zigmund.Request, allocator: std.mem.Allocator) !?User {
    _ = allocator;
    const bearer = zigmund.HTTPBearer{};
    const auth = (try bearer.resolve(req)) orelse return null;

    for (&fake_users) |*entry| {
        if (std.mem.eql(u8, auth.credentials, entry.token)) {
            return entry.user;
        }
    }
    return null;
}

fn readCurrentUser(
    current_user: zigmund.Security(getCurrentUser, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user = current_user.value.?;
    return zigmund.Response.json(allocator, .{
        .username = user.username,
        .email = user.email,
        .full_name = user.full_name,
        .disabled = user.disabled,
    });
}

fn readOwnItems(
    current_user: zigmund.Security(getCurrentUser, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user = current_user.value.?;
    return zigmund.Response.json(allocator, .{
        .owner = user.username,
        .items = &[_]struct { item_id: []const u8, title: []const u8 }{
            .{ .item_id = "item-1", .title = "My first item" },
            .{ .item_id = "item-2", .title = "My second item" },
        },
    });
}
```

### How It Works

1. `getCurrentUser` extracts the bearer token, then searches the user database for a matching record.
2. If the token is missing or unrecognized, the provider returns `null`, triggering a 401 response.
3. Both `readCurrentUser` and `readOwnItems` share the same provider. The resolved `User` struct is available through `.value.?`.

### Key Points

- The provider can return any type, not just strings. Returning a full `User` struct means handlers never need to look up the user themselves.
- Multiple handlers can share the same security provider, ensuring consistent authentication logic across your API.
- In production, replace the fake user array with a real database lookup.

---

## Simple OAuth2

OAuth2 password flow lets clients exchange a username and password for an access token. Zigmund provides `OAuth2PasswordBearer` to extract the token and `OAuth2PasswordRequestForm` to parse the login form.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const User = struct {
    username: []const u8,
    email: []const u8,
    full_name: []const u8,
    disabled: bool,
    hashed_password: []const u8,
};

const fake_users = [_]User{
    .{
        .username = "johndoe",
        .email = "johndoe@example.com",
        .full_name = "John Doe",
        .disabled = false,
        .hashed_password = "fakehashedsecret",
    },
    .{
        .username = "alice",
        .email = "alice@example.com",
        .full_name = "Alice Wonderson",
        .disabled = true,
        .hashed_password = "fakehashedsecret2",
    },
};

fn findUser(username: []const u8) ?User {
    for (&fake_users) |*u| {
        if (std.mem.eql(u8, u.username, username)) return u.*;
    }
    return null;
}

fn verifyPassword(plain: []const u8, hashed: []const u8) bool {
    const prefix = "fakehashed";
    if (!std.mem.startsWith(u8, hashed, prefix)) return false;
    return std.mem.eql(u8, hashed[prefix.len..], plain);
}

fn getCurrentUser(req: *zigmund.Request, allocator: std.mem.Allocator) !?User {
    _ = allocator;
    const oauth2 = zigmund.OAuth2PasswordBearer{ .token_url = "/token" };
    const token = (try oauth2.resolve(req)) orelse return null;
    return findUser(token);
}

fn loginForAccessToken(
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const form = try zigmund.OAuth2PasswordRequestForm.fromRequest(req);

    const user = findUser(form.username) orelse {
        return zigmund.Response.json(allocator, .{
            .@"error" = "invalid_credentials",
            .detail = "Incorrect username or password",
        });
    };

    if (!verifyPassword(form.password, user.hashed_password)) {
        return zigmund.Response.json(allocator, .{
            .@"error" = "invalid_credentials",
            .detail = "Incorrect username or password",
        });
    }

    return zigmund.Response.json(allocator, .{
        .access_token = user.username,
        .token_type = "bearer",
    });
}

fn readCurrentUser(
    current_user: zigmund.Security(getCurrentUser, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user = current_user.value.?;
    if (user.disabled) {
        return zigmund.Response.json(allocator, .{
            .@"error" = "inactive_user",
            .detail = "User account is disabled",
        });
    }
    return zigmund.Response.json(allocator, .{
        .username = user.username,
        .email = user.email,
        .full_name = user.full_name,
        .disabled = user.disabled,
    });
}
```

Register the security scheme and routes:

```zig
try app.addSecurityScheme("oauth2PasswordBearer", .{
    .oauth2 = .{
        .flows = .{
            .password = .{
                .token_url = "/token",
            },
        },
    },
});

try app.post("/token", loginForAccessToken, .{});
try app.get("/me", readCurrentUser, .{});
```

### How It Works

1. The client sends a POST to `/token` with `username` and `password` as form fields.
2. `loginForAccessToken` parses the form using `OAuth2PasswordRequestForm.fromRequest()`, validates credentials, and returns an access token.
3. On subsequent requests, the client includes `Authorization: Bearer <token>`.
4. `getCurrentUser` uses `OAuth2PasswordBearer` to extract the token, then looks up the user.
5. Protected endpoints declare `zigmund.Security(getCurrentUser, &.{})` and receive the resolved user.

### Key Points

- `OAuth2PasswordBearer` is configured with a `token_url` that tells Swagger UI where to send login requests.
- `OAuth2PasswordRequestForm.fromRequest()` parses the standard OAuth2 form fields: `username`, `password`, `scope`, `client_id`, and `client_secret`.
- In this simplified example, the token is the username itself. In production, issue a signed JWT or opaque token.
- Check the `disabled` field (or any other user attribute) inside the handler to enforce account-level restrictions.

---

## OAuth2 with JWT

For production systems, combine OAuth2 password flow with JSON Web Tokens. Zigmund's `VerifiedHS256Bearer` validates JWT signatures, expiry, and issuer claims automatically.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const JWT_SECRET = "zigmund-demo-secret-key-change-me";

fn jwtProvider(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const verifier = zigmund.VerifiedHS256Bearer{
        .secret = JWT_SECRET,
        .validation = .{
            .issuer = "zigmund-demo",
            .clock_skew_seconds = 120,
        },
    };
    return verifier.resolve(req);
}

fn readProtected(
    jwt: zigmund.Security(jwtProvider, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const token = jwt.value.?;
    // Parse JWT payload to extract claims...
    return zigmund.Response.json(allocator, .{
        .authenticated = true,
        .token_length = token.len,
    });
}

fn issueToken(
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const form = try zigmund.OAuth2PasswordRequestForm.fromRequest(req);

    const iat = std.time.timestamp();
    const exp = iat + 3600; // 1-hour expiry

    const payload_json = try std.fmt.allocPrint(
        allocator,
        "{{\"sub\":\"{s}\",\"iss\":\"zigmund-demo\",\"iat\":{d},\"exp\":{d}}}",
        .{ form.username, iat, exp },
    );
    defer allocator.free(payload_json);

    const header_json = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";
    const token = try makeHs256Jwt(allocator, header_json, payload_json, JWT_SECRET);
    defer allocator.free(token);

    return zigmund.Response.json(allocator, .{
        .access_token = token,
        .token_type = "bearer",
    });
}
```

Register the security scheme and routes:

```zig
try app.addSecurityScheme("oauth2JwtBearer", .{
    .oauth2 = .{
        .flows = .{
            .password = .{
                .token_url = "/token",
            },
        },
    },
});

try app.post("/token", issueToken, .{});
try app.get("/protected", readProtected, .{});
```

### How It Works

1. The `/token` endpoint constructs a JWT with standard claims (`sub`, `iss`, `iat`, `exp`), signs it with HS256, and returns it.
2. `jwtProvider` uses `VerifiedHS256Bearer` to extract the bearer token, verify the HMAC-SHA256 signature, check the expiry, and validate the issuer claim.
3. If any validation fails, the provider returns `null` and the client receives a 401 response.
4. The handler receives the full, verified JWT string and can parse the payload segment to access individual claims.

### Key Points

- `VerifiedHS256Bearer` performs signature verification, expiry checking, and issuer validation in a single step.
- The `.clock_skew_seconds` field allows a tolerance window for clock differences between servers.
- In production, load `JWT_SECRET` from an environment variable, not a hardcoded string.
- For RS256 or other algorithms, implement a custom provider using standard Zig crypto libraries.
- The token payload can contain any JSON claims. Parse the base64url-encoded payload segment to extract `sub`, custom scopes, or role information.

---

## See Also

- [Dependencies](dependencies.md) -- The general dependency injection system that security builds on.
- [Middleware](middleware.md) -- Request/response hooks for cross-cutting concerns like logging.
- [Handling Errors](handling-errors.md) -- Customizing error responses for authentication failures.
