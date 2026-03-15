const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/security/oauth2-jwt/";

/// Shared secret for HS256 JWT signing (demo only — use env vars in production).
const JWT_SECRET = "zigmund-demo-secret-key-change-me";

/// Security provider using VerifiedHS256Bearer — validates the JWT signature,
/// expiry, and issuer, then returns the raw (verified) token string.
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

/// Protected endpoint — returns the decoded JWT claims from the verified token.
fn readProtected(
    jwt: zigmund.Security(jwtProvider, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const token = jwt.value.?;

    // Parse the payload segment to expose claims as JSON.
    const first_dot = std.mem.indexOfScalar(u8, token, '.') orelse
        return zigmund.Response.json(allocator, .{ .@"error" = "malformed_token" });
    const second_dot = std.mem.indexOfScalarPos(u8, token, first_dot + 1, '.') orelse
        return zigmund.Response.json(allocator, .{ .@"error" = "malformed_token" });

    const payload_segment = token[first_dot + 1 .. second_dot];

    var payload_buf: [8192]u8 = undefined;
    const decoded_len = std.base64.url_safe_no_pad.Decoder.calcSizeForSlice(payload_segment) catch
        return zigmund.Response.json(allocator, .{ .@"error" = "invalid_base64" });

    if (decoded_len > payload_buf.len)
        return zigmund.Response.json(allocator, .{ .@"error" = "payload_too_large" });

    std.base64.url_safe_no_pad.Decoder.decode(payload_buf[0..decoded_len], payload_segment) catch
        return zigmund.Response.json(allocator, .{ .@"error" = "invalid_base64" });

    const decoded_payload = payload_buf[0..decoded_len];

    // Copy the decoded JSON payload so Response can own it.
    const payload_copy = try allocator.dupe(u8, decoded_payload);
    return .{
        .status = .ok,
        .body = payload_copy,
        .content_type = "application/json",
        .owned_body = payload_copy,
    };
}

/// POST /token — issues a signed HS256 JWT for the given username.
/// Accepts an OAuth2 password-grant form (username + password).
fn issueToken(
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const form = try zigmund.OAuth2PasswordRequestForm.fromRequest(req);

    // For the demo any username/password is accepted. In production, validate
    // credentials against a real user store.
    const iat = std.time.timestamp();
    const exp = iat + 3600; // 1-hour expiry

    const payload_json = try std.fmt.allocPrint(allocator, "{{\"sub\":\"{s}\",\"iss\":\"zigmund-demo\",\"iat\":{d},\"exp\":{d}}}", .{
        form.username,
        iat,
        exp,
    });
    defer allocator.free(payload_json);

    const header_json = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";

    const token = try makeHs256Jwt(allocator, header_json, payload_json, JWT_SECRET);
    defer allocator.free(token);

    return zigmund.Response.json(allocator, .{
        .access_token = token,
        .token_type = "bearer",
    });
}

/// Build an HS256-signed JWT from raw header/payload JSON strings.
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

    const encoded_sig = try encodeBase64UrlNoPad(allocator, &signature);
    defer allocator.free(encoded_sig);

    return std.fmt.allocPrint(allocator, "{s}.{s}.{s}", .{ header, payload, encoded_sig });
}

fn encodeBase64UrlNoPad(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const len = std.base64.url_safe_no_pad.Encoder.calcSize(data.len);
    const out = try allocator.alloc(u8, len);
    _ = std.base64.url_safe_no_pad.Encoder.encode(out, data);
    return out;
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addSecurityScheme("oauth2JwtBearer", .{
        .oauth2 = .{
            .flows = .{
                .password = .{
                    .token_url = "/tutorial/security/oauth2-jwt/token",
                },
            },
        },
    });

    try app.post("/tutorial/security/oauth2-jwt/token", issueToken, .{
        .summary = "Issue an HS256-signed JWT via OAuth2 password grant",
        .operation_id = "tutorial_security_oauth2_jwt_token",
        .tags = &.{ "parity", "tutorial" },
    });

    try app.get("/tutorial/security/oauth2-jwt/protected", readProtected, .{
        .summary = "Access a protected resource — JWT signature and claims are validated",
        .operation_id = "tutorial_security_oauth2_jwt_protected",
        .tags = &.{ "parity", "tutorial" },
    });
}
