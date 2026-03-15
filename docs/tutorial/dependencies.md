# Dependencies

Zigmund's dependency injection system lets you declare shared logic -- query parsing, authentication, database sessions -- as reusable provider functions that are automatically resolved and injected into your route handlers.

## Overview

Dependencies are ordinary Zig functions that accept a `*zigmund.Request` (and optionally an `std.mem.Allocator`) and return a value. You wire them into a handler by declaring a parameter with the `zigmund.Depends()` marker type. Zigmund resolves the provider before your handler runs and delivers the result through the `.value` field.

This pattern eliminates repetitive parameter parsing, centralizes validation, and makes testing straightforward -- you can swap providers without touching handler logic.

---

## Basic Dependencies

A basic dependency is a free function that extracts or computes something from the incoming request. You reference it with `zigmund.Depends(providerFn, .{})`.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const CommonQueryParams = struct {
    q: ?[]const u8,
    skip: u32,
    limit: u32,
};

fn commonParamsProvider(req: *zigmund.Request) CommonQueryParams {
    const q = req.queryParam("q");
    const skip_raw = req.queryParam("skip");
    const limit_raw = req.queryParam("limit");
    return .{
        .q = q,
        .skip = if (skip_raw) |s| std.fmt.parseInt(u32, s, 10) catch 0 else 0,
        .limit = if (limit_raw) |l| std.fmt.parseInt(u32, l, 10) catch 100 else 100,
    };
}

fn readItems(
    commons: zigmund.Depends(commonParamsProvider, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const params = commons.value.?;
    return zigmund.Response.json(allocator, .{
        .q = params.q,
        .skip = params.skip,
        .limit = params.limit,
    });
}

fn readUsers(
    commons: zigmund.Depends(commonParamsProvider, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const params = commons.value.?;
    return zigmund.Response.json(allocator, .{
        .route = "users",
        .q = params.q,
        .skip = params.skip,
        .limit = params.limit,
    });
}
```

Register the routes as usual:

```zig
try app.get("/items", readItems, .{});
try app.get("/users", readUsers, .{});
```

### How It Works

1. `commonParamsProvider` is a plain function that receives the request and returns a `CommonQueryParams` struct.
2. Both `readItems` and `readUsers` declare a parameter typed `zigmund.Depends(commonParamsProvider, .{})`. Zigmund sees this marker and calls the provider automatically.
3. The resolved value is available through `commons.value.?`. If the provider returns an error, Zigmund short-circuits the request with an appropriate error response.

### Key Points

- The provider function must accept `*zigmund.Request` as its first parameter. It may optionally accept `std.mem.Allocator` as a second parameter.
- The second argument to `Depends()` is a compile-time options struct (currently `{}`). It is reserved for future configuration such as caching behavior.
- Multiple handlers can share the same provider, keeping query-parsing logic in one place.

---

## Classes as Dependencies

In Python frameworks, callable classes are a common dependency pattern. Zig does not have classes, but you can achieve the same effect with struct-based provider functions. The provider function can return any struct type, and the struct itself can carry methods and internal state.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const CommonQueryParams = struct {
    q: ?[]const u8,
    skip: u32,
    limit: u32,
};

fn commonParamsProvider(req: *zigmund.Request) CommonQueryParams {
    const skip_raw = req.queryParam("skip");
    const limit_raw = req.queryParam("limit");
    return .{
        .q = req.queryParam("q"),
        .skip = if (skip_raw) |s| std.fmt.parseInt(u32, s, 10) catch 0 else 0,
        .limit = if (limit_raw) |l| std.fmt.parseInt(u32, l, 10) catch 100 else 100,
    };
}

fn readItems(
    commons: zigmund.Depends(commonParamsProvider, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const params = commons.value.?;
    return zigmund.Response.json(allocator, .{
        .q = params.q,
        .skip = params.skip,
        .limit = params.limit,
        .provider = "CommonQueryParams",
    });
}
```

### How It Works

The provider returns a `CommonQueryParams` struct -- the Zig equivalent of a callable class instance. Because the struct is a first-class value, you can attach methods to it, compose it with other structs, or store computed fields. The handler receives the fully constructed struct and accesses its fields directly.

### Key Points

- Think of the returned struct as the "instance" and the provider function as the "constructor".
- You can add `pub fn` methods to the struct for any post-processing logic the handler might need.
- This pattern scales naturally: add fields to the struct, and every handler that depends on it gains access to the new data.

---

## Sub-dependencies

A provider function can itself depend on another provider. Zigmund resolves the chain automatically, calling each provider in the correct order.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const QueryExtract = struct {
    q: ?[]const u8,
    last_query: ?[]const u8,
};

fn queryExtractor(req: *zigmund.Request) QueryExtract {
    return .{
        .q = req.queryParam("q"),
        .last_query = null,
    };
}

const SubQueryExtract = struct {
    q: ?[]const u8,
    last_query: ?[]const u8,
    description: []const u8,
};

fn subQueryExtractor(
    base: zigmund.Depends(queryExtractor, .{}),
) SubQueryExtract {
    const base_val = base.value.?;
    return .{
        .q = base_val.q,
        .last_query = base_val.last_query,
        .description = if (base_val.q != null) "query provided" else "no query",
    };
}

fn readQuery(
    sub: zigmund.Depends(subQueryExtractor, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const result = sub.value.?;
    return zigmund.Response.json(allocator, .{
        .q = result.q,
        .last_query = result.last_query,
        .description = result.description,
    });
}
```

### How It Works

1. `queryExtractor` pulls the raw query parameter from the request.
2. `subQueryExtractor` depends on `queryExtractor` via `zigmund.Depends(queryExtractor, .{})`. It receives the already-resolved `QueryExtract` value and enriches it with a `description` field.
3. The handler `readQuery` depends only on `subQueryExtractor`. Zigmund automatically resolves `queryExtractor` first, then `subQueryExtractor`, then calls the handler.

### Key Points

- Sub-dependency chains can be arbitrarily deep. Each provider declares its own dependencies, and Zigmund resolves the full graph.
- A sub-dependency provider does not need to accept `*zigmund.Request` if it only needs the output of its parent dependency.
- If any provider in the chain returns an error, the entire chain is aborted and an error response is returned.

---

## Dependencies in Path Operations

Sometimes a dependency should run as a precondition for a route -- verifying a header, checking permissions -- without the handler needing to consume the returned value. You can attach such dependencies at the route level using the `.dependencies` field in the route options.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn verifyTokenResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const token = req.header("x-token") orelse return error.Unauthorized;
    if (std.mem.eql(u8, token, "invalid")) return error.Unauthorized;
    return token;
}

fn verifyKeyResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const key = req.header("x-key") orelse return error.Unauthorized;
    if (std.mem.eql(u8, key, "invalid")) return error.Unauthorized;
    return key;
}

fn readItems(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .items = &[_][]const u8{ "Portal Gun", "Plumbus" },
    });
}
```

Register the dependencies and attach them to routes:

```zig
try app.addDependency("verify_token", verifyTokenResolver);
try app.addDependency("verify_key", verifyKeyResolver);

try app.get("/items", readItems, .{
    .dependencies = &.{
        .{ .name = "verify_token" },
        .{ .name = "verify_key" },
    },
});
```

### How It Works

1. `app.addDependency()` registers a named dependency resolver at the application level. The resolver runs before the handler and can short-circuit the request by returning an error.
2. The `.dependencies` field in the route options lists which named dependencies must pass before the handler executes.
3. The handler itself does not declare `Depends()` parameters -- the dependencies act purely as guards.

### Key Points

- Route-level dependencies are ideal for authorization checks, rate limiting, and request validation that the handler does not need to interact with directly.
- If any route-level dependency returns an error, the handler is never called.
- Named dependencies registered with `addDependency` can be reused across multiple routes.

---

## Dependencies with Yield

Some resources -- database connections, temporary files, locks -- need cleanup after the request completes. In Zigmund, a dependency struct can implement a `deinit` method, which Zigmund calls automatically after the response is sent.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const SessionResource = struct {
    label: []const u8,

    pub fn deinit(self: *SessionResource, allocator: std.mem.Allocator) !void {
        _ = self;
        _ = allocator;
        // Cleanup logic: close connections, release resources, etc.
    }
};

fn sessionProvider(req: *zigmund.Request) SessionResource {
    _ = req;
    return .{ .label = "yield-backed-session" };
}

fn useSession(
    session: zigmund.Depends(sessionProvider, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .resource = session.value.?.label,
    });
}
```

### How It Works

1. The provider returns a `SessionResource` struct.
2. Zigmund detects the `deinit` method on the struct at compile time.
3. After the response is sent, Zigmund calls `deinit` on the resource, guaranteeing cleanup even if the handler returned an error.

This is the Zig equivalent of Python's `yield` in dependency generators or context managers. The provider sets up the resource; `deinit` tears it down.

### Key Points

- The `deinit` method signature must be `pub fn deinit(self: *Self, allocator: std.mem.Allocator) !void`.
- Cleanup runs after the response is fully sent, so it does not affect response latency.
- If the handler errors, cleanup still runs. This ensures resources like database connections are always returned to the pool.
- Use this pattern for anything that has a lifecycle: database sessions, file handles, distributed locks, or temporary directories.

---

## Global Dependencies

When a dependency should apply to every route in the application, register it with `app.addDependency()` and reference it in every route's `.dependencies` list -- or use it as a guard that runs for all matched routes.

### Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn verifyTokenResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const token = req.header("x-token") orelse return error.Unauthorized;
    if (std.mem.eql(u8, token, "invalid")) return error.Unauthorized;
    return token;
}

fn verifyKeyResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const key = req.header("x-key") orelse return error.Unauthorized;
    if (std.mem.eql(u8, key, "invalid")) return error.Unauthorized;
    return key;
}

fn readItems(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const token = req.dependency("global_verify_token");
    const key = req.dependency("global_verify_key");
    return zigmund.Response.json(allocator, .{
        .items = &[_][]const u8{ "Portal Gun", "Plumbus" },
        .token = token,
        .key = key,
    });
}
```

Register global dependencies and attach them to routes:

```zig
try app.addDependency("global_verify_token", verifyTokenResolver);
try app.addDependency("global_verify_key", verifyKeyResolver);

try app.get("/items", readItems, .{
    .dependencies = &.{
        .{ .name = "global_verify_token" },
        .{ .name = "global_verify_key" },
    },
});
```

### How It Works

1. Named dependencies are registered once at the application level with `app.addDependency()`.
2. Each route that needs these dependencies lists them in its `.dependencies` option.
3. Inside the handler, you can retrieve the resolved dependency value using `req.dependency("name")`. This gives access to whatever the resolver returned.

### Key Points

- Global dependencies let you enforce application-wide invariants (authentication, request logging, feature flags) while keeping handlers focused on business logic.
- The resolver values are accessible in the handler through `req.dependency()`, so you can use them for both guard logic and data retrieval.
- Combine global dependencies with route-level dependencies for layered authorization: global deps verify basic authentication while route deps check specific permissions.

---

## See Also

- [Security](security.md) -- Security-specific dependency patterns (OAuth2, JWT, API keys).
- [Middleware](middleware.md) -- Request/response hooks that run outside the dependency system.
- [Bigger Applications](bigger-applications.md) -- Structuring large apps with routers and shared dependencies.
