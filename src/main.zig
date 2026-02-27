const std = @import("std");
const zigmund = @import("zigmund");

pub fn main() !void {
    _ = zigmund;
    std.debug.print("Use `zig build run -- <command>` to run Zigmund CLI.\n", .{});
}
