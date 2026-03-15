# Memory Management in Zigmund

If you are coming from Python and FastAPI, memory management is probably the single
biggest conceptual shift you will encounter in Zig. Python has a garbage collector
that silently allocates and frees memory on your behalf. Zig has no garbage
collector, no reference counting, and no hidden allocations. Every byte of heap
memory is allocated explicitly through an **allocator**, and you are responsible
for freeing it.

This sounds daunting, but Zigmund is designed to make it manageable. The framework
provides a per-request arena allocator that handles the overwhelming majority of
cleanup automatically. Understanding how this works will make your handlers feel
almost as effortless as Python -- with the performance benefits of manual memory
management.

---

## The Allocator Model

In Zig, an `std.mem.Allocator` is a value that knows how to allocate, resize, and
free memory. Rather than calling a global `malloc`, you pass an allocator to every
function that needs heap memory. This makes allocations visible, testable, and
composable.

Zigmund uses two kinds of allocators:

| Allocator | Scope | Who creates it | When it is freed |
|-----------|-------|----------------|------------------|
| `GeneralPurposeAllocator` | Application lifetime | You, in `main()` | At application shutdown via `defer` |
| Arena allocator | Single HTTP request | Zigmund, internally | Automatically, after the response is sent |

### Application-level allocator

When you initialise your Zigmund application, you create a
`GeneralPurposeAllocator` (GPA) and pass it to `App.init`. This allocator lives
for the entire duration of your program and is used for long-lived data such as
route tables, middleware registrations, and configuration:

```zig
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    var app = try zigmund.App.init(gpa.allocator(), .{
        .title = "My API",
        .version = "1.0.0",
    });
    defer app.deinit();

    // Register routes...
    try app.serve(.{});
}
```

The `defer` statements guarantee that `app.deinit()` and `gpa.deinit()` run when
`main` returns, regardless of whether it returns normally or via an error. In
debug builds, the GPA will report any memory leaks at shutdown, which is
invaluable during development.

### Per-request arena allocator

For each incoming HTTP request, Zigmund creates an **arena allocator**. An arena
is a bump allocator: every allocation moves a pointer forward in a large block.
Individual calls to `free` are no-ops -- the entire arena is freed in one shot
after the response is sent.

This means that inside a handler you can allocate freely without worrying about
freeing each allocation:

```zig
fn getUser(
    user_id: zigmund.Path(u32, .{ .alias = "user_id" }),
    allocator: std.mem.Allocator,  // <-- per-request arena allocator
) !zigmund.Response {
    // This allocation lives until the response is sent, then is freed
    // automatically along with the rest of the arena.
    return zigmund.Response.json(allocator, .{
        .id = user_id.value.?,
        .name = "Alice",
    });
}
```

There is nothing to free here. The `allocator` parameter is the arena allocator,
and its entire backing memory is reclaimed by the framework once the response has
been written to the client.

---

## The `allocator` Parameter in Handler Signatures

Zigmund's dependency injection system recognises `std.mem.Allocator` as a special
type. When you include it in your handler's parameter list, the framework
automatically injects the per-request arena allocator. The name of the parameter
does not matter -- only the type:

```zig
fn handler(allocator: std.mem.Allocator) !zigmund.Response {
    // `allocator` is the arena allocator for this request
    return zigmund.Response.json(allocator, .{ .ok = true });
}
```

You can place it anywhere in the parameter list and combine it with other
injected parameters:

```zig
fn handler(
    req: *zigmund.Request,
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    q: zigmund.Query([]const u8, .{ .alias = "q", .required = false }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // All four parameters are injected by the framework.
    // ...
}
```

### Comparison with FastAPI

In FastAPI, you never see an allocator because Python's runtime manages memory
invisibly:

```python
# FastAPI -- no allocator needed
@app.get("/users/{user_id}")
def get_user(user_id: int):
    return {"id": user_id, "name": "Alice"}
```

In Zigmund, the allocator is an explicit parameter, but the arena model means you
rarely need to think about cleanup:

```zig
// Zigmund -- allocator is explicit but cleanup is automatic
fn getUser(
    user_id: zigmund.Path(u32, .{ .alias = "user_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .id = user_id.value.?,
        .name = "Alice",
    });
}
```

The key difference is **visibility**: in Zig, you always know where memory comes
from.

---

## How `Response.json` Uses the Allocator

`Response.json` is the most common way to build a JSON response. It takes an
allocator and a value, serialises the value to a JSON string, and stores the
result in the response body. Here is its signature from the source:

```zig
pub fn json(allocator: std.mem.Allocator, value: anytype) !Response
```

Internally, it calls `std.fmt.allocPrint` to produce a heap-allocated JSON string.
The response struct stores this as `owned_body`, meaning the response owns the
memory:

```zig
pub fn json(allocator: std.mem.Allocator, value: anytype) !Response {
    const payload = try std.fmt.allocPrint(
        allocator,
        "{f}",
        .{std.json.fmt(value, .{})},
    );
    return .{
        .status = .ok,
        .body = payload,
        .content_type = "application/json",
        .owned_body = payload,
    };
}
```

Because the allocator is the per-request arena, this memory is freed automatically
when the request completes. The `Response.deinit` method also frees `owned_body`
and any headers, which Zigmund calls internally after sending the response.

Other response constructors follow the same pattern. Methods that need to
allocate -- `Response.redirect`, `Response.fileFromPath`, `Response.eventStream`,
`Response.jsonLines` -- all accept an allocator as the first parameter. Methods
that do not allocate -- `Response.text`, `Response.html` -- do not require one:

```zig
// No allocation needed -- body is a string literal (static memory)
return zigmund.Response.text("Hello, World!");

// Allocation needed -- JSON is serialised at runtime
return zigmund.Response.json(allocator, .{ .message = "Hello" });
```

---

## The `defer` Pattern for Cleanup

Zig's `defer` statement executes an expression when the current scope exits. It is
the idiomatic way to pair resource acquisition with cleanup:

```zig
var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
defer _ = gpa.deinit();  // runs when `main` returns

var app = try zigmund.App.init(gpa.allocator(), .{
    .title = "My API",
    .version = "1.0.0",
});
defer app.deinit();  // runs when `main` returns, before gpa.deinit()
```

`defer` statements execute in **reverse** order (last-in, first-out), so
`app.deinit()` runs before `gpa.deinit()`. This mirrors the natural dependency
order: the app was created with the GPA's allocator, so it must be cleaned up
first.

There is also `errdefer`, which only executes if the scope exits via an error:

```zig
fn createResource(allocator: std.mem.Allocator) !*Resource {
    const res = try allocator.create(Resource);
    errdefer allocator.destroy(res);  // only if an error is returned below

    try res.init();  // if this fails, `res` is freed
    return res;      // if we get here, caller owns `res`
}
```

### When you need `defer` in handlers

Inside Zigmund handlers, you typically do **not** need `defer` for most
allocations because the arena allocator handles cleanup. However, `defer` is
still useful for non-memory resources:

```zig
fn processFile(
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const file = try std.fs.cwd().openFile("data.json", .{});
    defer file.close();  // ensure file handle is closed

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    // No need to defer free -- arena handles it

    return zigmund.Response.json(allocator, .{ .data = contents });
}
```

---

## GeneralPurposeAllocator vs Arena Allocators

Understanding when each allocator type is appropriate:

### GeneralPurposeAllocator (GPA)

- **Purpose**: Long-lived application state.
- **Lifecycle**: Created in `main`, destroyed at shutdown.
- **Behavior**: Tracks individual allocations; reports leaks in debug mode.
- **Use in Zigmund**: Passed to `App.init` for route tables, middleware, and
  configuration.

```zig
var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
defer _ = gpa.deinit();
```

### Arena allocator

- **Purpose**: Short-lived, request-scoped allocations.
- **Lifecycle**: Created by Zigmund per request; freed after the response is sent.
- **Behavior**: Allocations are O(1) pointer bumps. Individual frees are no-ops.
  The entire arena is freed in bulk.
- **Use in Zigmund**: Injected as the `std.mem.Allocator` parameter in handlers.

You do not create the arena allocator yourself. Zigmund handles it:

```zig
fn handler(allocator: std.mem.Allocator) !zigmund.Response {
    // `allocator` is already an arena allocator -- just use it
    const greeting = try std.fmt.allocPrint(allocator, "Hello, {s}!", .{"world"});
    return zigmund.Response.text(greeting);
}
```

### Why arenas work well for web requests

Web request handling is inherently short-lived: a request arrives, you parse
parameters, query a database, build a response, and send it. The arena model
matches this lifecycle perfectly. Instead of tracking dozens of individual
allocations, everything is freed in one bulk operation. This is both faster
(no per-allocation bookkeeping) and safer (no forgotten frees).

---

## Putting It All Together

Here is a complete example that demonstrates both allocator types:

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const Item = struct {
    name: []const u8,
    price: f64,
    in_stock: bool = true,
};

fn createItem(
    item: zigmund.Body(Item, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const payload = item.value.?;

    // All allocations here use the arena allocator.
    // They are freed automatically after the response is sent.
    return zigmund.Response.json(allocator, .{
        .name = payload.name,
        .price = payload.price,
        .in_stock = payload.in_stock,
        .message = "Item created successfully",
    });
}

pub fn main() !void {
    // Application-level allocator -- lives for the entire program
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    // App uses the GPA for route tables and configuration
    var app = try zigmund.App.init(gpa.allocator(), .{
        .title = "Item Service",
        .version = "1.0.0",
    });
    defer app.deinit();

    try app.post("/items", createItem, .{});
    try app.serve(.{});
}
```

### Summary for Python developers

| Concept | Python / FastAPI | Zig / Zigmund |
|---------|-----------------|---------------|
| Memory management | Garbage collector (automatic) | Explicit allocators (manual but structured) |
| Request memory | Managed by CPython refcounting + GC | Per-request arena allocator (freed in bulk) |
| Application memory | Python runtime manages it | `GeneralPurposeAllocator` in `main()` |
| Cleanup pattern | `with` statements, `__del__` | `defer` and `errdefer` |
| Memory leaks | Rare (possible with cycles) | Caught by GPA in debug mode |
| Performance | GC pauses, refcount overhead | Zero overhead; arena free is O(1) |

The allocator model may feel unfamiliar at first, but it provides deterministic
performance, zero hidden allocations, and leak detection in debug builds. The
arena allocator pattern means that most handler code is just as concise as the
equivalent FastAPI code -- you simply pass `allocator` where needed, and the
framework handles the rest.
