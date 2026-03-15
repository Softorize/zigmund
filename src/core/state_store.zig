const std = @import("std");

pub const CleanupFn = *const fn (?*anyopaque, std.mem.Allocator) void;

pub const Store = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(Entry) = .empty,
    mutex: std.Thread.Mutex = .{},

    const Entry = struct {
        key: []u8,
        value: ?*anyopaque = null,
        cleanup: ?CleanupFn = null,
    };

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Store) void {
        self.clear();
        self.entries.deinit(self.allocator);
    }

    pub fn setBorrowed(self: *Store, key: []const u8, value: ?*anyopaque) !void {
        try self.upsert(key, value, null);
    }

    pub fn setOwned(self: *Store, key: []const u8, value: ?*anyopaque, cleanup: CleanupFn) !void {
        try self.upsert(key, value, cleanup);
    }

    pub fn getPtr(self: *Store, key: []const u8) ?*anyopaque {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.key, key)) return entry.value;
        }
        return null;
    }

    pub fn getAs(self: *Store, comptime Ptr: type, key: []const u8) ?Ptr {
        const raw = self.getPtr(key) orelse return null;
        const info = @typeInfo(Ptr);
        if (info != .pointer) {
            @compileError("state lookups require a pointer type");
        }
        return @ptrCast(@alignCast(raw));
    }

    pub fn remove(self: *Store, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.entries.items, 0..) |entry, idx| {
            if (!std.mem.eql(u8, entry.key, key)) continue;
            self.releaseEntry(entry);
            _ = self.entries.swapRemove(idx);
            return true;
        }
        return false;
    }

    pub fn clear(self: *Store) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.entries.items) |entry| {
            self.releaseEntry(entry);
        }
        self.entries.clearRetainingCapacity();
    }

    pub fn erasePointer(value: anytype) *anyopaque {
        const T = @TypeOf(value);
        if (@typeInfo(T) != .pointer) {
            @compileError("state values must be pointers");
        }
        return @ptrCast(@constCast(value));
    }

    pub fn normalizeCleanup(cleanup: anytype) CleanupFn {
        const T = @TypeOf(cleanup);
        if (T == CleanupFn) return cleanup;
        if (@typeInfo(T) == .@"fn") {
            const ptr: CleanupFn = &cleanup;
            return ptr;
        }
        @compileError("state cleanup must be fn(?*anyopaque, std.mem.Allocator) void");
    }

    fn upsert(self: *Store, key: []const u8, value: ?*anyopaque, cleanup: ?CleanupFn) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.entries.items) |*entry| {
            if (!std.mem.eql(u8, entry.key, key)) continue;
            if (entry.cleanup) |previous_cleanup| previous_cleanup(entry.value, self.allocator);
            entry.value = value;
            entry.cleanup = cleanup;
            return;
        }

        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);

        try self.entries.append(self.allocator, .{
            .key = owned_key,
            .value = value,
            .cleanup = cleanup,
        });
    }

    fn releaseEntry(self: *Store, entry: Entry) void {
        if (entry.cleanup) |cleanup| cleanup(entry.value, self.allocator);
        self.allocator.free(entry.key);
    }
};
