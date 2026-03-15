const std = @import("std");
const epoch = std.time.epoch;

// ─── Uuid ────────────────────────────────────────────────────────────

/// A UUID represented in its canonical 36-character string form:
/// "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
///
/// Usable as a field type in Body/Query/Path parameter structs.
/// Supports JSON serialization (writes as a quoted string) and
/// JSON deserialization (parses from a quoted string).
pub const Uuid = struct {
    bytes: [36]u8,
    len: u8 = 36,

    pub const Error = error{InvalidUuid};

    pub fn toString(self: Uuid) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn eql(a: Uuid, b: Uuid) bool {
        return std.mem.eql(u8, a.bytes[0..a.len], b.bytes[0..b.len]);
    }

    /// Parse and validate a UUID string in 8-4-4-4-12 format.
    pub fn parse(input: []const u8) Error!Uuid {
        if (input.len != 36) return error.InvalidUuid;

        // Dash positions: 8, 13, 18, 23
        const dash_positions = [_]u8{ 8, 13, 18, 23 };
        for (dash_positions) |pos| {
            if (input[pos] != '-') return error.InvalidUuid;
        }

        // Validate hex digits at every non-dash position
        for (input, 0..) |c, i| {
            if (i == 8 or i == 13 or i == 18 or i == 23) continue;
            if (!isHex(c)) return error.InvalidUuid;
        }

        var uuid: Uuid = .{ .bytes = undefined, .len = 36 };
        @memcpy(&uuid.bytes, input);
        return uuid;
    }

    fn isHex(c: u8) bool {
        return switch (c) {
            '0'...'9', 'a'...'f', 'A'...'F' => true,
            else => false,
        };
    }

    /// Custom JSON serialization — emits the UUID as a JSON string.
    pub fn jsonStringify(v: @This(), jws: anytype) !void {
        try jws.write(v.bytes[0..v.len]);
    }

    /// Custom JSON deserialization — reads a JSON string and validates
    /// it as a UUID.
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
        const slice = switch (token) {
            .string, .allocated_string => |s| s,
            else => return error.UnexpectedToken,
        };
        return Uuid.parse(slice) catch return error.UnexpectedToken;
    }

    /// Custom JSON deserialization from a pre-parsed Value.
    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
        _ = allocator;
        _ = options;
        switch (source) {
            .string => |s| return Uuid.parse(s) catch return error.UnexpectedToken,
            else => return error.UnexpectedToken,
        }
    }
};

// ─── DateTime ────────────────────────────────────────────────────────

/// An instant in time stored as seconds since the Unix epoch.
///
/// Serializes to/from ISO 8601 strings ("2024-03-14T12:00:00Z") in JSON.
pub const DateTime = struct {
    epoch_seconds: i64,

    pub const Error = error{InvalidDateTime};

    pub fn now() DateTime {
        return .{ .epoch_seconds = std.time.timestamp() };
    }

    pub fn fromEpoch(seconds: i64) DateTime {
        return .{ .epoch_seconds = seconds };
    }

    /// Format as ISO 8601 string ("YYYY-MM-DDTHH:MM:SSZ") into the
    /// provided buffer.  Returns the written slice.
    pub fn toIso8601(self: DateTime, buf: []u8) []const u8 {
        if (self.epoch_seconds < 0) {
            // For negative epoch values, output a fallback representation.
            const written = std.fmt.bufPrint(buf, "1970-01-01T00:00:00Z") catch return buf[0..0];
            return written;
        }
        const secs: u64 = @intCast(self.epoch_seconds);
        const es = epoch.EpochSeconds{ .secs = secs };
        const epoch_day = es.getEpochDay();
        const day_seconds = es.getDaySeconds();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        const written = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
            year_day.year,
            month_day.month.numeric(),
            @as(u8, month_day.day_index) + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        }) catch return buf[0..0];
        return written;
    }

    /// Parse an ISO 8601 datetime string ("YYYY-MM-DDTHH:MM:SSZ") into
    /// a DateTime.
    pub fn fromIso8601(input: []const u8) Error!DateTime {
        // Minimum valid: "YYYY-MM-DDTHH:MM:SSZ" = 20 chars
        if (input.len < 20) return error.InvalidDateTime;

        const year = parseDigits(input[0..4]) orelse return error.InvalidDateTime;
        if (input[4] != '-') return error.InvalidDateTime;
        const month = parseDigits(input[5..7]) orelse return error.InvalidDateTime;
        if (input[7] != '-') return error.InvalidDateTime;
        const day = parseDigits(input[8..10]) orelse return error.InvalidDateTime;
        if (input[10] != 'T') return error.InvalidDateTime;
        const hour = parseDigits(input[11..13]) orelse return error.InvalidDateTime;
        if (input[13] != ':') return error.InvalidDateTime;
        const minute = parseDigits(input[14..16]) orelse return error.InvalidDateTime;
        if (input[16] != ':') return error.InvalidDateTime;
        const second = parseDigits(input[17..19]) orelse return error.InvalidDateTime;
        if (input[19] != 'Z') return error.InvalidDateTime;

        if (month < 1 or month > 12) return error.InvalidDateTime;
        if (day < 1 or day > 31) return error.InvalidDateTime;
        if (hour > 23) return error.InvalidDateTime;
        if (minute > 59) return error.InvalidDateTime;
        if (second > 59) return error.InvalidDateTime;

        // Convert to epoch seconds
        var total_days: i64 = 0;
        // Days from years
        var y: u16 = 1970;
        while (y < year) : (y += 1) {
            total_days += if (epoch.isLeapYear(y)) @as(i64, 366) else @as(i64, 365);
        }
        // Days from months
        const month_days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var m: u8 = 1;
        while (m < month) : (m += 1) {
            if (m == 2 and epoch.isLeapYear(year)) {
                total_days += 29;
            } else {
                total_days += month_days[m - 1];
            }
        }
        total_days += @as(i64, day) - 1;

        const total_seconds = total_days * 86400 + @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);
        return .{ .epoch_seconds = total_seconds };
    }

    fn parseDigits(slice: []const u8) ?u16 {
        var result: u16 = 0;
        for (slice) |c| {
            if (c < '0' or c > '9') return null;
            result = result * 10 + @as(u16, c - '0');
        }
        return result;
    }

    /// Custom JSON serialization — emits ISO 8601 string.
    pub fn jsonStringify(v: @This(), jws: anytype) !void {
        var buf: [32]u8 = undefined;
        const str = v.toIso8601(&buf);
        try jws.write(str);
    }

    /// Custom JSON deserialization — reads a JSON string and parses
    /// ISO 8601 format.
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
        const slice = switch (token) {
            .string, .allocated_string => |s| s,
            .number, .allocated_number => |s| {
                // Allow parsing from a bare integer (epoch seconds).
                const n = std.fmt.parseInt(i64, s, 10) catch return error.UnexpectedToken;
                return DateTime.fromEpoch(n);
            },
            else => return error.UnexpectedToken,
        };
        return DateTime.fromIso8601(slice) catch return error.UnexpectedToken;
    }

    /// Custom JSON deserialization from a pre-parsed Value.
    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
        _ = allocator;
        _ = options;
        switch (source) {
            .string => |s| return DateTime.fromIso8601(s) catch return error.UnexpectedToken,
            .integer => |n| return DateTime.fromEpoch(n),
            else => return error.UnexpectedToken,
        }
    }
};

// ─── Duration ────────────────────────────────────────────────────────

/// A non-negative time span stored as a count of seconds.
///
/// Serializes to JSON as an integer (seconds).  Deserializes from
/// either a bare integer or from a string like "3600" / "PT1H" (ISO 8601
/// duration — hours/minutes/seconds subset).
pub const Duration = struct {
    total_seconds: u64,

    pub const Error = error{InvalidDuration};

    pub fn fromSeconds(s: u64) Duration {
        return .{ .total_seconds = s };
    }

    pub fn fromMinutes(m: u64) Duration {
        return .{ .total_seconds = m * 60 };
    }

    pub fn fromHours(h: u64) Duration {
        return .{ .total_seconds = h * 3600 };
    }

    pub fn seconds(self: Duration) u64 {
        return self.total_seconds;
    }

    pub fn toMinutes(self: Duration) u64 {
        return self.total_seconds / 60;
    }

    pub fn toHours(self: Duration) u64 {
        return self.total_seconds / 3600;
    }

    /// Human-readable breakdown.
    pub fn format(self: Duration, buf: []u8) []const u8 {
        const h = self.total_seconds / 3600;
        const m = (self.total_seconds % 3600) / 60;
        const s = self.total_seconds % 60;
        const written = std.fmt.bufPrint(buf, "PT{d}H{d}M{d}S", .{ h, m, s }) catch return buf[0..0];
        return written;
    }

    /// Parse an ISO 8601 duration string (subset: hours/minutes/seconds).
    /// Accepts "PT<n>H<n>M<n>S" where each component is optional but at
    /// least one must be present. Also accepts plain integer strings.
    pub fn fromIso8601(input: []const u8) Error!Duration {
        if (input.len == 0) return error.InvalidDuration;

        // Try plain integer first
        if (std.fmt.parseInt(u64, input, 10)) |n| {
            return .{ .total_seconds = n };
        } else |_| {}

        // ISO 8601 duration: must start with "PT"
        if (input.len < 3 or input[0] != 'P' or input[1] != 'T') return error.InvalidDuration;

        var total: u64 = 0;
        var i: usize = 2;
        var found_component = false;
        while (i < input.len) {
            const start = i;
            while (i < input.len and input[i] >= '0' and input[i] <= '9') : (i += 1) {}
            if (i == start or i >= input.len) return error.InvalidDuration;
            const n = std.fmt.parseInt(u64, input[start..i], 10) catch return error.InvalidDuration;
            switch (input[i]) {
                'H' => {
                    total += n * 3600;
                    found_component = true;
                },
                'M' => {
                    total += n * 60;
                    found_component = true;
                },
                'S' => {
                    total += n;
                    found_component = true;
                },
                else => return error.InvalidDuration,
            }
            i += 1;
        }
        if (!found_component) return error.InvalidDuration;
        return .{ .total_seconds = total };
    }

    /// Custom JSON serialization — emits total_seconds as an integer.
    pub fn jsonStringify(v: @This(), jws: anytype) !void {
        try jws.write(v.total_seconds);
    }

    /// Custom JSON deserialization.
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
        switch (token) {
            .number, .allocated_number => |s| {
                const n = std.fmt.parseInt(u64, s, 10) catch return error.UnexpectedToken;
                return .{ .total_seconds = n };
            },
            .string, .allocated_string => |s| {
                return Duration.fromIso8601(s) catch return error.UnexpectedToken;
            },
            else => return error.UnexpectedToken,
        }
    }

    /// Custom JSON deserialization from a pre-parsed Value.
    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
        _ = allocator;
        _ = options;
        switch (source) {
            .integer => |n| {
                if (n < 0) return error.UnexpectedToken;
                return .{ .total_seconds = @intCast(n) };
            },
            .string => |s| return Duration.fromIso8601(s) catch return error.UnexpectedToken,
            else => return error.UnexpectedToken,
        }
    }
};

// ─── Tests ───────────────────────────────────────────────────────────

test "Uuid parse and round-trip" {
    const input = "550e8400-e29b-41d4-a716-446655440000";
    const uuid = try Uuid.parse(input);
    try std.testing.expectEqualStrings(input, uuid.toString());
}

test "Uuid rejects invalid input" {
    // Wrong length
    try std.testing.expectError(error.InvalidUuid, Uuid.parse("too-short"));
    // Missing dash
    try std.testing.expectError(error.InvalidUuid, Uuid.parse("550e8400xe29b-41d4-a716-446655440000"));
    // Non-hex character
    try std.testing.expectError(error.InvalidUuid, Uuid.parse("550e8400-e29b-41d4-a716-44665544000g"));
}

test "Uuid equality" {
    const a = try Uuid.parse("550e8400-e29b-41d4-a716-446655440000");
    const b = try Uuid.parse("550e8400-e29b-41d4-a716-446655440000");
    const c = try Uuid.parse("550e8400-e29b-41d4-a716-446655440001");
    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));
}

test "Uuid JSON serialization round-trip" {
    const input = "550e8400-e29b-41d4-a716-446655440000";
    const uuid = try Uuid.parse(input);

    var buf: [256]u8 = undefined;
    var w: std.json.Stringify.Writer = .fixed(&buf);
    try std.json.Stringify.value(uuid, .{}, &w);
    const json_out = w.buffered();
    try std.testing.expectEqualStrings("\"550e8400-e29b-41d4-a716-446655440000\"", json_out);
}

test "Uuid JSON deserialization" {
    const json_input = "\"550e8400-e29b-41d4-a716-446655440000\"";
    const parsed = try std.json.parseFromSlice(Uuid, std.testing.allocator, json_input, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("550e8400-e29b-41d4-a716-446655440000", parsed.value.toString());
}

test "DateTime epoch to ISO 8601" {
    // 2024-03-14T12:00:00Z
    const dt = DateTime.fromEpoch(1710417600);
    var buf: [32]u8 = undefined;
    const iso = dt.toIso8601(&buf);
    try std.testing.expectEqualStrings("2024-03-14T12:00:00Z", iso);
}

test "DateTime Unix epoch zero" {
    const dt = DateTime.fromEpoch(0);
    var buf: [32]u8 = undefined;
    const iso = dt.toIso8601(&buf);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", iso);
}

test "DateTime ISO 8601 round-trip" {
    const input = "2024-03-14T12:00:00Z";
    const dt = try DateTime.fromIso8601(input);
    var buf: [32]u8 = undefined;
    const output = dt.toIso8601(&buf);
    try std.testing.expectEqualStrings(input, output);
}

test "DateTime fromIso8601 rejects invalid input" {
    try std.testing.expectError(error.InvalidDateTime, DateTime.fromIso8601("not-a-date"));
    try std.testing.expectError(error.InvalidDateTime, DateTime.fromIso8601("2024-13-01T00:00:00Z")); // month > 12
    try std.testing.expectError(error.InvalidDateTime, DateTime.fromIso8601("2024-01-01T25:00:00Z")); // hour > 23
}

test "DateTime JSON serialization round-trip" {
    const dt = DateTime.fromEpoch(1710417600);

    var buf: [256]u8 = undefined;
    var w: std.json.Stringify.Writer = .fixed(&buf);
    try std.json.Stringify.value(dt, .{}, &w);
    const json_out = w.buffered();
    try std.testing.expectEqualStrings("\"2024-03-14T12:00:00Z\"", json_out);
}

test "DateTime JSON deserialization from string" {
    const json_input = "\"2024-03-14T12:00:00Z\"";
    const parsed = try std.json.parseFromSlice(DateTime, std.testing.allocator, json_input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 1710417600), parsed.value.epoch_seconds);
}

test "DateTime JSON deserialization from integer" {
    const json_input = "1710417600";
    const parsed = try std.json.parseFromSlice(DateTime, std.testing.allocator, json_input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 1710417600), parsed.value.epoch_seconds);
}

test "Duration construction" {
    try std.testing.expectEqual(@as(u64, 60), Duration.fromSeconds(60).seconds());
    try std.testing.expectEqual(@as(u64, 300), Duration.fromMinutes(5).seconds());
    try std.testing.expectEqual(@as(u64, 7200), Duration.fromHours(2).seconds());
}

test "Duration conversions" {
    const d = Duration.fromSeconds(7265);
    try std.testing.expectEqual(@as(u64, 7265), d.seconds());
    try std.testing.expectEqual(@as(u64, 121), d.toMinutes());
    try std.testing.expectEqual(@as(u64, 2), d.toHours());
}

test "Duration ISO 8601 parsing" {
    const d1 = try Duration.fromIso8601("PT1H30M");
    try std.testing.expectEqual(@as(u64, 5400), d1.total_seconds);

    const d2 = try Duration.fromIso8601("PT45S");
    try std.testing.expectEqual(@as(u64, 45), d2.total_seconds);

    const d3 = try Duration.fromIso8601("PT2H15M30S");
    try std.testing.expectEqual(@as(u64, 8130), d3.total_seconds);

    // Plain integer string
    const d4 = try Duration.fromIso8601("3600");
    try std.testing.expectEqual(@as(u64, 3600), d4.total_seconds);
}

test "Duration ISO 8601 format" {
    const d = Duration.fromSeconds(7265);
    var buf: [64]u8 = undefined;
    const formatted = d.format(&buf);
    try std.testing.expectEqualStrings("PT2H1M5S", formatted);
}

test "Duration fromIso8601 rejects invalid input" {
    try std.testing.expectError(error.InvalidDuration, Duration.fromIso8601(""));
    try std.testing.expectError(error.InvalidDuration, Duration.fromIso8601("PT"));
    try std.testing.expectError(error.InvalidDuration, Duration.fromIso8601("P1H"));
}

test "Duration JSON serialization round-trip" {
    const d = Duration.fromMinutes(5);

    var buf: [256]u8 = undefined;
    var w: std.json.Stringify.Writer = .fixed(&buf);
    try std.json.Stringify.value(d, .{}, &w);
    const json_out = w.buffered();
    try std.testing.expectEqualStrings("300", json_out);
}

test "Duration JSON deserialization from integer" {
    const json_input = "300";
    const parsed = try std.json.parseFromSlice(Duration, std.testing.allocator, json_input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u64, 300), parsed.value.total_seconds);
}

test "Duration JSON deserialization from string" {
    const json_input = "\"PT1H30M\"";
    const parsed = try std.json.parseFromSlice(Duration, std.testing.allocator, json_input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u64, 5400), parsed.value.total_seconds);
}
