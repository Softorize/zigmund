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

pub const JwtValidationOptions = struct {
    issuer: ?[]const u8 = null,
    audience: ?[]const u8 = null,
    required_scopes: []const []const u8 = &.{},
    clock_skew_seconds: i64 = 60,
    current_time_seconds: ?i64 = null,
};

pub const JwtValidationError = error{
    InvalidJwt,
    JwtUnsupportedAlgorithm,
    JwtHeaderTooLarge,
    JwtPayloadTooLarge,
    JwtSignatureMismatch,
    JwtExpired,
    JwtNotYetValid,
    JwtIssuerMismatch,
    JwtAudienceMismatch,
    JwtScopeMismatch,
};

pub const VerifiedHS256Bearer = struct {
    secret: []const u8,
    validation: JwtValidationOptions = .{},
    auto_error: bool = true,

    pub fn resolve(self: VerifiedHS256Bearer, req: *const Request) ResolveError!?[]const u8 {
        const token = bearerTokenFromHeader(req.header("authorization"));
        if (token == null) {
            if (self.auto_error) return error.Unauthorized;
            return null;
        }

        validateHs256JwtToken(token.?, self.secret, self.validation) catch |err| switch (err) {
            error.JwtScopeMismatch => return error.InsufficientScope,
            else => {
                if (self.auto_error) return error.Unauthorized;
                return null;
            },
        };
        return token.?;
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

pub fn validateHs256JwtToken(
    token: []const u8,
    secret: []const u8,
    options: JwtValidationOptions,
) JwtValidationError!void {
    const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

    const first_dot = std.mem.indexOfScalar(u8, token, '.') orelse return error.InvalidJwt;
    const second_dot = std.mem.indexOfScalarPos(u8, token, first_dot + 1, '.') orelse return error.InvalidJwt;
    if (std.mem.indexOfScalarPos(u8, token, second_dot + 1, '.') != null) return error.InvalidJwt;

    const header_segment = token[0..first_dot];
    const payload_segment = token[first_dot + 1 .. second_dot];
    const signature_segment = token[second_dot + 1 ..];
    const signing_input = token[0..second_dot];

    var header_bytes: [1024]u8 = undefined;
    const decoded_header = try decodeJwtSegment(header_segment, &header_bytes, error.JwtHeaderTooLarge);

    var payload_bytes: [8192]u8 = undefined;
    const decoded_payload = try decodeJwtSegment(payload_segment, &payload_bytes, error.JwtPayloadTooLarge);

    var parser_storage: [16 * 1024]u8 = undefined;
    var parser_fba = std.heap.FixedBufferAllocator.init(&parser_storage);
    const header_json = std.json.parseFromSliceLeaky(
        std.json.Value,
        parser_fba.allocator(),
        decoded_header,
        .{},
    ) catch return error.InvalidJwt;

    const alg = jsonStringField(header_json, "alg") orelse return error.JwtUnsupportedAlgorithm;
    if (!std.mem.eql(u8, alg, "HS256")) return error.JwtUnsupportedAlgorithm;

    const payload_json = std.json.parseFromSliceLeaky(
        std.json.Value,
        parser_fba.allocator(),
        decoded_payload,
        .{},
    ) catch return error.InvalidJwt;

    var expected_signature: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&expected_signature, signing_input, secret);

    const decoded_signature_len = std.base64.url_safe_no_pad.Decoder.calcSizeForSlice(signature_segment) catch {
        return error.InvalidJwt;
    };
    if (decoded_signature_len != expected_signature.len) return error.JwtSignatureMismatch;

    var decoded_signature: [HmacSha256.mac_length]u8 = undefined;
    std.base64.url_safe_no_pad.Decoder.decode(decoded_signature[0..], signature_segment) catch {
        return error.InvalidJwt;
    };

    if (!std.crypto.timing_safe.eql([HmacSha256.mac_length]u8, expected_signature, decoded_signature)) {
        return error.JwtSignatureMismatch;
    }

    try validateJwtClaims(payload_json, options);
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

fn decodeJwtSegment(
    segment: []const u8,
    buffer: []u8,
    too_large_error: JwtValidationError,
) JwtValidationError![]const u8 {
    const decoded_len = std.base64.url_safe_no_pad.Decoder.calcSizeForSlice(segment) catch {
        return error.InvalidJwt;
    };
    if (decoded_len > buffer.len) return too_large_error;

    std.base64.url_safe_no_pad.Decoder.decode(buffer[0..decoded_len], segment) catch {
        return error.InvalidJwt;
    };
    return buffer[0..decoded_len];
}

fn validateJwtClaims(claims: std.json.Value, options: JwtValidationOptions) JwtValidationError!void {
    const now = options.current_time_seconds orelse std.time.timestamp();
    const skew = @max(options.clock_skew_seconds, 0);

    if (jsonIntField(claims, "exp")) |expires_at| {
        if (now > expires_at + skew) return error.JwtExpired;
    }
    if (jsonIntField(claims, "nbf")) |not_before| {
        if (now + skew < not_before) return error.JwtNotYetValid;
    }

    if (options.issuer) |expected_issuer| {
        const issuer = jsonStringField(claims, "iss") orelse return error.JwtIssuerMismatch;
        if (!std.mem.eql(u8, issuer, expected_issuer)) return error.JwtIssuerMismatch;
    }

    if (options.audience) |expected_audience| {
        if (!jwtAudienceMatches(claims, expected_audience)) return error.JwtAudienceMismatch;
    }

    if (options.required_scopes.len > 0 and !jwtContainsRequiredScopes(claims, options.required_scopes)) {
        return error.JwtScopeMismatch;
    }
}

fn jsonStringField(value: std.json.Value, key: []const u8) ?[]const u8 {
    if (value != .object) return null;
    const item = value.object.get(key) orelse return null;
    return switch (item) {
        .string => |str| str,
        else => null,
    };
}

fn jsonIntField(value: std.json.Value, key: []const u8) ?i64 {
    if (value != .object) return null;
    const item = value.object.get(key) orelse return null;
    return switch (item) {
        .integer => |number| number,
        .number_string => |number| std.fmt.parseInt(i64, number, 10) catch null,
        else => null,
    };
}

fn jwtAudienceMatches(value: std.json.Value, expected_audience: []const u8) bool {
    if (value != .object) return false;
    const audience = value.object.get("aud") orelse return false;
    return switch (audience) {
        .string => |item| std.mem.eql(u8, item, expected_audience),
        .array => |items| blk: {
            for (items.items) |entry| {
                switch (entry) {
                    .string => |item| if (std.mem.eql(u8, item, expected_audience)) break :blk true,
                    else => {},
                }
            }
            break :blk false;
        },
        else => false,
    };
}

fn jwtContainsRequiredScopes(value: std.json.Value, required_scopes: []const []const u8) bool {
    if (value != .object) return false;

    const scope_value = value.object.get("scope") orelse value.object.get("scp") orelse return false;
    for (required_scopes) |required_scope| {
        if (!jwtScopeValueContains(scope_value, required_scope)) return false;
    }
    return true;
}

fn jwtScopeValueContains(scope_value: std.json.Value, required_scope: []const u8) bool {
    return switch (scope_value) {
        .string => |raw| scopeSetContains(raw, required_scope),
        .array => |items| blk: {
            for (items.items) |entry| {
                switch (entry) {
                    .string => |item| if (std.mem.eql(u8, item, required_scope)) break :blk true,
                    else => {},
                }
            }
            break :blk false;
        },
        else => false,
    };
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

fn makeHs256Jwt(
    allocator: std.mem.Allocator,
    header_json: []const u8,
    payload_json: []const u8,
    secret: []const u8,
) ![]u8 {
    const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

    const header = try encodeBase64UrlNoPad(allocator, header_json);
    defer allocator.free(header);
    const payload = try encodeBase64UrlNoPad(allocator, payload_json);
    defer allocator.free(payload);

    const signing_input = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ header, payload });
    defer allocator.free(signing_input);

    var signature: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&signature, signing_input, secret);

    const encoded_signature = try encodeBase64UrlNoPad(allocator, &signature);
    defer allocator.free(encoded_signature);

    return std.fmt.allocPrint(allocator, "{s}.{s}.{s}", .{ header, payload, encoded_signature });
}

fn encodeBase64UrlNoPad(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const len = std.base64.url_safe_no_pad.Encoder.calcSize(data.len);
    const out = try allocator.alloc(u8, len);
    _ = std.base64.url_safe_no_pad.Encoder.encode(out, data);
    return out;
}

test "hs256 jwt validator enforces issuer audience and scopes" {
    const token = try makeHs256Jwt(
        std.testing.allocator,
        "{\"alg\":\"HS256\",\"typ\":\"JWT\"}",
        "{\"iss\":\"https://issuer.example\",\"aud\":[\"zigmund-api\"],\"scope\":\"orders:read orders:write\",\"exp\":4102444800,\"nbf\":1700000000}",
        "super-secret",
    );
    defer std.testing.allocator.free(token);

    try validateHs256JwtToken(token, "super-secret", .{
        .issuer = "https://issuer.example",
        .audience = "zigmund-api",
        .required_scopes = &.{"orders:read"},
        .current_time_seconds = 1_800_000_000,
    });
}

test "verified hs256 bearer maps invalid auth and missing scopes" {
    const token = try makeHs256Jwt(
        std.testing.allocator,
        "{\"alg\":\"HS256\",\"typ\":\"JWT\"}",
        "{\"iss\":\"https://issuer.example\",\"aud\":\"zigmund-api\",\"scope\":\"orders:read\",\"exp\":4102444800}",
        "super-secret",
    );
    defer std.testing.allocator.free(token);

    const auth_header = try std.fmt.allocPrint(std.testing.allocator, "Bearer {s}", .{token});
    defer std.testing.allocator.free(auth_header);

    var req = try Request.initSyntheticWithHeaders(std.testing.allocator, .GET, "/", "", &.{
        .{ .name = "authorization", .value = auth_header },
    });
    defer req.deinit();

    const accepted = VerifiedHS256Bearer{
        .secret = "super-secret",
        .validation = .{
            .issuer = "https://issuer.example",
            .audience = "zigmund-api",
            .required_scopes = &.{"orders:read"},
            .current_time_seconds = 1_800_000_000,
        },
    };
    try std.testing.expectEqualStrings(token, (try accepted.resolve(&req)).?);

    const insufficient_scope = VerifiedHS256Bearer{
        .secret = "super-secret",
        .validation = .{
            .required_scopes = &.{"orders:delete"},
            .current_time_seconds = 1_800_000_000,
        },
    };
    try std.testing.expectError(error.InsufficientScope, insufficient_scope.resolve(&req));

    const bad_secret = VerifiedHS256Bearer{
        .secret = "wrong-secret",
    };
    try std.testing.expectError(error.Unauthorized, bad_secret.resolve(&req));
}
