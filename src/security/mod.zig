const std = @import("std");
const Request = @import("../http/request.zig").Request;

pub const ResolveError = error{
    Unauthorized,
    InsufficientScope,
    InvalidGrantType,
};

pub const granted_scopes_dependency_key = "zigmund.security.scopes";
pub const required_scopes_dependency_key = "zigmund.security.required_scopes";

pub const ApiKeyIn = enum {
    query,
    header,
    cookie,

    pub fn asString(self: ApiKeyIn) []const u8 {
        return switch (self) {
            .query => "query",
            .header => "header",
            .cookie => "cookie",
        };
    }
};

pub const Scope = struct {
    name: []const u8,
    description: ?[]const u8 = null,
};

pub const OAuthFlow = struct {
    authorization_url: ?[]const u8 = null,
    token_url: ?[]const u8 = null,
    refresh_url: ?[]const u8 = null,
    scopes: []const Scope = &.{},
};

pub const OAuthFlows = struct {
    implicit: ?OAuthFlow = null,
    password: ?OAuthFlow = null,
    client_credentials: ?OAuthFlow = null,
    authorization_code: ?OAuthFlow = null,
};

pub const OpenApiSecurityScheme = union(enum) {
    api_key: struct {
        name: []const u8,
        in: ApiKeyIn,
    },
    http: struct {
        scheme: []const u8,
        bearer_format: ?[]const u8 = null,
    },
    oauth2: struct {
        flows: OAuthFlows,
    },
    openid_connect: struct {
        openid_connect_url: []const u8,
    },
};

pub const NamedScheme = struct {
    name: []const u8,
    scheme: OpenApiSecurityScheme,
};

pub const HTTPAuthorizationCredentials = struct {
    scheme: []const u8,
    credentials: []const u8,
};

pub const HTTPBasicCredentials = struct {
    username: []const u8,
    password: []const u8,
    decoded: []u8,

    pub fn deinit(self: *HTTPBasicCredentials, allocator: std.mem.Allocator) void {
        allocator.free(self.decoded);
        self.* = .{
            .username = "",
            .password = "",
            .decoded = &.{},
        };
    }
};

pub const BasicDecodeError = std.mem.Allocator.Error || std.base64.Base64Decoder.Error || error{
    InvalidBasicCredentials,
};

pub const APIKeyQuery = struct {
    name: []const u8,
    auto_error: bool = true,

    pub fn resolve(self: APIKeyQuery, req: *const Request) ResolveError!?[]const u8 {
        const value = req.queryParam(self.name);
        if (value == null and self.auto_error) return error.Unauthorized;
        return value;
    }
};

pub const APIKeyHeader = struct {
    name: []const u8,
    auto_error: bool = true,

    pub fn resolve(self: APIKeyHeader, req: *const Request) ResolveError!?[]const u8 {
        const value = req.header(self.name);
        if (value == null and self.auto_error) return error.Unauthorized;
        return value;
    }
};

pub const APIKeyCookie = struct {
    name: []const u8,
    auto_error: bool = true,

    pub fn resolve(self: APIKeyCookie, req: *const Request) ResolveError!?[]const u8 {
        const raw_cookie = req.header("cookie");
        if (raw_cookie) |cookie| {
            if (cookieLookup(cookie, self.name)) |value| return value;
        }
        if (self.auto_error) return error.Unauthorized;
        return null;
    }
};

pub const HTTPBasic = struct {
    auto_error: bool = true,

    pub fn resolve(self: HTTPBasic, req: *const Request) ResolveError!?HTTPAuthorizationCredentials {
        const parsed = parseAuthorizationHeader(req.header("authorization"));
        if (parsed) |auth| {
            if (std.ascii.eqlIgnoreCase(auth.scheme, "basic")) return auth;
        }
        if (self.auto_error) return error.Unauthorized;
        return null;
    }

    pub fn resolveDecoded(
        self: HTTPBasic,
        req: *const Request,
        allocator: std.mem.Allocator,
    ) (ResolveError || BasicDecodeError)!?HTTPBasicCredentials {
        const parsed = try self.resolve(req);
        if (parsed == null) return null;
        return decodeBasicCredentials(allocator, parsed.?.credentials);
    }
};

pub const HTTPBearer = struct {
    auto_error: bool = true,

    pub fn resolve(self: HTTPBearer, req: *const Request) ResolveError!?HTTPAuthorizationCredentials {
        const parsed = parseAuthorizationHeader(req.header("authorization"));
        if (parsed) |auth| {
            if (std.ascii.eqlIgnoreCase(auth.scheme, "bearer")) return auth;
        }
        if (self.auto_error) return error.Unauthorized;
        return null;
    }
};

pub const HTTPDigest = struct {
    auto_error: bool = true,

    pub fn resolve(self: HTTPDigest, req: *const Request) ResolveError!?HTTPAuthorizationCredentials {
        const parsed = parseAuthorizationHeader(req.header("authorization"));
        if (parsed) |auth| {
            if (std.ascii.eqlIgnoreCase(auth.scheme, "digest")) return auth;
        }
        if (self.auto_error) return error.Unauthorized;
        return null;
    }
};

pub const OAuth2PasswordBearer = struct {
    token_url: []const u8,
    scopes: []const []const u8 = &.{},
    auto_error: bool = true,

    pub fn resolve(self: OAuth2PasswordBearer, req: *const Request) ResolveError!?[]const u8 {
        _ = self.token_url;
        _ = self.scopes;
        const parsed = parseAuthorizationHeader(req.header("authorization"));
        if (parsed) |auth| {
            if (std.ascii.eqlIgnoreCase(auth.scheme, "bearer")) return auth.credentials;
        }
        if (self.auto_error) return error.Unauthorized;
        return null;
    }
};

pub const OAuth2ClientCredentialsBearer = struct {
    token_url: []const u8,
    scopes: []const []const u8 = &.{},
    auto_error: bool = true,

    pub fn resolve(self: OAuth2ClientCredentialsBearer, req: *const Request) ResolveError!?[]const u8 {
        _ = self.token_url;
        _ = self.scopes;
        return resolveBearerToken(req, self.auto_error);
    }
};

pub const OAuth2ImplicitBearer = struct {
    authorization_url: []const u8,
    scopes: []const []const u8 = &.{},
    auto_error: bool = true,

    pub fn resolve(self: OAuth2ImplicitBearer, req: *const Request) ResolveError!?[]const u8 {
        _ = self.authorization_url;
        _ = self.scopes;
        return resolveBearerToken(req, self.auto_error);
    }
};

pub const OAuth2AuthorizationCodeBearer = struct {
    authorization_url: []const u8,
    token_url: []const u8,
    scopes: []const []const u8 = &.{},
    auto_error: bool = true,

    pub fn resolve(self: OAuth2AuthorizationCodeBearer, req: *const Request) ResolveError!?[]const u8 {
        _ = self.authorization_url;
        _ = self.token_url;
        _ = self.scopes;
        return resolveBearerToken(req, self.auto_error);
    }
};

pub const OpenIdConnect = struct {
    openid_connect_url: []const u8,
    auto_error: bool = true,

    pub fn resolve(self: OpenIdConnect, req: *const Request) ResolveError!?[]const u8 {
        _ = self.openid_connect_url;
        return resolveBearerToken(req, self.auto_error);
    }
};

pub const OAuth2PasswordRequestForm = struct {
    username: []const u8,
    password: []const u8,
    scope: []const u8 = "",
    grant_type: []const u8 = "password",
    client_id: ?[]const u8 = null,
    client_secret: ?[]const u8 = null,

    pub fn fromRequest(req: *Request) anyerror!OAuth2PasswordRequestForm {
        return parseOAuth2PasswordRequestForm(req);
    }

    pub fn applyGrantedScopes(self: OAuth2PasswordRequestForm, req: *Request) !void {
        try setGrantedScopesRaw(req, self.scope);
    }

    pub fn parsedScopesAlloc(
        self: OAuth2PasswordRequestForm,
        allocator: std.mem.Allocator,
    ) ![][]const u8 {
        return parseScopesRawAlloc(allocator, self.scope);
    }
};

pub fn parseAuthorizationHeader(raw: ?[]const u8) ?HTTPAuthorizationCredentials {
    const value = raw orelse return null;
    const space_index = std.mem.indexOfScalar(u8, value, ' ') orelse return null;

    const scheme = std.mem.trim(u8, value[0..space_index], " \t");
    const credentials = std.mem.trim(u8, value[space_index + 1 ..], " \t");
    if (scheme.len == 0 or credentials.len == 0) return null;

    return .{
        .scheme = scheme,
        .credentials = credentials,
    };
}

pub fn bearerTokenFromHeader(raw: ?[]const u8) ?[]const u8 {
    const parsed = parseAuthorizationHeader(raw) orelse return null;
    if (!std.ascii.eqlIgnoreCase(parsed.scheme, "bearer")) return null;
    return parsed.credentials;
}

pub fn decodeBasicCredentials(
    allocator: std.mem.Allocator,
    encoded_credentials: []const u8,
) BasicDecodeError!HTTPBasicCredentials {
    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(encoded_credentials);
    const decoded = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(decoded);

    try std.base64.standard.Decoder.decode(decoded, encoded_credentials);

    const colon = std.mem.indexOfScalar(u8, decoded, ':') orelse return error.InvalidBasicCredentials;
    return .{
        .username = decoded[0..colon],
        .password = decoded[colon + 1 ..],
        .decoded = decoded,
    };
}

pub fn grantedScopesDependencyKey() []const u8 {
    return granted_scopes_dependency_key;
}

pub fn requiredScopesDependencyKey() []const u8 {
    return required_scopes_dependency_key;
}

pub fn setGrantedScopesRaw(req: *Request, raw_scopes: []const u8) !void {
    try req.setDependencyValue(granted_scopes_dependency_key, std.mem.trim(u8, raw_scopes, " \t"));
}

pub fn setRequiredScopesRaw(req: *Request, raw_scopes: []const u8) !void {
    try req.setDependencyValue(required_scopes_dependency_key, std.mem.trim(u8, raw_scopes, " \t"));
}

pub fn setGrantedScopes(req: *Request, scopes: []const []const u8) !void {
    const raw = try joinScopes(req.allocator, scopes);
    defer req.allocator.free(raw);
    try setGrantedScopesRaw(req, raw);
}

pub fn setRequiredScopes(req: *Request, scopes: []const []const u8) !void {
    const raw = try joinScopes(req.allocator, scopes);
    defer req.allocator.free(raw);
    try setRequiredScopesRaw(req, raw);
}

pub fn hasRequiredScopes(req: *const Request, required_scopes: []const []const u8) bool {
    if (required_scopes.len == 0) return true;

    const granted_raw = req.dependency(granted_scopes_dependency_key) orelse
        req.dependency("scope") orelse
        req.dependency("scopes") orelse return false;

    return hasScopesRaw(granted_raw, required_scopes);
}

pub fn hasScopesRaw(granted_raw: []const u8, required_scopes: []const []const u8) bool {
    if (required_scopes.len == 0) return true;

    for (required_scopes) |required_scope| {
        if (!scopeSetContains(granted_raw, required_scope)) return false;
    }
    return true;
}

pub fn parseScopesRawAlloc(allocator: std.mem.Allocator, raw_scopes: []const u8) ![][]const u8 {
    const trimmed = std.mem.trim(u8, raw_scopes, " \t");

    var count: usize = 0;
    var count_it = std.mem.tokenizeAny(u8, trimmed, ", ");
    while (count_it.next()) |_| count += 1;

    if (count == 0) {
        return allocator.alloc([]const u8, 0);
    }

    const scopes = try allocator.alloc([]const u8, count);
    var fill_it = std.mem.tokenizeAny(u8, trimmed, ", ");
    var idx: usize = 0;
    while (fill_it.next()) |token| : (idx += 1) {
        scopes[idx] = token;
    }
    return scopes;
}

pub fn parseOAuth2PasswordRequestForm(req: *Request) anyerror!OAuth2PasswordRequestForm {
    const content_type = req.header("content-type") orelse {
        try req.addValidationIssue(.{
            .location = .body,
            .field = "body",
            .message = "Unsupported media type",
            .issue_type = "unsupported_media_type",
        });
        return error.UnsupportedMediaType;
    };

    const media_type = mediaTypeToken(content_type);
    if (!std.ascii.eqlIgnoreCase(media_type, "application/x-www-form-urlencoded") and
        !std.ascii.eqlIgnoreCase(media_type, "multipart/form-data"))
    {
        try req.addValidationIssue(.{
            .location = .body,
            .field = "body",
            .message = "Unsupported media type",
            .issue_type = "unsupported_media_type",
            .input = content_type,
        });
        return error.UnsupportedMediaType;
    }

    var form = try req.formAsLeaky(OAuth2PasswordRequestForm);
    if (form.grant_type.len == 0) {
        form.grant_type = "password";
    }
    if (!std.ascii.eqlIgnoreCase(form.grant_type, "password")) {
        try req.addValidationIssue(.{
            .location = .body,
            .field = "grant_type",
            .message = "Invalid grant_type for OAuth2 password flow",
            .issue_type = "invalid_grant_type",
            .input = form.grant_type,
        });
        return error.InvalidGrantType;
    }

    return form;
}

fn resolveBearerToken(req: *const Request, auto_error: bool) ResolveError!?[]const u8 {
    const token = bearerTokenFromHeader(req.header("authorization"));
    if (token) |value| return value;
    if (auto_error) return error.Unauthorized;
    return null;
}

fn joinScopes(allocator: std.mem.Allocator, scopes: []const []const u8) ![]u8 {
    if (scopes.len == 0) return allocator.dupe(u8, "");

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var writer = out.writer(allocator);
    for (scopes, 0..) |scope, idx| {
        if (idx != 0) try writer.writeByte(' ');
        try writer.writeAll(scope);
    }
    return out.toOwnedSlice(allocator);
}

fn scopeSetContains(raw_scopes: []const u8, expected_scope: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, raw_scopes, ", ");
    while (it.next()) |token| {
        if (std.mem.eql(u8, token, expected_scope)) return true;
    }
    return false;
}

fn mediaTypeToken(raw: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, raw, ';') orelse raw.len;
    return std.mem.trim(u8, raw[0..end], " \t");
}

fn cookieLookup(cookie_header: []const u8, key: []const u8) ?[]const u8 {
    var pairs = std.mem.splitScalar(u8, cookie_header, ';');
    while (pairs.next()) |pair| {
        const trimmed = std.mem.trim(u8, pair, " \t");
        if (trimmed.len == 0) continue;

        const idx = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const name = trimmed[0..idx];
        const value = trimmed[idx + 1 ..];
        if (std.mem.eql(u8, name, key)) return value;
    }
    return null;
}

test "bearer parsing" {
    var req = try Request.initSynthetic(std.testing.allocator, .GET, "/", "");
    defer req.deinit();

    const bearer = HTTPBearer{};
    try std.testing.expect((try bearer.resolve(&req)) == null);
}

test "authorization header and bearer helper parsing" {
    const parsed = parseAuthorizationHeader("Bearer token-123").?;
    try std.testing.expectEqualStrings("Bearer", parsed.scheme);
    try std.testing.expectEqualStrings("token-123", parsed.credentials);
    try std.testing.expectEqualStrings("token-123", bearerTokenFromHeader("Bearer token-123").?);
    try std.testing.expect(bearerTokenFromHeader("Basic dXNlcjpwYXNz") == null);
}

test "basic credential decoding helper and resolver" {
    var decoded = try decodeBasicCredentials(std.testing.allocator, "dXNlcjpwYXNz");
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("user", decoded.username);
    try std.testing.expectEqualStrings("pass", decoded.password);

    var req = try Request.initSyntheticWithHeaders(std.testing.allocator, .GET, "/", "", &.{
        .{
            .name = "authorization",
            .value = "Basic dXNlcjpwYXNz",
        },
    });
    defer req.deinit();

    const basic = HTTPBasic{};
    var parsed = (try basic.resolveDecoded(&req, std.testing.allocator)).?;
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("user", parsed.username);
    try std.testing.expectEqualStrings("pass", parsed.password);
}
