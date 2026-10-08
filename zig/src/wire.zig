// A flat token tape, not a JSON value tree. Container tokens point to their
// matching close; devalue slot IDs map to start offsets. Strings borrow input
// where the scanner can, and are copied only when retained by the result graph.
const std = @import("std");
const d = @import("root.zig");
pub const Atom = struct { token: std.json.Token, end: usize = 0, children: usize = 0 };
pub const Tape = struct {
    atoms: []const Atom,
    pub fn next(self: Tape, i: usize) usize {
        return switch (self.atoms[i].token) {
            .array_begin, .object_begin => self.atoms[i].end + 1,
            else => i + 1,
        };
    }
    pub fn child(self: Tape, i: usize, n: usize) d.Error!usize {
        if (n >= self.atoms[i].children) return error.InvalidDocument;
        var pos = i + 1;
        for (0..n) |_| pos = self.next(pos);
        return pos;
    }
    pub fn string(self: Tape, i: usize) d.Error![]const u8 {
        return switch (self.atoms[i].token) {
            .string, .allocated_string => |s| s,
            else => error.InvalidDocument,
        };
    }
    pub fn number(self: Tape, i: usize) d.Error!f64 {
        const s = switch (self.atoms[i].token) {
            .number, .allocated_number => |s| s,
            else => return error.InvalidDocument,
        };
        return std.fmt.parseFloat(f64, s) catch error.InvalidDocument;
    }
    pub fn reference(self: Tape, i: usize) d.Error!i64 {
        const f = try self.number(i);
        if (!std.math.isFinite(f) or @trunc(f) != f or f < -7 or f >= 9223372036854775808.0) return error.InvalidDocument;
        return @intFromFloat(f);
    }
};
pub fn scan(a: std.mem.Allocator, bytes: []const u8) d.Error!Tape {
    var scanner = std.json.Scanner.initCompleteInput(a, bytes);
    defer scanner.deinit();
    var atoms: std.ArrayList(Atom) = .empty;
    var stack: std.ArrayList(usize) = .empty;
    while (true) {
        const token = scanner.nextAllocMax(a, .alloc_if_needed, bytes.len) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidDocument;
        if (token == .end_of_document) break;
        const i = atoms.items.len;
        switch (token) {
            .array_end, .object_end => {
                const open = stack.pop() orelse return error.InvalidDocument;
                atoms.items[open].end = i;
            },
            else => {
                if (stack.items.len > 0) atoms.items[stack.items[stack.items.len - 1]].children += 1;
            },
        }
        try atoms.append(a, .{ .token = token });
        if (token == .array_begin or token == .object_begin) {
            if (stack.items.len >= d.max_depth) return error.DepthLimit;
            try stack.append(a, i);
        }
    }
    if (atoms.items.len == 0 or stack.items.len != 0) return error.InvalidDocument;
    return .{ .atoms = atoms.items };
}
