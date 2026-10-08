const std = @import("std");
const d = @import("devalue");
pub const a = std.testing.allocator;
pub fn encoded(graph: *d.Graph, value: d.Value, expected: []const u8) !void {
    const bytes = try d.stringify(a, graph, value, &.{});
    defer a.free(bytes);
    try std.testing.expectEqualStrings(expected, bytes);
}
test "native encoder and decoder contents and identity independently" {
    var g = d.Graph.init(a);
    defer g.deinit();
    const root = try g.object(false);
    const child = try g.array(2);
    try g.arrayPut(child, 0, try g.string("<hi>\n😀"));
    try g.arrayPut(child, 1, .undefined);
    try g.put(root, "first", child);
    try g.put(root, "alias", child);
    try g.put(root, "self", root);
    const wire = "[{\"first\":1,\"alias\":1,\"self\":0},[2,-1],\"\\u003Chi>\\n😀\"]";
    try encoded(&g, root, wire);
    var parsed = try d.parse(a, wire, &.{});
    defer parsed.deinit();
    const p = &parsed.graph;
    const first = (try p.get(parsed.value, "first")).?;
    try std.testing.expect(d.equal(first, (try p.get(parsed.value, "alias")).?));
    try std.testing.expect(d.equal(parsed.value, (try p.get(parsed.value, "self")).?));
    try std.testing.expectEqualStrings("<hi>\n😀", (try p.arrayGet(first, 0)).?.string);
    try std.testing.expect((try p.arrayGet(first, 1)).? == .undefined);
    try p.arrayPut(first, 0, .{ .boolean = true });
    try std.testing.expect((try p.arrayGet((try p.get(parsed.value, "alias")).?, 0)).?.boolean);
}
test "all shared pinned upstream corpus cases" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, @import("fixtures").golden_path, a, .limited(16 * 1024 * 1024));
    defer a.free(bytes);
    const Case = struct { name: []const u8, devalue: []const u8, uneval: []const u8 };
    const Corpus = struct { devalue: []const u8, cases: []Case };
    const fixture = try std.json.parseFromSlice(Corpus, a, bytes, .{});
    defer fixture.deinit();
    try std.testing.expectEqualStrings(d.upstream_version, fixture.value.devalue);
    try std.testing.expectEqual(@as(usize, 368), fixture.value.cases.len);
    for (fixture.value.cases) |case| {
        var result = d.parse(a, case.devalue, &.{}) catch |err| {
            std.debug.print("case {s}: {s}\n", .{ case.name, @errorName(err) });
            return err;
        };
        defer result.deinit();
        const output = try d.stringify(a, &result.graph, result.value, &.{});
        defer a.free(output);
        if (!std.mem.eql(u8, case.devalue, output)) {
            std.debug.print("case {s}\n", .{case.name});
            try std.testing.expectEqualStrings(case.devalue, output);
        }
    }
}

comptime {
    _ = @import("profile.zig");
    _ = @import("robustness.zig");
    _ = @import("upstream.zig");
}
