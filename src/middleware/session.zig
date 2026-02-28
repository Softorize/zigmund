const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const SessionOptions = struct {
    /// Name of the session cookie.
    cookie_name: []const u8 = "session_id",
    /// Session expiry in seconds (0 = browser session).
    max_age: u32 = 3600,
    /// Cookie path.
    cookie_path: []const u8 = "/",
    /// Cookie HttpOnly flag.
    http_only: bool = true,
    /// Cookie secure flag.
    secure: bool = false,
    /// Cookie SameSite.
    same_site: enum { strict, lax, none } = .lax,
};

/// Session data stored per session ID.
pub const SessionData = struct {
    values: std.StringHashMap([]const u8),
    created_at: i64,
    last_accessed: i64,
    modified: bool,

    fn init(allocator: std.mem.Allocator) SessionData {
        return .{
            .values = std.StringHashMap([]const u8).init(allocator),
            .created_at = std.time.timestamp(),
            .last_accessed = std.time.timestamp(),
            .modified = false,
        };
    }

    fn deinit(self: *SessionData) void {
        self.values.deinit();
    }
};

/// Pluggable session store interface.
pub const SessionStore = struct {
    ptr: *anyopaque,
    getFn: *const fn (*anyopaque, []const u8) ?*SessionData,
    putFn: *const fn (*anyopaque, []const u8) anyerror!*SessionData,
    removeFn: *const fn (*anyopaque, []const u8) void,

    pub fn get(self: SessionStore, id: []const u8) ?*SessionData {
        return self.getFn(self.ptr, id);
    }

    pub fn getOrCreate(self: SessionStore, id: []const u8) !*SessionData {
        return self.putFn(self.ptr, id);
    }

    pub fn remove(self: SessionStore, id: []const u8) void {
        self.removeFn(self.ptr, id);
    }
};

/// Default in-memory session store.
pub const InMemoryStore = struct {
    sessions: std.StringHashMap(SessionData),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) InMemoryStore {
        return .{
            .sessions = std.StringHashMap(SessionData).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *InMemoryStore) void {
        var iter = self.sessions.iterator();
        while (iter.next()) |entry| {
            var data = entry.value_ptr;
            data.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.sessions.deinit();
    }

    pub fn store(self: *InMemoryStore) SessionStore {
        return .{
            .ptr = @ptrCast(self),
            .getFn = @ptrCast(&getFn),
            .putFn = @ptrCast(&putFn),
            .removeFn = @ptrCast(&removeFn),
        };
    }

    fn getFn(self: *InMemoryStore, id: []const u8) ?*SessionData {
        return self.sessions.getPtr(id);
    }

    fn putFn(self: *InMemoryStore, id: []const u8) !*SessionData {
        if (self.sessions.getPtr(id)) |existing| {
            existing.last_accessed = std.time.timestamp();
            return existing;
        }
        const owned_id = try self.allocator.dupe(u8, id);
        const result = try self.sessions.getOrPut(owned_id);
        if (!result.found_existing) {
            result.value_ptr.* = SessionData.init(self.allocator);
        }
        return result.value_ptr;
    }

    fn removeFn(self: *InMemoryStore, id: []const u8) void {
        if (self.sessions.fetchRemove(id)) |entry| {
            var data = entry.value;
            data.deinit();
            self.allocator.free(entry.key);
        }
    }
};

var global_options: SessionOptions = .{};
var global_store: ?SessionStore = null;
var global_memory_store: ?InMemoryStore = null;

pub fn configure(allocator: std.mem.Allocator, options: SessionOptions, custom_store: ?SessionStore) void {
    global_options = options;
    if (custom_store) |cs| {
        global_store = cs;
    } else {
        if (global_memory_store == null) {
            global_memory_store = InMemoryStore.init(allocator);
        }
        global_store = global_memory_store.?.store();
    }
}

pub fn deinit() void {
    if (global_memory_store) |*ms| {
        ms.deinit();
        global_memory_store = null;
    }
    global_store = null;
}

fn generateSessionId(allocator: std.mem.Allocator) ![]u8 {
    var bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&bytes);
    const hex = std.fmt.bytesToHex(bytes, .lower);
    return try allocator.dupe(u8, &hex);
}

fn extractCookieValue(cookies: []const u8, name: []const u8) ?[]const u8 {
    var iter = std.mem.splitSequence(u8, cookies, "; ");
    while (iter.next()) |pair| {
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
            const key = std.mem.trim(u8, pair[0..eq], " ");
            if (std.mem.eql(u8, key, name)) {
                return pair[eq + 1 ..];
            }
        }
    }
    return null;
}

/// Request hook: load or create session.
pub fn requestHook(req: *Request, allocator: std.mem.Allocator) !void {
    const sess_store = global_store orelse return;

    // Look for existing session cookie
    var session_id: ?[]const u8 = null;
    if (req.header("cookie")) |cookies| {
        session_id = extractCookieValue(cookies, global_options.cookie_name);
    }

    var is_new = false;
    if (session_id == null) {
        session_id = try generateSessionId(allocator);
        is_new = true;
    }

    // Get or create session
    const session = try sess_store.getOrCreate(session_id.?);
    _ = session;

    try req.setDependencyValue("_session_id", session_id.?);
    if (is_new) {
        try req.setDependencyValue("_session_new", "true");
    }
}

/// Response hook: set session cookie.
pub fn responseHook(req: *Request, response: *Response, allocator: std.mem.Allocator) !void {
    const session_id = req.dependency("_session_id") orelse return;

    // Only set cookie for new sessions or if modified
    if (req.dependency("_session_new") != null) {
        const same_site_str: []const u8 = switch (global_options.same_site) {
            .strict => "Strict",
            .lax => "Lax",
            .none => "None",
        };

        var cookie_buf: std.ArrayList(u8) = .empty;
        try cookie_buf.writer(allocator).print("{s}={s}; Path={s}; SameSite={s}", .{
            global_options.cookie_name,
            session_id,
            global_options.cookie_path,
            same_site_str,
        });
        if (global_options.http_only) try cookie_buf.appendSlice(allocator, "; HttpOnly");
        if (global_options.secure) try cookie_buf.appendSlice(allocator, "; Secure");
        if (global_options.max_age > 0) {
            try cookie_buf.writer(allocator).print("; Max-Age={d}", .{global_options.max_age});
        }

        try response.setHeader(allocator, "Set-Cookie", try cookie_buf.toOwnedSlice(allocator));
    }
}

/// Create a Middleware struct ready to register with the app.
pub fn middleware(allocator: std.mem.Allocator, options: SessionOptions) @import("../core/app.zig").App.Middleware {
    configure(allocator, options, null);
    return .{
        .name = "session",
        .request_hook = &requestHook,
        .response_hook = &responseHook,
    };
}
