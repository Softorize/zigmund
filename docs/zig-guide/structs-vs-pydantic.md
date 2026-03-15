# Zig Structs vs Pydantic Models

In FastAPI, Pydantic models are the backbone of request and response handling.
You define a class that inherits from `BaseModel`, declare typed fields, and
Pydantic handles serialisation, deserialisation, and validation at runtime.

In Zigmund, plain Zig **structs** fill the same role. There is no `BaseModel` to
inherit from and no class hierarchy. A struct is a collection of typed fields --
the Zig compiler enforces the types at compile time, and Zigmund's injector
handles JSON deserialisation and validation at runtime.

This guide explains how to translate your Pydantic mental model into Zig structs
and covers the validation mechanisms Zigmund provides.

---

## Basic Struct Definition

A Pydantic model in FastAPI:

```python
from pydantic import BaseModel

class Item(BaseModel):
    name: str
    price: float
    in_stock: bool = True
```

The equivalent Zig struct:

```zig
const Item = struct {
    name: []const u8,
    price: f64,
    in_stock: bool = true,
};
```

Key differences:

| Concept | Pydantic | Zig struct |
|---------|----------|------------|
| String type | `str` | `[]const u8` (a byte slice) |
| Float type | `float` | `f64` (64-bit float) |
| Integer type | `int` | `u32`, `i64`, etc. (explicit size) |
| Boolean type | `bool` | `bool` |
| Default values | `field: type = default` | `field: type = default` |
| Inheritance | `class Child(Parent)` | Not supported -- use composition |

The default value syntax is identical: `in_stock: bool = true` in Zig works
the same as `in_stock: bool = True` in Python.

---

## Optional Fields

In Python:

```python
from typing import Optional

class User(BaseModel):
    name: str
    bio: Optional[str] = None
```

In Zig:

```zig
const User = struct {
    name: []const u8,
    bio: ?[]const u8 = null,
};
```

The `?` prefix makes a type optional in Zig. `?[]const u8` means "either a
string or null." Combined with a default value of `null`, this creates a field
that can be omitted from the JSON payload.

### Accessing optional fields

```zig
// Check if present
if (user.bio) |bio_value| {
    // bio_value is []const u8 (unwrapped)
    std.debug.print("Bio: {s}\n", .{bio_value});
} else {
    std.debug.print("No bio provided\n", .{});
}

// Or use orelse for a default
const bio = user.bio orelse "No bio";
```

---

## Using Structs with Body(T, .{})

To receive a JSON request body as a struct, use the `Body` marker:

```zig
const ItemPayload = struct {
    name: []const u8,
    price: f64,
    in_stock: bool = true,
};

fn createItem(
    item: zigmund.Body(ItemPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const payload = item.value.?;
    return zigmund.Response.json(allocator, .{
        .name = payload.name,
        .price = payload.price,
        .in_stock = payload.in_stock,
    });
}
```

Zigmund's injector deserialises the JSON request body into an `ItemPayload`
struct. Fields that are missing from the JSON use their default values. Fields
without defaults that are missing from the JSON produce a 422 validation error.

### Comparison with FastAPI

```python
# FastAPI
class ItemPayload(BaseModel):
    name: str
    price: float
    in_stock: bool = True

@app.post("/items")
def create_item(item: ItemPayload):
    return {
        "name": item.name,
        "price": item.price,
        "in_stock": item.in_stock,
    }
```

```zig
// Zigmund
const ItemPayload = struct {
    name: []const u8,
    price: f64,
    in_stock: bool = true,
};

fn createItem(
    item: zigmund.Body(ItemPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const payload = item.value.?;
    return zigmund.Response.json(allocator, .{
        .name = payload.name,
        .price = payload.price,
        .in_stock = payload.in_stock,
    });
}
```

The patterns are strikingly similar. The main syntactic difference is the
`Body(ItemPayload, .{})` marker type instead of a type annotation, and the
`.value.?` unwrap to access the parsed struct.

---

## Compile-Time vs Runtime Validation

One of the most important differences between Pydantic and Zig structs is
**when** type validation occurs.

### Pydantic: runtime validation

Pydantic validates types at runtime. If you send `{"price": "not a number"}`,
Pydantic catches it when deserialising and returns a 422 error. The Python type
system itself does not enforce types -- they are just hints.

### Zig: compile-time type checking + runtime parsing

Zig enforces types at compile time. You cannot assign a `[]const u8` to a `f64`
field -- the compiler will reject it. However, since JSON data arrives as text
at runtime, Zigmund still performs runtime parsing to convert JSON values to Zig
types. If the JSON contains `"price": "not a number"`, the JSON parser will fail
and Zigmund returns a 422 error.

The benefit of compile-time checking is that you cannot accidentally misuse
types in your handler code:

```zig
const Item = struct {
    name: []const u8,
    price: f64,
};

fn handler(item: zigmund.Body(Item, .{}), allocator: std.mem.Allocator) !zigmund.Response {
    const payload = item.value.?;
    // This would be a COMPILE ERROR:
    // const total = payload.name * 2;
    // The compiler knows `name` is []const u8, not a number.

    const total = payload.price * 2;  // This is fine -- price is f64.
    return zigmund.Response.json(allocator, .{ .total = total });
}
```

---

## Response Model Filtering

In FastAPI, you use `response_model` to filter which fields appear in the
response:

```python
class PublicUser(BaseModel):
    id: int
    username: str

@app.get("/users/me", response_model=PublicUser)
def read_user():
    # Returns extra fields, but only id and username appear in the response
    return {"id": 7, "username": "alice", "email": "alice@example.com", "admin": True}
```

Zigmund supports the same pattern through the `response_model` route option:

```zig
const PublicUser = struct {
    id: u32,
    username: []const u8,
};

fn readUser(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    // Return all fields -- response_model will filter
    return zigmund.Response.json(allocator, .{
        .id = 7,
        .username = "alice",
        .email = "alice@example.com",
        .admin = true,
    });
}

// Registration
try app.get("/users/me", readUser, .{
    .response_model = PublicUser,
});
```

The `response_model = PublicUser` option tells Zigmund to filter the JSON
response so that only fields present in `PublicUser` (`id` and `username`)
appear in the output. The `email` and `admin` fields are stripped.

### Additional response model options

Zigmund provides several route options that control response model behavior,
mirroring FastAPI's response model features:

```zig
try app.get("/users/me", readUser, .{
    .response_model = PublicUser,
    .response_model_include = &.{"id", "username"},    // Only include these fields
    .response_model_exclude = &.{"internal_id"},       // Exclude these fields
    .response_model_exclude_unset = false,             // Exclude fields not explicitly set
    .response_model_exclude_defaults = false,          // Exclude fields with default values
    .response_model_exclude_none = false,              // Exclude fields with null values
    .response_model_by_alias = true,                   // Use alias names in output
});
```

---

## Nested Structs

Just as Pydantic supports nested models, Zig supports nested structs:

```python
# FastAPI / Pydantic
class Address(BaseModel):
    street: str
    city: str
    country: str = "US"

class User(BaseModel):
    name: str
    address: Address
```

```zig
// Zigmund / Zig
const Address = struct {
    street: []const u8,
    city: []const u8,
    country: []const u8 = "US",
};

const User = struct {
    name: []const u8,
    address: Address,
};
```

When used with `Body(User, .{})`, the JSON parser handles nested objects
automatically:

```json
{
    "name": "Alice",
    "address": {
        "street": "123 Main St",
        "city": "Springfield",
        "country": "US"
    }
}
```

Nesting can go as deep as needed. Zigmund will recursively deserialise nested
objects into their corresponding struct types.

---

## Field-Level Validation with `zigmund_field_constraints`

While Pydantic uses `Field(...)` with validators for per-field constraints,
Zigmund uses a `zigmund_field_constraints` declaration on the struct. This
provides runtime validation for numeric bounds, string lengths, and regex
patterns on individual fields:

```zig
const CreateUser = struct {
    username: []const u8,
    age: u32,
    email: []const u8,

    pub const zigmund_field_constraints = .{
        .username = .{
            .min_length = @as(?usize, 3),
            .max_length = @as(?usize, 50),
        },
        .age = .{
            .ge = @as(?f64, 0),
            .le = @as(?f64, 150),
        },
        .email = .{
            .pattern = @as(?[]const u8, "^[^@]+@[^@]+\\.[^@]+$"),
        },
    };
};
```

When a `Body(CreateUser, .{})` parameter is parsed, the injector automatically
checks each constrained field after deserialisation. If a constraint is
violated, a 422 validation error is returned with details about which field
failed and why.

### Comparison with Pydantic

```python
from pydantic import BaseModel, Field

class CreateUser(BaseModel):
    username: str = Field(min_length=3, max_length=50)
    age: int = Field(ge=0, le=150)
    email: str = Field(pattern=r"^[^@]+@[^@]+\.[^@]+$")
```

The constraint names (`min_length`, `max_length`, `ge`, `le`, `gt`, `lt`,
`pattern`) are intentionally identical to Pydantic's naming conventions.

Available field constraints:

| Constraint | Type | Description |
|-----------|------|-------------|
| `gt` | `?f64` | Greater than |
| `ge` | `?f64` | Greater than or equal |
| `lt` | `?f64` | Less than |
| `le` | `?f64` | Less than or equal |
| `min_length` | `?usize` | Minimum string length |
| `max_length` | `?usize` | Maximum string length |
| `pattern` | `?[]const u8` | Regex pattern |

Constraints are validated recursively for nested structs, so deeply-nested
models propagate constraints automatically.

---

## Model-Level Validation with `zigmund_validate`

For validation that spans multiple fields or requires custom logic, Zigmund
supports a `zigmund_validate` declaration on the struct. This is similar to
Pydantic's `@model_validator`:

```zig
const DateRange = struct {
    start_date: []const u8,
    end_date: []const u8,

    pub fn zigmund_validate(self: DateRange) !void {
        // Custom validation: end_date must come after start_date
        if (std.mem.order(u8, self.start_date, self.end_date) != .lt) {
            return error.EndDateBeforeStartDate;
        }
    }
};
```

The validator function can have two signatures:

```zig
// Simple form -- receives only the struct value
pub fn zigmund_validate(self: MyStruct) !void { ... }

// Extended form -- also receives the request for additional context
pub fn zigmund_validate(self: MyStruct, req: *zigmund.Request) !void { ... }
```

If the validator returns an error, the framework produces a 422 validation
error response. The error name is included in the response for debugging.

### Comparison with Pydantic

```python
from pydantic import BaseModel, model_validator

class DateRange(BaseModel):
    start_date: str
    end_date: str

    @model_validator(mode="after")
    def validate_range(self):
        if self.start_date >= self.end_date:
            raise ValueError("end_date must come after start_date")
        return self
```

```zig
const DateRange = struct {
    start_date: []const u8,
    end_date: []const u8,

    pub fn zigmund_validate(self: DateRange) !void {
        if (std.mem.order(u8, self.start_date, self.end_date) != .lt) {
            return error.EndDateBeforeStartDate;
        }
    }
};
```

---

## Response Model Aliases

Pydantic supports field aliases with `Field(alias="...")`. Zigmund provides
a similar mechanism through `zigmund_response_aliases`:

```zig
const UserResponse = struct {
    user_id: u32,
    full_name: []const u8,

    pub const zigmund_response_aliases: []const zigmund.ResponseModelAlias = &.{
        .{ .path = "user_id", .alias = "userId" },
        .{ .path = "full_name", .alias = "fullName" },
    };
};
```

When this struct is used as a `response_model`, the output JSON uses the alias
names instead of the field names:

```json
{
    "userId": 42,
    "fullName": "Alice Smith"
}
```

---

## Response Model Transforms and Computed Fields

For advanced response shaping, structs used as response models can declare
transform functions and computed fields:

### `zigmund_response_transform`

A function that receives the JSON value and can modify it in place before the
response is sent:

```zig
const OrderResponse = struct {
    items: []const Item,
    subtotal: f64,

    pub fn zigmund_response_transform(
        value: *std.json.Value,
        allocator: std.mem.Allocator,
    ) anyerror!void {
        // Add a computed field to the JSON
        _ = allocator;
        // Modify `value` in place...
    }
};
```

### `zigmund_computed_fields`

Declares fields that are computed from the response data at runtime:

```zig
const OrderResponse = struct {
    quantity: u32,
    unit_price: f64,

    pub const zigmund_computed_fields: []const zigmund.ComputedFieldEntry = &.{
        .{
            .name = "total",
            .compute = &computeTotal,
        },
    };

    fn computeTotal(
        fields: std.json.ObjectMap,
        allocator: std.mem.Allocator,
    ) anyerror!std.json.Value {
        _ = allocator;
        const qty = fields.get("quantity") orelse return .{ .float = 0 };
        const price = fields.get("unit_price") orelse return .{ .float = 0 };
        return .{ .float = qty.float * price.float };
    }
};
```

---

## No Class Inheritance -- Composition Instead

Zig does not have classes or inheritance. Where Pydantic uses inheritance to
share fields between models, Zig uses **composition** (embedding one struct
inside another):

```python
# Pydantic -- inheritance
class BaseItem(BaseModel):
    name: str
    price: float

class ItemWithId(BaseItem):
    id: int
```

```zig
// Zig -- composition
const BaseItem = struct {
    name: []const u8,
    price: f64,
};

const ItemWithId = struct {
    base: BaseItem,
    id: u32,
};
```

Or you can simply repeat the fields (which is more idiomatic in Zig when the
structs serve different purposes):

```zig
const CreateItem = struct {
    name: []const u8,
    price: f64,
};

const ItemResponse = struct {
    id: u32,
    name: []const u8,
    price: f64,
};
```

This explicit repetition may feel redundant coming from Python, but it has
advantages: each struct is self-contained, there are no hidden inherited fields,
and the compiler can optimize each struct independently.

---

## Type Mapping Reference

A quick reference for translating Python types to Zig types:

| Python | Zig | Notes |
|--------|-----|-------|
| `str` | `[]const u8` | Byte slice (UTF-8 string) |
| `int` | `i32`, `i64`, `u32`, `u64` | Choose the appropriate size |
| `float` | `f32`, `f64` | Choose the appropriate precision |
| `bool` | `bool` | Same name |
| `Optional[T]` | `?T` | `?` prefix makes any type optional |
| `list[T]` | `[]const T` | Slice of T |
| `dict` | Not directly supported | Use a struct with known fields |
| `Any` | `std.json.Value` | Dynamic JSON value |
| `None` | `null` | Zig's null literal |
| `datetime` | `[]const u8` or `zigmund.DateTime` | String or typed wrapper |
| `UUID` | `[]const u8` or `zigmund.Uuid` | String or typed wrapper |

---

## Summary

| Concept | Pydantic | Zig Structs in Zigmund |
|---------|----------|----------------------|
| Model definition | `class Item(BaseModel):` | `const Item = struct { ... };` |
| Field types | Runtime-checked annotations | Compile-time enforced types |
| Default values | `field: type = default` | `field: type = default` |
| Optional fields | `Optional[T] = None` | `?T = null` |
| JSON deserialization | Automatic via Pydantic | Via `Body(T, .{})` marker |
| Field validation | `Field(min_length=3)` | `zigmund_field_constraints` |
| Model validation | `@model_validator` | `zigmund_validate` function |
| Response filtering | `response_model=Model` | `.response_model = Model` |
| Field aliases | `Field(alias="name")` | `zigmund_response_aliases` |
| Inheritance | `class Child(Parent):` | Composition or field repetition |
| Computed fields | `@computed_field` | `zigmund_computed_fields` |

Zig structs are simpler than Pydantic models -- there is no metaclass magic, no
runtime schema generation, and no class hierarchy. What you see is what you get.
The trade-off is that some conveniences require explicit declarations (like
`zigmund_field_constraints`), but the benefit is complete transparency, compile-time
safety, and zero runtime overhead for type checking.
