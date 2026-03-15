const std = @import("std");

pub fn lookupFieldAlias(
    comptime Model: type,
    comptime decl_name: []const u8,
    comptime field_name: []const u8,
) ?[]const u8 {
    if (!@hasDecl(Model, decl_name)) return null;

    const raw = @field(Model, decl_name);
    const RawType = @TypeOf(raw);
    switch (@typeInfo(RawType)) {
        .pointer => |ptr| {
            if (ptr.size == .slice) {
                inline for (raw) |entry| {
                    validateAliasEntry(@TypeOf(entry));
                    if (std.mem.eql(u8, entry.field, field_name)) return entry.alias;
                }
            } else if (@typeInfo(ptr.child) == .array) {
                inline for (raw.*) |entry| {
                    validateAliasEntry(@TypeOf(entry));
                    if (std.mem.eql(u8, entry.field, field_name)) return entry.alias;
                }
            } else if (ptr.size == .one and @typeInfo(ptr.child) == .@"struct") {
                const entry = raw.*;
                validateAliasEntry(@TypeOf(entry));
                if (std.mem.eql(u8, entry.field, field_name)) return entry.alias;
            } else {
                @compileError("parameter model aliases must be slices, arrays, or pointers to alias entries");
            }
        },
        .array => {
            inline for (raw[0..]) |entry| {
                validateAliasEntry(@TypeOf(entry));
                if (std.mem.eql(u8, entry.field, field_name)) return entry.alias;
            }
        },
        else => @compileError("parameter model aliases must be a slice or array"),
    }
    return null;
}

fn validateAliasEntry(comptime EntryType: type) void {
    if (@typeInfo(EntryType) != .@"struct") {
        @compileError("parameter model alias entries must be structs with `field` and `alias`");
    }
    if (!@hasField(EntryType, "field") or !@hasField(EntryType, "alias")) {
        @compileError("parameter model alias entries must define `field` and `alias`");
    }
    if (@FieldType(EntryType, "field") != []const u8 or @FieldType(EntryType, "alias") != []const u8) {
        @compileError("parameter model alias entry fields must be []const u8");
    }
}
