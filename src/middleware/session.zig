const std = @import("std");
const App = @import("../core/app.zig").App;
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
    sessions: std.StringHashMap(*SessionData),
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) InMemoryStore {
        return .{
            .sessions = std.StringHashMap(*SessionData).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *InMemoryStore) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.sessions.iterator();
        while (iter.next()) |entry| {
            self.destroySession(entry.key_ptr.*, entry.value_ptr.*);
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
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.sessions.get(id);
    }

    fn putFn(self: *InMemoryStore, id: []const u8) !*SessionData {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.get(id)) |existing| {
            existing.last_accessed = std.time.timestamp();
            return existing;
        }

        const owned_id = try self.allocator.dupe(u8, id);
        errdefer self.allocator.free(owned_id);

        const data = try self.allocator.create(SessionData);
        errdefer self.allocator.destroy(data);
        data.* = SessionData.init(self.allocator);

        try self.sessions.put(owned_id, data);
        return data;
    }

    fn removeFn(self: *InMemoryStore, id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.fetchRemove(id)) |entry| {
            self.destroySession(entry.key, entry.value);
        }
    }

    fn destroySession(self: *InMemoryStore, key: []const u8, data: *SessionData) void {
        data.deinit();
        self.allocator.destroy(data);
        self.allocator.free(key);
    }
};

const SessionMiddlewareState = struct {
    allocator: std.mem.Allocator,
    options: SessionOptions,
    store: SessionStore,
    owned_memory_store: ?*InMemoryStore = null,

    fn init(
        allocator: std.mem.Allocator,
        options: SessionOptions,
        custom_store: ?SessionStore,
    ) !*SessionMiddlewareState {
        const state = try allocator.create(SessionMiddlewareState);
        errdefer allocator.destroy(state);

        state.* = .{
            .allocator = allocator,
            .options = options,
            .store = undefined,
        };

        if (custom_store) |store| {
            state.store = store;
            return state;
        }

        const memory_store = try allocator.create(InMemoryStore);
        errdefer allocator.destroy(memory_store);
        memory_store.* = InMemoryStore.init(allocator);

        state.owned_memory_store = memory_store;
        state.store = memory_store.store();
        return state;
    }

    fn deinit(self: *SessionMiddlewareState) void {
        if (self.owned_memory_store) |store| {
            store.deinit();
            self.allocator.destroy(store);
        }
        self.allocator.destroy(self);
    }
};

pub fn configure(_: std.mem.Allocator, _: SessionOptions, _: ?SessionStore) void {}

pub fn deinit() void {}

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

fn sessionExpired(session: *const SessionData, options: SessionOptions) bool {
    if (options.max_age == 0) return false;
    const expires_after = @as(i64, options.max_age);
    return std.time.timestamp() - session.last_accessed >= expires_after;
}

pub fn requestHook(req: *Request, allocator: std.mem.Allocator) !void {
    _ = req;
    _ = allocator;
}

fn requestHookWithContext(req: *Request, allocator: std.mem.Allocator, context: ?*anyopaque) !void {
    const state = contextToState(context) orelse return;
    const sess_store = state.store;
    const options = state.options;

    var session_id: ?[]const u8 = null;
    if (req.header("cookie")) |cookies| {
        session_id = extractCookieValue(cookies, options.cookie_name);
    }

    var is_new = false;
    var owned_id: ?[]u8 = null;

    if (session_id) |existing_id| {
        if (sess_store.get(existing_id)) |session| {
            if (sessionExpired(session, options)) {
                sess_store.remove(existing_id);
                session_id = null;
            }
        } else {
            session_id = null;
        }
    }

    if (session_id == null) {
        owned_id = try generateSessionId(allocator);
        session_id = owned_id.?;
        is_new = true;
    }
    defer if (owned_id) |id| allocator.free(id);

    _ = try sess_store.getOrCreate(session_id.?);

    try req.setDependencyValue("_session_id", session_id.?);
    if (is_new) {
        try req.setDependencyValue("_session_new", "true");
    }
}

pub fn responseHook(req: *Request, response: *Response, allocator: std.mem.Allocator) !void {
    _ = req;
    _ = response;
    _ = allocator;
}

fn responseHookWithContext(
    req: *Request,
    response: *Response,
    allocator: std.mem.Allocator,
    context: ?*anyopaque,
) !void {
    const state = contextToState(context) orelse return;
    const session_id = req.dependency("_session_id") orelse return;

    if (req.dependency("_session_new") != null) {
        const same_site_str: []const u8 = switch (state.options.same_site) {
            .strict => "Strict",
            .lax => "Lax",
            .none => "None",
        };

        var cookie_buf: std.ArrayList(u8) = .empty;
        try cookie_buf.writer(allocator).print("{s}={s}; Path={s}; SameSite={s}", .{
            state.options.cookie_name,
            session_id,
            state.options.cookie_path,
            same_site_str,
        });
        if (state.options.http_only) try cookie_buf.appendSlice(allocator, "; HttpOnly");
        if (state.options.secure) try cookie_buf.appendSlice(allocator, "; Secure");
        if (state.options.max_age > 0) {
            try cookie_buf.writer(allocator).print("; Max-Age={d}", .{state.options.max_age});
        }

        const cookie_str = try cookie_buf.toOwnedSlice(allocator);
        defer allocator.free(cookie_str);
        try response.setHeader(allocator, "Set-Cookie", cookie_str);
    }
}

fn deinitContext(context: ?*anyopaque, allocator: std.mem.Allocator) void {
    _ = allocator;
    const state = contextToState(context) orelse return;
    state.deinit();
}

fn contextToState(context: ?*anyopaque) ?*SessionMiddlewareState {
    const ptr = context orelse return null;
    return @ptrCast(@alignCast(ptr));
}

pub fn middlewareWithStore(
    allocator: std.mem.Allocator,
    options: SessionOptions,
    store: SessionStore,
) App.Middleware {
    const state = SessionMiddlewareState.init(allocator, options, store) catch @panic("failed to initialize session middleware");
    return .{
        .name = "session",
        .context = @ptrCast(state),
        .request_hook_with_context = &requestHookWithContext,
        .response_hook_with_context = &responseHookWithContext,
        .deinit_hook = &deinitContext,
    };
}

/// Create a Middleware struct ready to register with the app.
pub fn middleware(allocator: std.mem.Allocator, options: SessionOptions) App.Middleware {
    const state = SessionMiddlewareState.init(allocator, options, null) catch @panic("failed to initialize session middleware");
    return .{
        .name = "session",
        .context = @ptrCast(state),
        .request_hook_with_context = &requestHookWithContext,
        .response_hook_with_context = &responseHookWithContext,
        .deinit_hook = &deinitContext,
    };
}
