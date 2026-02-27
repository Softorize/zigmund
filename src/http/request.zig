const std = @import("std");

pub const Request = struct {
    pub const ValidationLocation = enum {
        query,
        path,
        header,
        cookie,
        body,

        pub fn asString(self: ValidationLocation) []const u8 {
            return switch (self) {
                .query => "query",
                .path => "path",
                .header => "header",
                .cookie => "cookie",
                .body => "body",
            };
        }
    };

    pub const ValidationIssue = struct {
        location: ValidationLocation,
        field: []const u8,
        message: []const u8,
        issue_type: []const u8,
        input: ?[]const u8 = null,
    };

    pub const UploadFile = struct {
        filename: ?[]const u8 = null,
        content_type: ?[]const u8 = null,
        data: []const u8 = "",
    };

    pub const DependencyCleanupFn = *const fn (*Request, []const u8, []const u8, std.mem.Allocator) anyerror!void;

    const SyntheticHeader = struct {
        name: []u8,
        value: []u8,
    };

    const MultipartPart = struct {
        name: []const u8,
        filename: ?[]const u8 = null,
        content_type: ?[]const u8 = null,
        data: []const u8 = "",
    };

    const DependencyCleanup = struct {
        key: []u8,
        value: []u8,
        run: DependencyCleanupFn,
    };

    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    raw: ?*std.http.Server.Request = null,
    peer_address: ?std.net.Address = null,
    method: std.http.Method,
    target: []const u8,
    path: []const u8,
    query: []const u8,
    body: []const u8 = "",
    owned_body: ?[]u8 = null,
    request_id: ?[]const u8 = null,
    owned_request_id: ?[]u8 = null,
    path_params: std.StringHashMapUnmanaged([]const u8) = .empty,
    query_params: std.StringHashMapUnmanaged([]const u8) = .empty,
    synthetic_headers: std.ArrayListUnmanaged(SyntheticHeader) = .empty,
    dependency_values: std.StringHashMapUnmanaged([]const u8) = .empty,
    dependency_owned_values: std.ArrayListUnmanaged([]u8) = .empty,
    dependency_cleanups: std.ArrayListUnmanaged(DependencyCleanup) = .empty,
    dependency_cleanups_ran: bool = false,
    validation_issues: std.ArrayListUnmanaged(ValidationIssue) = .empty,

    pub const BodyError = error{BodyTooLarge} || std.http.Server.Request.ExpectContinueError || std.Io.Reader.LimitedAllocError;

    pub fn initFromRaw(allocator: std.mem.Allocator, raw: *std.http.Server.Request) !Request {
        return initFromRawWithBodyLimit(allocator, raw, 8 * 1024 * 1024);
    }

    pub fn initFromRawWithBodyLimit(
        allocator: std.mem.Allocator,
        raw: *std.http.Server.Request,
        max_body_bytes: usize,
    ) !Request {
        return initFromRawWithBodyLimitAndPeer(allocator, raw, max_body_bytes, null);
    }

    pub fn initFromRawWithBodyLimitAndPeer(
        allocator: std.mem.Allocator,
        raw: *std.http.Server.Request,
        max_body_bytes: usize,
        peer_address: ?std.net.Address,
    ) !Request {
        const split = splitTarget(raw.head.target);
        var req: Request = .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .raw = raw,
            .peer_address = peer_address,
            .method = raw.head.method,
            .target = raw.head.target,
            .path = split.path,
            .query = split.query,
            .body = "",
        };
        errdefer req.deinit();

        try req.storeRawHeaders(raw);
        try req.parseQueryParams();
        try req.readBodyFromRaw(max_body_bytes);
        return req;
    }

    pub fn initSynthetic(
        allocator: std.mem.Allocator,
        method: std.http.Method,
        target: []const u8,
        body: []const u8,
    ) !Request {
        return initSyntheticWithHeaders(allocator, method, target, body, &.{});
    }

    pub fn initSyntheticWithHeaders(
        allocator: std.mem.Allocator,
        method: std.http.Method,
        target: []const u8,
        body: []const u8,
        headers: []const std.http.Header,
    ) !Request {
        const split = splitTarget(target);
        var req: Request = .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .raw = null,
            .method = method,
            .target = target,
            .path = split.path,
            .query = split.query,
            .body = body,
        };
        errdefer req.deinit();

        try req.storeSyntheticHeaders(headers);
        try req.parseQueryParams();
        return req;
    }

    pub fn deinit(self: *Request) void {
        self.arena.deinit();

        if (self.owned_body) |buf| {
            self.allocator.free(buf);
            self.owned_body = null;
        }
        if (self.owned_request_id) |id| {
            self.allocator.free(id);
            self.owned_request_id = null;
            self.request_id = null;
        }

        for (self.dependency_owned_values.items) |item| {
            self.allocator.free(item);
        }
        self.dependency_owned_values.deinit(self.allocator);
        self.dependency_values.deinit(self.allocator);

        for (self.dependency_cleanups.items) |cleanup| {
            self.allocator.free(cleanup.key);
            self.allocator.free(cleanup.value);
        }
        self.dependency_cleanups.deinit(self.allocator);

        self.validation_issues.deinit(self.allocator);
        for (self.synthetic_headers.items) |hdr| {
            self.allocator.free(hdr.name);
            self.allocator.free(hdr.value);
        }
        self.synthetic_headers.deinit(self.allocator);

        self.path_params.deinit(self.allocator);
        self.query_params.deinit(self.allocator);
    }

    pub fn header(self: *const Request, name: []const u8) ?[]const u8 {
        for (self.synthetic_headers.items) |hdr| {
            if (std.ascii.eqlIgnoreCase(hdr.name, name)) return hdr.value;
        }
        return null;
    }

    pub fn cookie(self: *const Request, key: []const u8) ?[]const u8 {
        const cookie_header = self.header("cookie") orelse return null;
        var pairs = std.mem.splitScalar(u8, cookie_header, ';');
        while (pairs.next()) |pair| {
            const trimmed = std.mem.trim(u8, pair, " \t");
            if (trimmed.len == 0) continue;
            const eq_idx = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            const name = trimmed[0..eq_idx];
            const value = trimmed[eq_idx + 1 ..];
            if (std.mem.eql(u8, name, key)) return value;
        }
        return null;
    }

    pub fn cookieAs(self: *Request, comptime T: type, key: []const u8) !T {
        const raw_value = self.cookie(key) orelse {
            if (@typeInfo(T) == .optional) return null;
            try self.addValidationIssue(.{
                .location = .cookie,
                .field = key,
                .message = "Field required",
                .issue_type = "missing",
            });
            return error.ValidationFailed;
        };

        return parseScalar(T, raw_value) catch {
            try self.addValidationIssue(.{
                .location = .cookie,
                .field = key,
                .message = "Invalid value",
                .issue_type = "type_error",
                .input = raw_value,
            });
            return error.ValidationFailed;
        };
    }

    pub fn setPathParam(self: *Request, key: []const u8, value: []const u8) !void {
        try self.path_params.put(self.allocator, key, value);
    }

    pub fn param(self: *const Request, key: []const u8) ?[]const u8 {
        return self.path_params.get(key);
    }

    pub fn queryParam(self: *const Request, key: []const u8) ?[]const u8 {
        return self.query_params.get(key);
    }

    pub fn queryAs(self: *Request, comptime T: type, key: []const u8) !T {
        const raw_value = self.queryParam(key) orelse {
            if (@typeInfo(T) == .optional) return null;
            try self.addValidationIssue(.{
                .location = .query,
                .field = key,
                .message = "Field required",
                .issue_type = "missing",
            });
            return error.ValidationFailed;
        };

        return parseScalar(T, raw_value) catch {
            try self.addValidationIssue(.{
                .location = .query,
                .field = key,
                .message = "Invalid value",
                .issue_type = "type_error",
                .input = raw_value,
            });
            return error.ValidationFailed;
        };
    }

    pub fn paramAs(self: *Request, comptime T: type, key: []const u8) !T {
        const raw_value = self.param(key) orelse {
            if (@typeInfo(T) == .optional) return null;
            try self.addValidationIssue(.{
                .location = .path,
                .field = key,
                .message = "Field required",
                .issue_type = "missing",
            });
            return error.ValidationFailed;
        };

        return parseScalar(T, raw_value) catch {
            try self.addValidationIssue(.{
                .location = .path,
                .field = key,
                .message = "Invalid value",
                .issue_type = "type_error",
                .input = raw_value,
            });
            return error.ValidationFailed;
        };
    }

    pub fn headerAs(self: *Request, comptime T: type, key: []const u8) !T {
        const raw_value = self.header(key) orelse {
            if (@typeInfo(T) == .optional) return null;
            try self.addValidationIssue(.{
                .location = .header,
                .field = key,
                .message = "Field required",
                .issue_type = "missing",
            });
            return error.ValidationFailed;
        };

        return parseScalar(T, raw_value) catch {
            try self.addValidationIssue(.{
                .location = .header,
                .field = key,
                .message = "Invalid value",
                .issue_type = "type_error",
                .input = raw_value,
            });
            return error.ValidationFailed;
        };
    }

    pub fn bodyJson(self: *Request, comptime T: type) !std.json.Parsed(T) {
        return std.json.parseFromSlice(T, self.allocator, self.body, .{}) catch {
            try self.addValidationIssue(.{
                .location = .body,
                .field = "body",
                .message = "Invalid JSON body",
                .issue_type = "json_invalid",
                .input = self.body,
            });
            return error.ValidationFailed;
        };
    }

    pub fn bodyJsonLeaky(self: *Request, comptime T: type) !T {
        return std.json.parseFromSliceLeaky(T, self.arena.allocator(), self.body, .{}) catch {
            try self.addValidationIssue(.{
                .location = .body,
                .field = "body",
                .message = "Invalid JSON body",
                .issue_type = "json_invalid",
                .input = self.body,
            });
            return error.ValidationFailed;
        };
    }

    pub fn formField(self: *Request, key: []const u8) !?[]const u8 {
        if (self.isMultipartFormData()) {
            const parts = try self.multipartPartsLeaky();
            for (parts) |part| {
                if (!std.mem.eql(u8, part.name, key)) continue;
                return part.data;
            }
            return null;
        }

        var pairs = std.mem.splitScalar(u8, self.body, '&');
        while (pairs.next()) |pair| {
            if (pair.len == 0) continue;

            const eq_idx = std.mem.indexOfScalar(u8, pair, '=') orelse {
                const decoded_key = try self.decodeFormComponentLeaky(pair);
                if (std.mem.eql(u8, decoded_key, key)) return "";
                continue;
            };

            const decoded_key = try self.decodeFormComponentLeaky(pair[0..eq_idx]);
            if (!std.mem.eql(u8, decoded_key, key)) continue;

            const value = pair[eq_idx + 1 ..];
            return try self.decodeFormComponentLeaky(value);
        }
        return null;
    }

    pub fn formAsLeaky(self: *Request, comptime T: type) !T {
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                var out: T = undefined;
                inline for (info.fields) |field| {
                    const raw_value = self.formField(field.name) catch {
                        try self.addValidationIssue(.{
                            .location = .body,
                            .field = field.name,
                            .message = "Invalid form encoding",
                            .issue_type = "form_invalid",
                            .input = self.body,
                        });
                        return error.ValidationFailed;
                    };

                    if (raw_value) |raw| {
                        const parsed = parseFormValue(field.type, raw) catch {
                            try self.addValidationIssue(.{
                                .location = .body,
                                .field = field.name,
                                .message = "Invalid value",
                                .issue_type = "type_error",
                                .input = raw,
                            });
                            return error.ValidationFailed;
                        };
                        @field(out, field.name) = parsed;
                    } else {
                        if (field.default_value_ptr) |default_ptr| {
                            const typed_default: *const field.type = @ptrCast(@alignCast(default_ptr));
                            @field(out, field.name) = typed_default.*;
                        } else if (@typeInfo(field.type) == .optional) {
                            @field(out, field.name) = null;
                        } else {
                            try self.addValidationIssue(.{
                                .location = .body,
                                .field = field.name,
                                .message = "Field required",
                                .issue_type = "missing",
                            });
                            return error.ValidationFailed;
                        }
                    }
                }
                return out;
            },
            else => {
                const decoded = self.decodeFormComponentLeaky(self.body) catch {
                    try self.addValidationIssue(.{
                        .location = .body,
                        .field = "body",
                        .message = "Invalid form encoding",
                        .issue_type = "form_invalid",
                        .input = self.body,
                    });
                    return error.ValidationFailed;
                };
                return parseFormValue(T, decoded) catch {
                    try self.addValidationIssue(.{
                        .location = .body,
                        .field = "body",
                        .message = "Invalid value",
                        .issue_type = "type_error",
                        .input = decoded,
                    });
                    return error.ValidationFailed;
                };
            },
        }
    }

    pub fn fileAs(self: *Request, comptime T: type) !T {
        return self.fileAsWithMediaType(T, null);
    }

    pub fn fileAsWithMediaType(self: *Request, comptime T: type, expected_file_media: ?[]const u8) !T {
        if (comptime isUploadFileSliceType(T)) {
            if (self.isMultipartFormData()) {
                const parts = try self.resolveAllMultipartFileParts();
                for (parts) |part| try self.validateFileMediaType(expected_file_media, part.content_type);
                return self.coerceUploadFileSliceOutput(T, parts);
            }

            const raw_content_type = self.header("content-type");
            try self.validateFileMediaType(expected_file_media, raw_content_type);
            return self.coerceSingleUploadFileSliceOutput(T, self.body, raw_content_type);
        }

        if (self.isMultipartFormData()) {
            const part = try self.resolveMultipartFilePart();
            try self.validateFileMediaType(expected_file_media, part.content_type);
            return self.coerceFileOutput(T, part.data, part.filename, part.content_type);
        }

        const raw_content_type = self.header("content-type");
        try self.validateFileMediaType(expected_file_media, raw_content_type);
        return self.coerceFileOutput(T, self.body, null, raw_content_type);
    }

    fn validateFileMediaType(self: *Request, expected_file_media: ?[]const u8, actual_media: ?[]const u8) !void {
        const expected = expected_file_media orelse return;
        if (std.ascii.eqlIgnoreCase(expected, "application/octet-stream")) return;

        if (actual_media) |actual| {
            if (contentTypeMatches(actual, expected)) return;
        } else {
            // When no content type is provided, keep backward-compatible behavior.
            return;
        }

        try self.addValidationIssue(.{
            .location = .body,
            .field = "file",
            .message = "Unsupported media type",
            .issue_type = "unsupported_media_type",
            .input = if (actual_media) |actual| actual else "(missing)",
        });
        return error.UnsupportedMediaType;
    }

    fn isUploadFileSliceType(comptime T: type) bool {
        if (@typeInfo(T) != .pointer) return false;
        const ptr = @typeInfo(T).pointer;
        return ptr.size == .slice and ptr.child == UploadFile;
    }

    fn coerceFileOutput(
        self: *Request,
        comptime T: type,
        data: []const u8,
        filename: ?[]const u8,
        content_type: ?[]const u8,
    ) !T {
        switch (@typeInfo(T)) {
            .pointer => |ptr| {
                if (ptr.size != .slice or ptr.child != u8) {
                    try self.addValidationIssue(.{
                        .location = .body,
                        .field = "file",
                        .message = "Unsupported file target type",
                        .issue_type = "type_error",
                    });
                    return error.ValidationFailed;
                }

                if (ptr.is_const) return data;
                return try self.arena.allocator().dupe(u8, data);
            },
            .@"struct" => {
                if (T == UploadFile) {
                    return .{
                        .filename = filename,
                        .content_type = content_type,
                        .data = data,
                    };
                }
                try self.addValidationIssue(.{
                    .location = .body,
                    .field = "file",
                    .message = "Unsupported file target type",
                    .issue_type = "type_error",
                });
                return error.ValidationFailed;
            },
            else => {
                try self.addValidationIssue(.{
                    .location = .body,
                    .field = "file",
                    .message = "Unsupported file target type",
                    .issue_type = "type_error",
                });
                return error.ValidationFailed;
            },
        }
    }

    fn coerceUploadFileSliceOutput(self: *Request, comptime T: type, parts: []const MultipartPart) !T {
        const out = try self.arena.allocator().alloc(UploadFile, parts.len);
        for (parts, 0..) |part, idx| {
            out[idx] = .{
                .filename = part.filename,
                .content_type = part.content_type,
                .data = part.data,
            };
        }
        return out;
    }

    fn coerceSingleUploadFileSliceOutput(
        self: *Request,
        comptime T: type,
        data: []const u8,
        content_type: ?[]const u8,
    ) !T {
        const out = try self.arena.allocator().alloc(UploadFile, 1);
        out[0] = .{
            .filename = null,
            .content_type = content_type,
            .data = data,
        };
        return out;
    }

    pub fn setDependencyValue(self: *Request, key: []const u8, value: []const u8) !void {
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        try self.dependency_owned_values.append(self.allocator, owned_value);
        try self.dependency_values.put(self.allocator, key, owned_value);
    }

    pub fn registerDependencyCleanup(
        self: *Request,
        key: []const u8,
        value: []const u8,
        cleanup: DependencyCleanupFn,
    ) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        try self.dependency_cleanups.append(self.allocator, .{
            .key = owned_key,
            .value = owned_value,
            .run = cleanup,
        });
    }

    pub fn runDependencyCleanups(self: *Request, allocator: std.mem.Allocator) !void {
        if (self.dependency_cleanups_ran) return;
        self.dependency_cleanups_ran = true;

        var idx = self.dependency_cleanups.items.len;
        while (idx > 0) {
            idx -= 1;
            const cleanup = self.dependency_cleanups.items[idx];
            try cleanup.run(self, cleanup.key, cleanup.value, allocator);
        }
    }

    pub fn setRequestId(self: *Request, request_id: []const u8) !void {
        const owned = try self.allocator.dupe(u8, request_id);
        errdefer self.allocator.free(owned);

        if (self.owned_request_id) |current| {
            self.allocator.free(current);
        }

        self.owned_request_id = owned;
        self.request_id = owned;
    }

    pub fn requestId(self: *const Request) ?[]const u8 {
        return self.request_id;
    }

    pub fn setPeerAddress(self: *Request, peer_address: std.net.Address) void {
        self.peer_address = peer_address;
    }

    pub fn peerAddress(self: *const Request) ?std.net.Address {
        return self.peer_address;
    }

    pub fn dependency(self: *const Request, key: []const u8) ?[]const u8 {
        return self.dependency_values.get(key);
    }

    pub fn validationIssues(self: *const Request) []const ValidationIssue {
        return self.validation_issues.items;
    }

    pub fn hasValidationIssues(self: *const Request) bool {
        return self.validation_issues.items.len != 0;
    }

    fn splitTarget(target: []const u8) struct { path: []const u8, query: []const u8 } {
        if (std.mem.indexOfScalar(u8, target, '?')) |idx| {
            return .{ .path = target[0..idx], .query = target[idx + 1 ..] };
        }
        return .{ .path = target, .query = "" };
    }

    fn storeSyntheticHeaders(self: *Request, headers: []const std.http.Header) !void {
        for (headers) |hdr| {
            const name = try self.allocator.dupe(u8, hdr.name);
            errdefer self.allocator.free(name);
            const value = try self.allocator.dupe(u8, hdr.value);
            errdefer self.allocator.free(value);
            try self.synthetic_headers.append(self.allocator, .{
                .name = name,
                .value = value,
            });
        }
    }

    fn storeRawHeaders(self: *Request, raw: *std.http.Server.Request) !void {
        var it = raw.iterateHeaders();
        while (it.next()) |hdr| {
            const name = try self.allocator.dupe(u8, hdr.name);
            errdefer self.allocator.free(name);
            const value = try self.allocator.dupe(u8, hdr.value);
            errdefer self.allocator.free(value);
            try self.synthetic_headers.append(self.allocator, .{
                .name = name,
                .value = value,
            });
        }
    }

    fn parseQueryParams(self: *Request) !void {
        if (self.query.len == 0) return;

        var pairs = std.mem.splitScalar(u8, self.query, '&');
        while (pairs.next()) |pair| {
            if (pair.len == 0) continue;
            if (std.mem.indexOfScalar(u8, pair, '=')) |idx| {
                const key = pair[0..idx];
                const value = pair[idx + 1 ..];
                if (key.len == 0) continue;
                try self.query_params.put(self.allocator, key, value);
            } else {
                try self.query_params.put(self.allocator, pair, "");
            }
        }
    }

    fn readBodyFromRaw(self: *Request, max_len: usize) BodyError!void {
        const raw = self.raw orelse return;
        if (!raw.head.method.requestHasBody()) return;

        var read_buffer: [8192]u8 = undefined;
        const reader = try raw.readerExpectContinue(&read_buffer);
        const body = reader.allocRemaining(self.allocator, .limited(max_len)) catch |err| switch (err) {
            error.StreamTooLong => return error.BodyTooLarge,
            else => return err,
        };
        self.owned_body = body;
        self.body = body;
    }

    fn isMultipartFormData(self: *const Request) bool {
        const content_type = self.header("content-type") orelse return false;
        return startsWithIgnoreCase(content_type, "multipart/form-data");
    }

    fn resolveMultipartFilePart(self: *Request) !MultipartPart {
        const file_parts = try self.resolveAllMultipartFileParts();
        return file_parts[0];
    }

    fn resolveAllMultipartFileParts(self: *Request) ![]const MultipartPart {
        const parts = self.multipartPartsLeaky() catch {
            try self.addValidationIssue(.{
                .location = .body,
                .field = "file",
                .message = "Invalid multipart body",
                .issue_type = "multipart_invalid",
                .input = self.body,
            });
            return error.ValidationFailed;
        };

        var file_parts: std.ArrayList(MultipartPart) = .empty;
        errdefer file_parts.deinit(self.arena.allocator());

        for (parts) |part| {
            if (part.filename != null) {
                try file_parts.append(self.arena.allocator(), part);
            }
        }

        if (file_parts.items.len == 0) {
            for (parts) |part| {
                if (std.mem.eql(u8, part.name, "file")) {
                    try file_parts.append(self.arena.allocator(), part);
                }
            }
        }

        if (file_parts.items.len != 0) {
            return try file_parts.toOwnedSlice(self.arena.allocator());
        }

        try self.addValidationIssue(.{
            .location = .body,
            .field = "file",
            .message = "Field required",
            .issue_type = "missing",
        });
        return error.ValidationFailed;
    }

    fn multipartPartsLeaky(self: *Request) ![]const MultipartPart {
        const boundary = self.multipartBoundary() orelse return error.MissingMultipartBoundary;
        const boundary_marker = try std.fmt.allocPrint(self.arena.allocator(), "--{s}", .{boundary});
        const part_delimiter = try std.fmt.allocPrint(self.arena.allocator(), "\r\n--{s}", .{boundary});

        if (!std.mem.startsWith(u8, self.body, boundary_marker)) return error.InvalidMultipartBody;

        var cursor: usize = boundary_marker.len;
        var parts: std.ArrayList(MultipartPart) = .empty;
        errdefer parts.deinit(self.arena.allocator());

        while (cursor <= self.body.len) {
            if (std.mem.startsWith(u8, self.body[cursor..], "--")) {
                return try parts.toOwnedSlice(self.arena.allocator());
            }

            if (!std.mem.startsWith(u8, self.body[cursor..], "\r\n")) return error.InvalidMultipartBody;
            cursor += 2;

            const header_end_rel = std.mem.indexOf(u8, self.body[cursor..], "\r\n\r\n") orelse return error.InvalidMultipartBody;
            const header_blob = self.body[cursor .. cursor + header_end_rel];
            cursor += header_end_rel + 4;

            var part = try parseMultipartHeaders(header_blob);
            const body_end_rel = std.mem.indexOf(u8, self.body[cursor..], part_delimiter) orelse return error.InvalidMultipartBody;
            part.data = self.body[cursor .. cursor + body_end_rel];
            try parts.append(self.arena.allocator(), part);

            cursor += body_end_rel + 2;
            if (!std.mem.startsWith(u8, self.body[cursor..], boundary_marker)) return error.InvalidMultipartBody;
            cursor += boundary_marker.len;
        }

        return error.InvalidMultipartBody;
    }

    fn multipartBoundary(self: *const Request) ?[]const u8 {
        const content_type = self.header("content-type") orelse return null;

        var parts = std.mem.splitScalar(u8, content_type, ';');
        const media_type = std.mem.trim(u8, parts.next() orelse return null, " \t");
        if (!std.ascii.eqlIgnoreCase(media_type, "multipart/form-data")) return null;

        while (parts.next()) |segment| {
            const parameter = std.mem.trim(u8, segment, " \t");
            const eq_idx = std.mem.indexOfScalar(u8, parameter, '=') orelse continue;

            const key = std.mem.trim(u8, parameter[0..eq_idx], " \t");
            if (!std.ascii.eqlIgnoreCase(key, "boundary")) continue;

            var value = std.mem.trim(u8, parameter[eq_idx + 1 ..], " \t");
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }
            if (value.len == 0) return null;
            return value;
        }

        return null;
    }

    fn parseMultipartHeaders(headers: []const u8) !MultipartPart {
        var part: MultipartPart = .{ .name = "" };

        var lines = std.mem.splitSequence(u8, headers, "\r\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const colon_idx = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const header_name = std.mem.trim(u8, line[0..colon_idx], " \t");
            const header_value = std.mem.trim(u8, line[colon_idx + 1 ..], " \t");

            if (std.ascii.eqlIgnoreCase(header_name, "content-disposition")) {
                try parseContentDispositionHeader(header_value, &part);
            } else if (std.ascii.eqlIgnoreCase(header_name, "content-type")) {
                part.content_type = header_value;
            }
        }

        if (part.name.len == 0) return error.MultipartMissingName;
        return part;
    }

    fn parseContentDispositionHeader(value: []const u8, part: *MultipartPart) !void {
        var tokens = std.mem.splitScalar(u8, value, ';');
        const kind = std.mem.trim(u8, tokens.next() orelse return error.InvalidMultipartDisposition, " \t");
        if (!std.ascii.eqlIgnoreCase(kind, "form-data")) return error.InvalidMultipartDisposition;

        while (tokens.next()) |token| {
            const attr = std.mem.trim(u8, token, " \t");
            if (attr.len == 0) continue;

            const eq_idx = std.mem.indexOfScalar(u8, attr, '=') orelse continue;
            const key = std.mem.trim(u8, attr[0..eq_idx], " \t");
            var attr_value = std.mem.trim(u8, attr[eq_idx + 1 ..], " \t");
            if (attr_value.len >= 2 and attr_value[0] == '"' and attr_value[attr_value.len - 1] == '"') {
                attr_value = attr_value[1 .. attr_value.len - 1];
            }

            if (std.ascii.eqlIgnoreCase(key, "name")) {
                part.name = attr_value;
            } else if (std.ascii.eqlIgnoreCase(key, "filename")) {
                part.filename = attr_value;
            }
        }
    }

    fn startsWithIgnoreCase(value: []const u8, prefix: []const u8) bool {
        if (value.len < prefix.len) return false;
        return std.ascii.eqlIgnoreCase(value[0..prefix.len], prefix);
    }

    fn contentTypeMatches(actual: []const u8, expected: []const u8) bool {
        return std.ascii.eqlIgnoreCase(mediaTypeToken(actual), mediaTypeToken(expected));
    }

    fn mediaTypeToken(raw: []const u8) []const u8 {
        const end = std.mem.indexOfScalar(u8, raw, ';') orelse raw.len;
        return std.mem.trim(u8, raw[0..end], " \t");
    }

    fn parseScalar(comptime T: type, input: []const u8) !T {
        switch (@typeInfo(T)) {
            .optional => |opt| return try parseScalar(opt.child, input),
            .int => return std.fmt.parseInt(T, input, 10),
            .comptime_int => return std.fmt.parseInt(T, input, 10),
            .float => return std.fmt.parseFloat(T, input),
            .comptime_float => return std.fmt.parseFloat(T, input),
            .bool => {
                if (std.ascii.eqlIgnoreCase(input, "true") or std.mem.eql(u8, input, "1")) return true;
                if (std.ascii.eqlIgnoreCase(input, "false") or std.mem.eql(u8, input, "0")) return false;
                return error.InvalidBoolean;
            },
            .pointer => |info| {
                if (info.size == .slice and info.child == u8) return input;
                return error.UnsupportedType;
            },
            else => return error.UnsupportedType,
        }
    }

    fn parseFormValue(comptime T: type, raw: []const u8) !T {
        if (@typeInfo(T) == .optional) {
            const Child = @typeInfo(T).optional.child;
            if (raw.len == 0) return null;
            return try parseScalar(Child, raw);
        }
        return parseScalar(T, raw);
    }

    fn decodeFormComponentLeaky(self: *Request, input: []const u8) ![]const u8 {
        if (std.mem.indexOfScalar(u8, input, '+') == null and std.mem.indexOfScalar(u8, input, '%') == null) {
            return input;
        }

        const out = try self.arena.allocator().alloc(u8, input.len);
        var in_idx: usize = 0;
        var out_idx: usize = 0;
        while (in_idx < input.len) : (in_idx += 1) {
            const ch = input[in_idx];
            switch (ch) {
                '+' => {
                    out[out_idx] = ' ';
                    out_idx += 1;
                },
                '%' => {
                    if (in_idx + 2 >= input.len) return error.InvalidPercentEncoding;
                    const hi = hexNibble(input[in_idx + 1]) orelse return error.InvalidPercentEncoding;
                    const lo = hexNibble(input[in_idx + 2]) orelse return error.InvalidPercentEncoding;
                    out[out_idx] = (hi << 4) | lo;
                    out_idx += 1;
                    in_idx += 2;
                },
                else => {
                    out[out_idx] = ch;
                    out_idx += 1;
                },
            }
        }
        return out[0..out_idx];
    }

    fn hexNibble(ch: u8) ?u8 {
        return switch (ch) {
            '0'...'9' => ch - '0',
            'a'...'f' => ch - 'a' + 10,
            'A'...'F' => ch - 'A' + 10,
            else => null,
        };
    }

    pub fn addValidationIssue(self: *Request, issue: ValidationIssue) !void {
        try self.validation_issues.append(self.allocator, issue);
    }
};

test "query parsing" {
    var req = try Request.initSynthetic(std.testing.allocator, .GET, "/items?page=1&size=20", "");
    defer req.deinit();

    try std.testing.expectEqualStrings("1", req.queryParam("page").?);
    try std.testing.expectEqualStrings("20", req.queryParam("size").?);
}

test "typed query parsing" {
    var req = try Request.initSynthetic(std.testing.allocator, .GET, "/items?page=2&active=true", "");
    defer req.deinit();

    try std.testing.expectEqual(@as(i64, 2), try req.queryAs(i64, "page"));
    try std.testing.expectEqual(true, try req.queryAs(bool, "active"));
}
