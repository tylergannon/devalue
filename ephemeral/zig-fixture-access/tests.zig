const std = @import("std");

test "runtime corpus lookup from a separate package build root" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, @import("fixtures").golden_path, std.testing.allocator, .limited(16 * 1024 * 1024));
    defer std.testing.allocator.free(bytes);
    const Corpus = struct { devalue: []const u8, cases: []std.json.Value };
    const corpus = try std.json.parseFromSlice(Corpus, std.testing.allocator, bytes, .{});
    defer corpus.deinit();
    try std.testing.expectEqualStrings("5.9.4", corpus.value.devalue);
    try std.testing.expectEqual(@as(usize, 359), corpus.value.cases.len);
}

test "invalid UTF-8 and unpaired surrogate escapes are syntax errors" {
    for ([_][]const u8{ "\"\xed\xa0\x80\"", "\"\\uD800\"", "\"\\uDC00\"", "\"a\\uD800b\"" }) |input| {
        try std.testing.expectError(error.SyntaxError, std.json.parseFromSlice([]const u8, std.testing.allocator, input, .{}));
    }
    const paired = try std.json.parseFromSlice([]const u8, std.testing.allocator, "\"\\uD83D\\uDE00\"", .{});
    defer paired.deinit();
    try std.testing.expectEqualStrings("😀", paired.value);
}
