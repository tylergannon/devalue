const std = @import("std");

test "backing integer conversions and splat" {
    const Status = enum(u8) { ok = 0, failed = 1 };
    const status: Status = .failed;
    const raw: u8 = @backingInt(status);
    const restored: Status = @fromBackingInt(raw);
    try std.testing.expectEqual(status, restored);
    try std.testing.expect(std.meta.BackingInt(Status) == u8);
    const bytes: [4]u8 = @splat(7);
    try std.testing.expectEqualSlices(u8, &.{ 7, 7, 7, 7 }, &bytes);
    try std.testing.expectEqual(@as(i32, -1), @divCeil(@as(i32, -5), 3));
}

test "public declaration reflection and SoA fields" {
    const Item = struct {
        x: i32,
        y: i32,
        pub const public_value = 1;
        const private_value = 2;
    };
    try std.testing.expect(@hasDecl(Item, "public_value"));
    try std.testing.expect(!@hasDecl(Item, "private_value"));
    const info = @typeInfo(Item).@"struct";
    try std.testing.expectEqual(@as(usize, 2), info.field_names.len);
    inline for (info.field_names, info.field_types, info.field_attrs) |name, field_type, attrs| {
        try std.testing.expect(name.len == 1);
        try std.testing.expect(field_type == i32);
        _ = attrs;
    }
    const Generated = @Struct(.auto, null, &.{ "x", "y" }, &.{ i32, i32 }, &@splat(.{}));
    const value: Generated = .{ .x = 3, .y = 4 };
    try std.testing.expectEqual(@as(i32, 7), value.x + value.y);
}

test "logical bit representation and unaligned memory representation" {
    const TwoBytes = extern struct { b0: u8, b1: u8 };
    const bytes: TwoBytes = .{ .b0 = 0x12, .b1 = 0xAB };
    const integer_pointer: *align(1) const u16 = @ptrCast(&bytes);
    const expected: u16 = if (@import("builtin").target.cpu.arch.endian() == .little) 0xAB12 else 0x12AB;
    try std.testing.expectEqual(expected, integer_pointer.*);
    const bits: u32 = @bitCast(@as(f32, 1.0));
    try std.testing.expectEqual(@as(u32, 0x3F800000), bits);
}

test "safe allocator reports no leaks" {
    var safe: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    defer std.testing.expectEqual(@as(usize, 0), safe.deinit()) catch @panic("allocator leak");
    const allocator = safe.allocator();
    const data = try allocator.alloc(u32, 16);
    defer allocator.free(data);
}

fn collectionsAndFormatting(allocator: std.mem.Allocator) !void {
    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(allocator);
    try list.append(allocator, 42);
    try std.testing.expectEqual(@as(u32, 42), list.last().?);
    list.lastPtr().?.* += 1;
    try std.testing.expectEqual(@as(u32, 43), list.last().?);

    const text = try allocator.print("{s}={d}", .{ "value", list.last().? });
    defer allocator.free(text);
    try std.testing.expectEqualStrings("value=43", text);
    const sentinel = try allocator.printSentinel("{s}", .{text}, 0);
    defer allocator.free(sentinel);
    try std.testing.expectEqual(@as(u8, 0), sentinel[sentinel.len]);
}

test "current collection and formatting APIs" {
    try collectionsAndFormatting(std.testing.allocator);
}

test "collection and formatting allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, collectionsAndFormatting, .{});
}

test "explicit buffer fallback and static bit set" {
    var buffer: [32]u8 = undefined;
    var first: std.heap.BufferFirstAllocator = .init(&buffer, std.testing.allocator);
    const allocator = first.allocator();
    const data = try allocator.alloc(u8, 128);
    defer allocator.free(data);
    var bits: std.bit_set.Integer(8) = .empty;
    bits.set(3);
    try std.testing.expect(bits.isSet(3));
    try std.testing.expect(std.lang.Optimize.safe.runtimeSafety());
    try std.testing.expect(!std.lang.Optimize.fast.runtimeSafety());
}
