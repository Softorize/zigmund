const std = @import("std");

pub const QueryOptions = struct {
    alias: ?[]const u8 = null,
    description: ?[]const u8 = null,
    required: bool = true,
    deprecated: bool = false,
    gt: ?f64 = null,
    ge: ?f64 = null,
    lt: ?f64 = null,
    le: ?f64 = null,
    min_length: ?usize = null,
    max_length: ?usize = null,
    pattern: ?[]const u8 = null,
    enum_values: []const []const u8 = &.{},
    strict: bool = false,
};

pub const PathOptions = struct {
    alias: ?[]const u8 = null,
    description: ?[]const u8 = null,
    gt: ?f64 = null,
    ge: ?f64 = null,
    lt: ?f64 = null,
    le: ?f64 = null,
    min_length: ?usize = null,
    max_length: ?usize = null,
    pattern: ?[]const u8 = null,
    enum_values: []const []const u8 = &.{},
    strict: bool = false,
};

pub const HeaderOptions = struct {
    alias: ?[]const u8 = null,
    convert_underscores: bool = true,
    description: ?[]const u8 = null,
    gt: ?f64 = null,
    ge: ?f64 = null,
    lt: ?f64 = null,
    le: ?f64 = null,
    min_length: ?usize = null,
    max_length: ?usize = null,
    pattern: ?[]const u8 = null,
    enum_values: []const []const u8 = &.{},
    strict: bool = false,
};

pub const CookieOptions = struct {
    alias: ?[]const u8 = null,
    description: ?[]const u8 = null,
    gt: ?f64 = null,
    ge: ?f64 = null,
    lt: ?f64 = null,
    le: ?f64 = null,
    min_length: ?usize = null,
    max_length: ?usize = null,
    pattern: ?[]const u8 = null,
    enum_values: []const []const u8 = &.{},
    strict: bool = false,
};

pub const BodyOptions = struct {
    embed: bool = false,
    media_type: []const u8 = "application/json",
    description: ?[]const u8 = null,
    gt: ?f64 = null,
    ge: ?f64 = null,
    lt: ?f64 = null,
    le: ?f64 = null,
    min_length: ?usize = null,
    max_length: ?usize = null,
    pattern: ?[]const u8 = null,
    enum_values: []const []const u8 = &.{},
    strict: bool = false,
};

pub const FormOptions = struct {
    media_type: []const u8 = "application/x-www-form-urlencoded",
    description: ?[]const u8 = null,
    gt: ?f64 = null,
    ge: ?f64 = null,
    lt: ?f64 = null,
    le: ?f64 = null,
    min_length: ?usize = null,
    max_length: ?usize = null,
    pattern: ?[]const u8 = null,
    enum_values: []const []const u8 = &.{},
    strict: bool = false,
};

pub const FileOptions = struct {
    media_type: []const u8 = "application/octet-stream",
    description: ?[]const u8 = null,
    gt: ?f64 = null,
    ge: ?f64 = null,
    lt: ?f64 = null,
    le: ?f64 = null,
    min_length: ?usize = null,
    max_length: ?usize = null,
    pattern: ?[]const u8 = null,
    enum_values: []const []const u8 = &.{},
    strict: bool = false,
};

pub const DependsCacheScope = enum {
    request,
    app,
};

pub const DependsOptions = struct {
    use_cache: bool = true,
    cache_scope: DependsCacheScope = .request,
    name: ?[]const u8 = null,
    depends_on: []const []const u8 = &.{},
};

pub const MarkerKind = enum {
    depends,
    security,
};

pub const Location = enum {
    query,
    path,
    header,
    cookie,
    body,
    form,
    file,
};

pub fn Query(comptime T: type, opts: QueryOptions) type {
    return ParamType(T, .query, QueryOptions, opts);
}

pub fn Path(comptime T: type, opts: PathOptions) type {
    return ParamType(T, .path, PathOptions, opts);
}

pub fn Header(comptime T: type, opts: HeaderOptions) type {
    return ParamType(T, .header, HeaderOptions, opts);
}

pub fn Cookie(comptime T: type, opts: CookieOptions) type {
    return ParamType(T, .cookie, CookieOptions, opts);
}

pub fn Body(comptime T: type, opts: BodyOptions) type {
    return ParamType(T, .body, BodyOptions, opts);
}

pub fn Form(comptime T: type, opts: FormOptions) type {
    return ParamType(T, .form, FormOptions, opts);
}

pub fn File(comptime T: type, opts: FileOptions) type {
    return ParamType(T, .file, FileOptions, opts);
}

pub fn Depends(comptime provider: anytype, opts: DependsOptions) type {
    const RawReturn = ProviderRawReturnType(provider);
    const ValueType = StripOptional(RawReturn);
    const ProviderReturnsOptional = RawReturn != ValueType;

    return struct {
        pub const marker_kind = MarkerKind.depends;
        pub const Provider = provider;
        pub const ProviderValueType = ValueType;
        pub const provider_returns_optional = ProviderReturnsOptional;
        pub const options = opts;
        pub const dependency_name = opts.name;

        value: ?ValueType = null,
    };
}

pub fn Security(comptime provider: anytype, scopes: []const []const u8) type {
    return SecurityType(provider, scopes, null);
}

pub fn SecurityNamed(comptime provider: anytype, name: []const u8, scopes: []const []const u8) type {
    return SecurityType(provider, scopes, name);
}

fn SecurityType(comptime provider: anytype, scopes: []const []const u8, dependency_name_opt: ?[]const u8) type {
    const RawReturn = ProviderRawReturnType(provider);
    const ValueType = StripOptional(RawReturn);
    const ProviderReturnsOptional = RawReturn != ValueType;

    return struct {
        pub const marker_kind = MarkerKind.security;
        pub const Provider = provider;
        pub const ProviderValueType = ValueType;
        pub const provider_returns_optional = ProviderReturnsOptional;
        pub const required_scopes = scopes;
        pub const dependency_name = dependency_name_opt;

        value: ?ValueType = null,
    };
}

fn ParamType(comptime T: type, comptime location: Location, comptime Opts: type, comptime opts: Opts) type {
    return struct {
        pub const ValueType = T;
        pub const Location = location;
        pub const options = opts;

        value: ?T = null,
    };
}

fn ProviderRawReturnType(comptime provider: anytype) type {
    const ProviderType = @TypeOf(provider);
    if (@typeInfo(ProviderType) != .@"fn") {
        @compileError("Depends/Security provider must be a function");
    }

    const info = @typeInfo(ProviderType).@"fn";
    const return_type = info.return_type orelse @compileError("Depends/Security provider must have a return type");

    if (@typeInfo(return_type) == .error_union) {
        return @typeInfo(return_type).error_union.payload;
    }
    return return_type;
}

fn StripOptional(comptime T: type) type {
    if (@typeInfo(T) == .optional) {
        return @typeInfo(T).optional.child;
    }
    return T;
}

test "parameter marker types carry metadata" {
    const QueryInt = Query(i64, .{ .alias = "page" });
    const q: QueryInt = .{ .value = 1 };

    try std.testing.expectEqual(@as(?i64, 1), q.value);
    try std.testing.expectEqualStrings("page", QueryInt.options.alias.?);
}

test "depends marker carries provider value type" {
    const Provider = struct {
        fn run() !?[]const u8 {
            return "ok";
        }
    };

    const D = Depends(Provider.run, .{});
    var dep: D = .{};
    dep.value = "x";

    try std.testing.expectEqualStrings("x", dep.value.?);
    try std.testing.expect(D.provider_returns_optional);
}
