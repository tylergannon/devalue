const std = @import("std");
const Error = @import("root.zig").Error;
pub const Buffer = std.ArrayList(u8);
pub fn text(b: *Buffer, a: std.mem.Allocator, s: []const u8) Error!void {
    try b.appendSlice(a, s);
}
pub fn integer(b: *Buffer, a: std.mem.Allocator, n: anytype) Error!void {
    var buf: [32]u8 = undefined;
    try text(b, a, std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable);
}
pub fn quote(b: *Buffer, a: std.mem.Allocator, s: []const u8) Error!void {
    if (!std.unicode.utf8ValidateSlice(s)) return error.UnsupportedString;
    try b.append(a, '"');
    var i: usize = 0;
    var start: usize = 0;
    while (i < s.len) : (i += 1) {
        var replacement: ?[]const u8 = switch (s[i]) {
            '"' => "\\\"",
            '\\' => "\\\\",
            '<' => "\\u003C",
            '\n' => "\\n",
            '\r' => "\\r",
            '\t' => "\\t",
            8 => "\\b",
            12 => "\\f",
            else => null,
        };
        var hex: [6]u8 = undefined;
        var width: usize = 1;
        if (replacement == null and s[i] < 32) {
            replacement = std.fmt.bufPrint(&hex, "\\u00{x:0>2}", .{s[i]}) catch unreachable;
        } else if (std.mem.startsWith(u8, s[i..], "\xe2\x80\xa8")) {
            replacement = "\\u2028";
            width = 3;
        } else if (std.mem.startsWith(u8, s[i..], "\xe2\x80\xa9")) {
            replacement = "\\u2029";
            width = 3;
        }
        if (replacement) |r| {
            try text(b, a, s[start..i]);
            try text(b, a, r);
            i += width - 1;
            start = i + 1;
        }
    }
    try text(b, a, s[start..]);
    try b.append(a, '"');
}
// Zig's shortest-roundtrip Ryu digits, with ECMAScript Number::toString layout.
pub fn number(b: *Buffer, a: std.mem.Allocator, f: f64) Error!void {
    if (!std.math.isFinite(f)) return error.UnsupportedValue;
    if (f == 0) return text(b, a, "0");
    if (f < 0) try b.append(a, '-');
    var buf: [64]u8 = undefined;
    const scientific = std.fmt.float.render(&buf, @abs(f), .{ .mode = .scientific }) catch unreachable;
    const e = std.mem.indexOfScalar(u8, scientific, 'e').?;
    const exp = std.fmt.parseInt(i32, scientific[e + 1 ..], 10) catch unreachable;
    var digits_buf: [32]u8 = undefined;
    var k: usize = 0;
    for (scientific[0..e]) |c| if (c != '.') {
        digits_buf[k] = c;
        k += 1;
    };
    const digits = digits_buf[0..k];
    const n = exp + 1;
    if (n > 0 and n <= 21) {
        const pos: usize = @intCast(n);
        if (k <= pos) {
            try text(b, a, digits);
            try b.appendNTimes(a, '0', pos - k);
        } else {
            try text(b, a, digits[0..pos]);
            try b.append(a, '.');
            try text(b, a, digits[pos..]);
        }
    } else if (n > -6 and n <= 0) {
        try text(b, a, "0.");
        try b.appendNTimes(a, '0', @intCast(-n));
        try text(b, a, digits);
    } else {
        try b.append(a, digits[0]);
        if (k > 1) {
            try b.append(a, '.');
            try text(b, a, digits[1..]);
        }
        try text(b, a, if (exp >= 0) "e+" else "e-");
        try integer(b, a, @abs(exp));
    }
}
// Proleptic Gregorian civil conversion (Howard Hinnant's civil algorithms).
fn civilFromDays(days: i64) struct { year: i64, month: i64, day: i64 } {
    const z = days + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divTrunc(doe - @divTrunc(doe, 1460) + @divTrunc(doe, 36524) - @divTrunc(doe, 146096), 365);
    var year = yoe + era * 400;
    const doy = doe - (365 * yoe + @divTrunc(yoe, 4) - @divTrunc(yoe, 100));
    const mp = @divTrunc(5 * doy + 2, 153);
    const day = doy - @divTrunc(153 * mp + 2, 5) + 1;
    const month = mp + @as(i64, if (mp < 10) 3 else -9);
    year += @as(i64, if (month <= 2) 1 else 0);
    return .{ .year = year, .month = month, .day = day };
}
fn daysFromCivil(y: i64, m: i64, d: i64) i64 {
    const year = y - @as(i64, if (m <= 2) 1 else 0);
    const era = @divFloor(year, 400);
    const yoe = year - era * 400;
    const mp = m + @as(i64, if (m > 2) -3 else 9);
    const doy = @divTrunc(153 * mp + 2, 5) + d - 1;
    return era * 146097 + yoe * 365 + @divTrunc(yoe, 4) - @divTrunc(yoe, 100) + doy - 719468;
}
pub fn dateString(out: *[27]u8, millis: i64) []const u8 {
    const date = civilFromDays(@divFloor(millis, 86400000));
    const time = @mod(millis, 86400000);
    const hour = @divTrunc(time, 3600000);
    const minute = @mod(@divTrunc(time, 60000), 60);
    const second = @mod(@divTrunc(time, 1000), 60);
    const ms = @mod(time, 1000);
    if (date.year >= 0 and date.year <= 9999) return std.fmt.bufPrint(out, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{ @abs(date.year), @abs(date.month), @abs(date.day), @abs(hour), @abs(minute), @abs(second), @abs(ms) }) catch unreachable;
    return std.fmt.bufPrint(out, "{s}{d:0>6}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{ if (date.year < 0) "-" else "+", @abs(date.year), @abs(date.month), @abs(date.day), @abs(hour), @abs(minute), @abs(second), @abs(ms) }) catch unreachable;
}
fn decimal(s: []const u8) Error!i64 {
    for (s) |c| if (c < '0' or c > '9') return error.InvalidDocument;
    return std.fmt.parseInt(i64, s, 10) catch error.InvalidDocument;
}
pub fn parseDate(s: []const u8) Error!i64 {
    const expanded = s.len == 27;
    if (s.len != 24 and !expanded) return error.InvalidDocument;
    const off: usize = if (expanded) 3 else 0;
    var y = try decimal(s[if (expanded) @as(usize, 1) else 0 .. 4 + off]);
    if (expanded) {
        if (s[0] == '-') y = -y else if (s[0] != '+') return error.InvalidDocument;
    }
    if (s[4 + off] != '-' or s[7 + off] != '-' or s[10 + off] != 'T' or s[13 + off] != ':' or s[16 + off] != ':' or s[19 + off] != '.' or s[23 + off] != 'Z') return error.InvalidDocument;
    const m = try decimal(s[5 + off .. 7 + off]);
    const d = try decimal(s[8 + off .. 10 + off]);
    const h = try decimal(s[11 + off .. 13 + off]);
    const minute = try decimal(s[14 + off .. 16 + off]);
    const sec = try decimal(s[17 + off .. 19 + off]);
    const ms = try decimal(s[20 + off .. 23 + off]);
    if (m < 1 or m > 12 or d < 1 or d > 31 or h > 23 or minute > 59 or sec > 59) return error.InvalidDocument;
    const millis = daysFromCivil(y, m, d) * 86400000 + h * 3600000 + minute * 60000 + sec * 1000 + ms;
    if (millis < -8640000000000000 or millis > 8640000000000000) return error.InvalidDocument;
    var out: [27]u8 = undefined;
    if (!std.mem.eql(u8, s, dateString(&out, millis))) return error.InvalidDocument;
    return millis;
}
