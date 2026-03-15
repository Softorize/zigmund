# Comptime Parameter Markers

One of the most distinctive features of Zigmund is its parameter marker system.
If you are coming from FastAPI, you are familiar with writing `Query(...)`,
`Path(...)`, and `Body(...)` as function parameter annotations. Zigmund has
equivalents with the same names -- but they work in a fundamentally different way.

In FastAPI, parameter annotations are resolved at **runtime** using Python's type
introspection and the Depends system. In Zigmund, parameter markers are resolved
at **compile time** using Zig's comptime metaprogramming. The compiler sees your
handler function's type signature, analyzes every parameter, and generates
specialized extraction code before the program even runs.

This guide explains how the marker system works, how to use each marker type, and
how the `.value.?` pattern replaces what you might think of as "unwrapping" a
parameter.

---

## What Are Comptime Markers?

A marker like `Query(u32, .{})` is not a function call at runtime. It is a
**comptime function** that returns a **type**. When you write:

```zig
fn listItems(
    skip: zigmund.Query(u32, .{ .alias = "skip", .required = false }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // ...
}
```

The compiler evaluates `zigmund.Query(u32, .{ .alias = "skip", .required = false })`
at compile time and produces a struct type. That struct has:

- A `value` field of type `?u32` (an optional wrapping the inner type)
- Comptime declarations for `ValueType`, `Location`, and `options` that carry
  metadata about where to extract the value and what constraints to apply

The generated struct looks conceptually like this:

```zig
// What Query(u32, .{ .alias = "skip", .required = false }) produces:
const QuerySkipMarker = struct {
    pub const ValueType = u32;
    pub const Location = .query;
    pub const options = QueryOptions{
        .alias = "skip",
        .required = false,
        // ... other defaults
    };

    value: ?u32 = null,
};
```

This is not something you write yourself -- the `Query` function generates it.
But understanding this structure explains why the `.value.?` pattern works.

---

## The `.value.?` Pattern

Every marker wraps its inner value in an optional (`?T`). After the framework
populates the marker, you access the extracted value with `.value.?`:

```zig
fn readItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .item_id = item_id.value.?,
    });
}
```

Here, `item_id` has type `Path(u32, ...)`, and `item_id.value` has type `?u32`.
The `.?` operator unwraps the optional, asserting that it is not null.

For **required** parameters (the default), the framework guarantees that
`.value` is populated before your handler runs, so `.?` is always safe. If the
parameter is missing from the request, the framework returns a 422 validation
error before your handler is called.

For **optional** parameters (`.required = false`), `.value` may be `null`. Use
`orelse` to provide a default:

```zig
fn listItems(
    skip: zigmund.Query(u32, .{ .alias = "skip", .required = false }),
    limit: zigmund.Query(u32, .{ .alias = "limit", .required = false }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const resolved_skip = skip.value orelse 0;
    const resolved_limit = limit.value orelse 10;

    return zigmund.Response.json(allocator, .{
        .skip = resolved_skip,
        .limit = resolved_limit,
    });
}
```

### Comparison with FastAPI

In FastAPI, optional parameters use Python's `Optional` type and default values:

```python
@app.get("/items")
def list_items(skip: int = 0, limit: int = 10):
    return {"skip": skip, "limit": limit}
```

In Zigmund, optionality is expressed through the marker options and the `orelse`
keyword:

```zig
fn listItems(
    skip: zigmund.Query(u32, .{ .alias = "skip", .required = false }),
    limit: zigmund.Query(u32, .{ .alias = "limit", .required = false }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const resolved_skip = skip.value orelse 0;
    const resolved_limit = limit.value orelse 10;
    return zigmund.Response.json(allocator, .{
        .skip = resolved_skip,
        .limit = resolved_limit,
    });
}
```

---

## How the Injector Resolves Parameters

Zigmund's injector (`src/core/injector.zig`) uses comptime reflection to analyze
your handler function's type signature. When you register a handler with
`app.get(...)` or `app.post(...)`, the framework calls `bindHttpHandler` which
generates a wrapper function at compile time.

The process works like this:

1. **Inspect the function signature.** The injector uses `@typeInfo` to iterate
   over every parameter of your handler function.

2. **Classify each parameter.** For each parameter type, it checks:
   - Is it `*Request`? Inject the raw request object.
   - Is it `*BackgroundTasks`? Inject the background task runner.
   - Is it `std.mem.Allocator`? Inject the per-request arena allocator.
   - Does it have `Location`, `ValueType`, `options`, and `value` fields?
     It is a parameter marker -- extract from the appropriate source.
   - Does it have `marker_kind == .depends`? It is a dependency -- resolve
     the provider function.
   - Does it have `marker_kind == .security`? It is a security dependency --
     resolve the security provider.

3. **Generate extraction code.** For parameter markers, the injector reads the
   `Location` declaration to determine whether to extract from query string,
   path, headers, cookies, body, form data, or file upload. It reads `options`
   for validation constraints like `alias`, `required`, `gt`, `min_length`, etc.

4. **Call the handler.** Once all arguments are resolved, the injector calls
   your handler with `@call(.auto, handler, args)`.

All of this happens at **compile time**. There is no runtime reflection, no hash
table of parameter names, no dynamic dispatch. The compiler generates a
specialised wrapper function that extracts exactly the parameters your handler
needs, with exactly the right types and constraints.

---

## All Marker Types

### Query

Extracts a value from the URL query string.

```zig
fn handler(
    page: zigmund.Query(u32, .{ .alias = "page" }),
    q: zigmund.Query([]const u8, .{ .alias = "q", .required = false }),
) !zigmund.Response { ... }
```

**Options** (`QueryOptions`):

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `alias` | `?[]const u8` | `null` | Query parameter name (required for scalar types) |
| `description` | `?[]const u8` | `null` | OpenAPI description |
| `required` | `bool` | `true` | Whether the parameter must be present |
| `deprecated` | `bool` | `false` | Mark as deprecated in OpenAPI |
| `gt` | `?f64` | `null` | Value must be greater than this |
| `ge` | `?f64` | `null` | Value must be greater than or equal |
| `lt` | `?f64` | `null` | Value must be less than this |
| `le` | `?f64` | `null` | Value must be less than or equal |
| `min_length` | `?usize` | `null` | Minimum string length |
| `max_length` | `?usize` | `null` | Maximum string length |
| `pattern` | `?[]const u8` | `null` | Regex pattern the value must match |
| `enum_values` | `[]const []const u8` | `&.{}` | Allowed values |
| `strict` | `bool` | `false` | Enable strict type parsing |
| `openapi_examples` | `[]const OpenApiExample` | `&.{}` | Named examples for docs |

### Path

Extracts a value from the URL path.

```zig
fn handler(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
) !zigmund.Response { ... }
```

**Options** (`PathOptions`): Same as `QueryOptions` except there is no `required`
field (path parameters are always required) and no `deprecated` field.

### Header

Extracts a value from an HTTP header.

```zig
fn handler(
    token: zigmund.Header([]const u8, .{ .alias = "x-api-token" }),
) !zigmund.Response { ... }
```

**Options** (`HeaderOptions`): Same as `QueryOptions` plus:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `convert_underscores` | `bool` | `true` | Convert `_` to `-` in header names |

### Cookie

Extracts a value from a cookie.

```zig
fn handler(
    session: zigmund.Cookie([]const u8, .{ .alias = "session_id" }),
) !zigmund.Response { ... }
```

**Options** (`CookieOptions`): Same fields as `QueryOptions` (without `deprecated`).

### Body

Deserialises a JSON request body into a Zig struct.

```zig
const CreateItem = struct {
    name: []const u8,
    price: f64,
    in_stock: bool = true,
};

fn handler(
    item: zigmund.Body(CreateItem, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const payload = item.value.?;
    return zigmund.Response.json(allocator, .{
        .name = payload.name,
        .price = payload.price,
    });
}
```

**Options** (`BodyOptions`):

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `embed` | `bool` | `false` | Wrap body in a named key |
| `media_type` | `[]const u8` | `"application/json"` | Expected Content-Type |
| `description` | `?[]const u8` | `null` | OpenAPI description |
| `gt`, `ge`, `lt`, `le` | `?f64` | `null` | Numeric constraints |
| `min_length`, `max_length` | `?usize` | `null` | String length constraints |
| `pattern` | `?[]const u8` | `null` | Regex pattern constraint |
| `enum_values` | `[]const []const u8` | `&.{}` | Allowed values |
| `strict` | `bool` | `false` | Enable strict parsing |

### Form

Extracts form-encoded data into a struct.

```zig
const LoginForm = struct {
    username: []const u8,
    password: []const u8,
};

fn handler(
    form: zigmund.Form(LoginForm, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response { ... }
```

**Options** (`FormOptions`): Similar to `BodyOptions` with `media_type` defaulting
to `"application/x-www-form-urlencoded"`.

### File

Extracts uploaded file data.

```zig
fn handler(
    upload: zigmund.File(zigmund.UploadFile, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response { ... }
```

**Options** (`FileOptions`): Similar to `BodyOptions` with `media_type` defaulting
to `"application/octet-stream"`.

### Depends

Injects a dependency by calling a provider function. This is the Zigmund
equivalent of FastAPI's `Depends(...)`.

```zig
fn getDbConnection(allocator: std.mem.Allocator) ![]const u8 {
    return "db-connection-string";
}

fn handler(
    db: zigmund.Depends(getDbConnection, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const conn = db.value.?;
    return zigmund.Response.json(allocator, .{ .db = conn });
}
```

**Options** (`DependsOptions`):

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `use_cache` | `bool` | `true` | Cache the result within the scope |
| `cache_scope` | `DependsCacheScope` | `.request` | `.request` or `.app` |
| `name` | `?[]const u8` | `null` | Named dependency for overrides |
| `depends_on` | `[]const []const u8` | `&.{}` | Explicit dependency ordering |
| `cleanup` | `?DependencyCleanupFn` | `null` | Cleanup callback (request scope only) |

**Comparison with FastAPI:**

```python
# FastAPI
def get_db():
    db = connect()
    try:
        yield db
    finally:
        db.close()

@app.get("/items")
def read_items(db: Session = Depends(get_db)):
    ...
```

```zig
// Zigmund
fn getDb(allocator: std.mem.Allocator) ![]const u8 {
    return "connection";
}

fn readItems(
    db: zigmund.Depends(getDb, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response { ... }
```

The provider function in Zigmund is resolved **recursively** -- a Depends
provider can itself accept injected parameters, including other Depends markers.
Circular dependencies are detected at runtime and produce an error.

### Security

Injects security credentials by calling a security provider. Works like
`Depends` but carries additional OpenAPI security scheme metadata:

```zig
fn handler(
    credentials: zigmund.Security(zigmund.HTTPBearer, &.{"read"}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const token = credentials.value.?;
    return zigmund.Response.json(allocator, .{ .token = token });
}
```

Variants include `SecurityNamed`, `SecurityOptional`, and
`SecurityNamedOptional` for more precise control over OpenAPI security
requirements.

---

## How Markers Differ from FastAPI Decorators

| Aspect | FastAPI | Zigmund |
|--------|---------|---------|
| Resolution time | Runtime (via Python inspect) | Compile time (via `@typeInfo`) |
| Type checking | Runtime (Pydantic validation) | Compile time (Zig type system) + runtime validation |
| Overhead | Reflection on every request | Zero -- specialised code generated at compile time |
| Error on bad type | Runtime `422 Unprocessable Entity` | Compile error for type mismatches; runtime 422 for bad input |
| Extensibility | Custom `Depends` callables | Custom `Depends` provider functions |
| Syntax | `item_id: int = Path(...)` | `item_id: zigmund.Path(u32, .{...})` |

The compile-time approach means that many errors that would be runtime exceptions
in FastAPI are caught before your program even runs. If you pass a wrong type,
forget a required option, or create a circular dependency chain, the Zig compiler
will tell you with a clear error message.

---

## Validation Constraints

All parameter markers (Query, Path, Header, Cookie, Body, Form, File) support
validation constraints through their options structs. These constraints are
enforced at runtime when the request is processed:

```zig
fn handler(
    page: zigmund.Query(u32, .{
        .alias = "page",
        .ge = 1,            // must be >= 1
        .le = 100,          // must be <= 100
        .description = "Page number",
    }),
    q: zigmund.Query([]const u8, .{
        .alias = "q",
        .min_length = 1,    // must have at least 1 character
        .max_length = 100,  // must have at most 100 characters
        .required = false,
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response { ... }
```

When a constraint is violated, the framework returns a 422 response with details
about which parameter failed and why. This mirrors FastAPI's validation error
responses powered by Pydantic.

---

## Summary

The comptime marker system is what makes Zigmund feel like FastAPI despite being
written in a systems language. You declare what you need in your handler's type
signature, and the framework generates all the extraction, parsing, and
validation code at compile time. The result is handler code that is concise and
readable, with zero runtime reflection overhead and compile-time safety that
catches errors before deployment.
