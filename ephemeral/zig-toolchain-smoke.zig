const std = @import("std");

fn allocateAndParse(gpa: std.mem.Allocator) !void {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(gpa);
    try list.appendSlice(gpa, "[1,2,3]");

    const parsed = try std.json.parseFromSlice([]u8, gpa, list.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, parsed.value);
}

test "pinned compiler allocator, container, and JSON APIs" {
    try allocateAndParse(std.testing.allocator);
}

test "allocation failures release partial results" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocateAndParse, .{});
}
