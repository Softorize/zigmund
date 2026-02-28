const std = @import("std");
const deps = @import("../deps/mod.zig");
const security = @import("../security/mod.zig");
const Response = @import("../http/response.zig").Response;

pub fn unauthorizedResponse(allocator: std.mem.Allocator) Response {
    var response = Response.text("unauthorized").withStatus(.unauthorized);
    response.setHeader(allocator, "www-authenticate", "Bearer") catch |err| {
        std.log.debug("failed to set header: {s}", .{@errorName(err)});
    };
    return response;
}

pub fn insufficientScopeResponse(allocator: std.mem.Allocator) Response {
    var response = Response.text("forbidden").withStatus(.forbidden);
    response.setHeader(allocator, "www-authenticate", "Bearer error=\"insufficient_scope\"") catch |err| {
        std.log.debug("failed to set header: {s}", .{@errorName(err)});
    };
    return response;
}

pub fn challengeForSecurityScheme(scheme: security.OpenApiSecurityScheme) ?[]const u8 {
    return switch (scheme) {
        .http => |http| httpChallenge(http.scheme),
        .oauth2, .openid_connect => "Bearer",
        .api_key => null,
    };
}

pub fn httpChallenge(raw_scheme: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(raw_scheme, "basic")) {
        return "Basic realm=\"zigmund\"";
    }
    if (std.ascii.eqlIgnoreCase(raw_scheme, "bearer")) return "Bearer";
    if (std.ascii.eqlIgnoreCase(raw_scheme, "digest")) {
        return "Digest realm=\"zigmund\", qop=\"auth\", algorithm=SHA-256";
    }
    return raw_scheme;
}

pub fn dependencyErrorToResponse(allocator: std.mem.Allocator, err: deps.RunError) Response {
    return switch (err) {
        error.Unauthorized => unauthorizedResponse(allocator),
        error.InsufficientScope => insufficientScopeResponse(allocator),
        error.MissingDependency => Response.text("missing dependency").withStatus(.internal_server_error),
        error.DependencyCycleDetected => Response.text("dependency cycle detected").withStatus(.internal_server_error),
        error.DependencyExecutionFailed => Response.text("dependency execution failed").withStatus(.internal_server_error),
    };
}

/// Maps middleware errors to HTTP responses.
/// NOTE: Uses runtime error name comparison because middleware returns `anyerror`.
/// This means any error named "Unauthorized" from any error set will match.
/// This is a known limitation of the current design.
pub fn middlewareErrorToResponse(allocator: std.mem.Allocator, err: anyerror) Response {
    if (std.mem.eql(u8, @errorName(err), "Unauthorized")) {
        return unauthorizedResponse(allocator);
    }
    if (std.mem.eql(u8, @errorName(err), "InsufficientScope")) {
        return insufficientScopeResponse(allocator);
    }
    return Response.text("middleware execution failed").withStatus(.internal_server_error);
}
