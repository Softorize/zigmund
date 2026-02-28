const std = @import("std");
const zigmund = @import("zigmund");
const Value = zigmund.JinjaValue;
const renderString = zigmund.renderJinjaString;

// ─── Variable rendering ────────────────────────────────────────────────

test "renders simple variable" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "Hello {{ name }}!", &.{
        .{ "name", Value{ .string = "Zigmund" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Hello Zigmund!", result);
}

test "renders integer variable" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "Count: {{ n }}", &.{
        .{ "n", Value{ .integer = 42 } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Count: 42", result);
}

test "renders float variable" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "Pi: {{ pi }}", &.{
        .{ "pi", Value{ .float = 3.0 } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Pi: 3.0", result);
}

test "renders boolean variable" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ val }}", &.{
        .{ "val", Value{ .boolean = true } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("True", result);
}

test "renders undefined variable as empty" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "Hello {{ missing }}!", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Hello !", result);
}

// ─── Dot notation ─────────────────────────────────────────────────────

test "dot notation accesses map values" {
    const alloc = std.testing.allocator;
    const keys = [_][]const u8{ "name", "age" };
    const vals = [_]Value{ .{ .string = "Alice" }, .{ .integer = 30 } };
    const result = try renderString(alloc, "{{ user.name }} is {{ user.age }}", &.{
        .{ "user", Value{ .map = .{ .keys = &keys, .values = &vals } } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Alice is 30", result);
}

test "subscript accesses list items" {
    const alloc = std.testing.allocator;
    const items = [_]Value{ .{ .string = "first" }, .{ .string = "second" } };
    const result = try renderString(alloc, "{{ items[0] }}", &.{
        .{ "items", Value{ .list = &items } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("first", result);
}

// ─── Control flow: if/elif/else ──────────────────────────────────────

test "if true renders body" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% if show %}visible{% endif %}", &.{
        .{ "show", Value{ .boolean = true } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("visible", result);
}

test "if false skips body" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% if show %}visible{% endif %}", &.{
        .{ "show", Value{ .boolean = false } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "if/else selects correct branch" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% if x %}yes{% else %}no{% endif %}", &.{
        .{ "x", Value{ .boolean = false } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("no", result);
}

test "if/elif/else chain" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% if x == 1 %}one{% elif x == 2 %}two{% else %}other{% endif %}", &.{
        .{ "x", Value{ .integer = 2 } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("two", result);
}

test "comparison operators" {
    const alloc = std.testing.allocator;
    {
        const result = try renderString(alloc, "{% if x > 5 %}big{% else %}small{% endif %}", &.{
            .{ "x", Value{ .integer = 10 } },
        });
        defer alloc.free(result);
        try std.testing.expectEqualStrings("big", result);
    }
    {
        const result = try renderString(alloc, "{% if x <= 5 %}small{% else %}big{% endif %}", &.{
            .{ "x", Value{ .integer = 3 } },
        });
        defer alloc.free(result);
        try std.testing.expectEqualStrings("small", result);
    }
}

test "boolean and/or operators" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% if a and b %}both{% else %}nope{% endif %}", &.{
        .{ "a", Value{ .boolean = true } },
        .{ "b", Value{ .boolean = false } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("nope", result);
}

test "not operator" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% if not hidden %}shown{% endif %}", &.{
        .{ "hidden", Value{ .boolean = false } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("shown", result);
}

// ─── For loops ─────────────────────────────────────────────────────────

test "for loop iterates over list" {
    const alloc = std.testing.allocator;
    const items = [_]Value{ .{ .string = "a" }, .{ .string = "b" }, .{ .string = "c" } };
    const result = try renderString(alloc, "{% for x in items %}{{ x }}{% endfor %}", &.{
        .{ "items", Value{ .list = &items } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("abc", result);
}

test "for loop provides loop.index" {
    const alloc = std.testing.allocator;
    const items = [_]Value{ .{ .string = "a" }, .{ .string = "b" } };
    const result = try renderString(alloc, "{% for x in items %}{{ loop.index }}{% endfor %}", &.{
        .{ "items", Value{ .list = &items } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("12", result);
}

test "for loop provides loop.index0" {
    const alloc = std.testing.allocator;
    const items = [_]Value{ .{ .string = "a" }, .{ .string = "b" } };
    const result = try renderString(alloc, "{% for x in items %}{{ loop.index0 }}{% endfor %}", &.{
        .{ "items", Value{ .list = &items } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("01", result);
}

test "for loop provides loop.first and loop.last" {
    const alloc = std.testing.allocator;
    const items = [_]Value{ .{ .string = "a" }, .{ .string = "b" }, .{ .string = "c" } };
    const result = try renderString(
        alloc,
        "{% for x in items %}{% if loop.first %}[{% endif %}{{ x }}{% if loop.last %}]{% endif %}{% endfor %}",
        &.{.{ "items", Value{ .list = &items } }},
    );
    defer alloc.free(result);
    try std.testing.expectEqualStrings("[abc]", result);
}

test "for loop provides loop.length" {
    const alloc = std.testing.allocator;
    const items = [_]Value{ .{ .integer = 1 }, .{ .integer = 2 }, .{ .integer = 3 } };
    const result = try renderString(alloc, "{% for x in items %}{{ loop.length }}{% endfor %}", &.{
        .{ "items", Value{ .list = &items } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("333", result);
}

test "for loop with else on empty list" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% for x in items %}{{ x }}{% else %}empty{% endfor %}", &.{
        .{ "items", Value{ .list = &.{} } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("empty", result);
}

// ─── Filters ───────────────────────────────────────────────────────────

test "filter upper" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ name|upper }}", &.{
        .{ "name", Value{ .string = "hello" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("HELLO", result);
}

test "filter lower" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ name|lower }}", &.{
        .{ "name", Value{ .string = "HELLO" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "filter default with none value" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ name|default('anonymous') }}", &.{
        .{ "name", Value.none },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("anonymous", result);
}

test "filter default with existing value" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ name|default('anonymous') }}", &.{
        .{ "name", Value{ .string = "Alice" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Alice", result);
}

test "filter length on list" {
    const alloc = std.testing.allocator;
    const items = [_]Value{ .{ .integer = 1 }, .{ .integer = 2 }, .{ .integer = 3 } };
    const result = try renderString(alloc, "{{ items|length }}", &.{
        .{ "items", Value{ .list = &items } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("3", result);
}

test "filter join" {
    const alloc = std.testing.allocator;
    const items = [_]Value{ .{ .string = "a" }, .{ .string = "b" }, .{ .string = "c" } };
    const result = try renderString(alloc, "{{ items|join(', ') }}", &.{
        .{ "items", Value{ .list = &items } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("a, b, c", result);
}

test "filter trim" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "[{{ text|trim }}]", &.{
        .{ "text", Value{ .string = "  hello  " } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("[hello]", result);
}

test "filter capitalize" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ text|capitalize }}", &.{
        .{ "text", Value{ .string = "hello WORLD" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Hello world", result);
}

test "filter replace" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ text|replace('world', 'zig') }}", &.{
        .{ "text", Value{ .string = "hello world" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("hello zig", result);
}

test "filter first and last" {
    const alloc = std.testing.allocator;
    const items = [_]Value{ .{ .integer = 10 }, .{ .integer = 20 }, .{ .integer = 30 } };
    {
        const result = try renderString(alloc, "{{ items|first }}", &.{
            .{ "items", Value{ .list = &items } },
        });
        defer alloc.free(result);
        try std.testing.expectEqualStrings("10", result);
    }
    {
        const result = try renderString(alloc, "{{ items|last }}", &.{
            .{ "items", Value{ .list = &items } },
        });
        defer alloc.free(result);
        try std.testing.expectEqualStrings("30", result);
    }
}

test "filter chain: upper then trim" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ text|trim|upper }}", &.{
        .{ "text", Value{ .string = "  hello  " } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("HELLO", result);
}

test "filter int converts string to integer" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ val|int }}", &.{
        .{ "val", Value{ .string = "42" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("42", result);
}

test "filter abs" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ val|abs }}", &.{
        .{ "val", Value{ .integer = -5 } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("5", result);
}

test "filter wordcount" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ text|wordcount }}", &.{
        .{ "text", Value{ .string = "hello beautiful world" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("3", result);
}

test "filter striptags" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ html|striptags }}", &.{
        .{ "html", Value{ .string = "<p>Hello <b>world</b></p>" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Hello world", result);
}

// ─── Auto-escaping ────────────────────────────────────────────────────

test "auto-escapes HTML by default" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ html }}", &.{
        .{ "html", Value{ .string = "<script>alert('xss')</script>" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;", result);
}

test "safe filter bypasses auto-escaping" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ html|safe }}", &.{
        .{ "html", Value{ .string = "<b>bold</b>" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("<b>bold</b>", result);
}

// ─── Set statement ────────────────────────────────────────────────────

test "set assigns variable" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% set x = 42 %}{{ x }}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("42", result);
}

test "set with expression" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% set x = 3 + 4 %}{{ x }}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("7", result);
}

// ─── Arithmetic ───────────────────────────────────────────────────────

test "arithmetic addition" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ 1 + 2 }}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("3", result);
}

test "arithmetic precedence" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ 2 + 3 * 4 }}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("14", result);
}

test "arithmetic with variables" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ a + b }}", &.{
        .{ "a", Value{ .integer = 10 } },
        .{ "b", Value{ .integer = 20 } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("30", result);
}

test "modulo operator" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ 10 % 3 }}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("1", result);
}

// ─── Tilde concatenation ──────────────────────────────────────────────

test "tilde concatenates strings" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ 'hello' ~ ' ' ~ 'world' }}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("hello world", result);
}

// ─── Comments ─────────────────────────────────────────────────────────

test "comments are stripped from output" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "before{# comment #}after", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("beforeafter", result);
}

// ─── Raw blocks ───────────────────────────────────────────────────────

test "raw blocks pass through template syntax" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% raw %}{{ not_a_var }}{% endraw %}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("{{ not_a_var }}", result);
}

// ─── String literals ──────────────────────────────────────────────────

test "string literal output" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ 'hello' }}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

// ─── Macro ────────────────────────────────────────────────────────────

test "macro definition and call" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% macro greet(name) %}Hello {{ name }}!{% endmacro %}{{ greet('World') }}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Hello World!", result);
}

test "macro with default parameter" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% macro greet(name = 'friend') %}Hi {{ name }}{% endmacro %}{{ greet() }}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Hi friend", result);
}

// ─── Range function ───────────────────────────────────────────────────

test "range function generates list" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% for i in range(3) %}{{ i }}{% endfor %}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("012", result);
}

test "range with start and end" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% for i in range(1, 4) %}{{ i }}{% endfor %}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("123", result);
}

// ─── tojson filter ────────────────────────────────────────────────────

test "tojson filter" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ name|tojson }}", &.{
        .{ "name", Value{ .string = "hello" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("\"hello\"", result);
}

// ─── Integration with TemplatesIntegration ─────────────────────────────

test "TemplatesIntegration renderJinja loads from filesystem" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "greet.html",
        .data = "Hello {{ name }}! You have {{ count }} messages.",
    });

    const templates_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(templates_dir);

    var templates = try zigmund.TemplatesIntegration.init(std.testing.allocator, templates_dir);
    defer templates.deinit();

    const rendered = try templates.renderJinja("greet.html", &.{
        .{ "name", Value{ .string = "Alice" } },
        .{ "count", Value{ .integer = 5 } },
    });
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("Hello Alice! You have 5 messages.", rendered);
}

test "Engine renders template from filesystem with control flow" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "list.html",
        .data = "{% for item in items %}{{ loop.index }}. {{ item }}\n{% endfor %}",
    });

    const templates_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(templates_dir);

    var engine = zigmund.JinjaEngine.init(std.testing.allocator, templates_dir);
    defer engine.deinit();

    const items = [_]Value{ .{ .string = "Apple" }, .{ .string = "Banana" } };
    const rendered = try engine.render("list.html", &.{
        .{ "items", Value{ .list = &items } },
    });
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("1. Apple\n2. Banana\n", rendered);
}
