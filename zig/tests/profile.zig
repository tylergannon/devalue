const std = @import("std");
const d = @import("devalue");
const t = @import("tests.zig");
const a = t.a;
const numbers = [_]f64{ 1e-6, 1e-7, 1e20, 1e21, std.math.floatTrueMin(f64), std.math.floatMax(f64), 9007199254740991, 9007199254740992, 1.0000000000000001e-7, 0.0000010000000000000002, 999999999999999900000.0, 1.0000000000000001e21, 9.999999999999997e-7, 9.999999999999998e-8, 99999999999999980000.0, 100000000000000020000.0 };
const controls = "\x00\x01\x08\x0c\n\r\t\"\\<\u{2028}\u{2029}雪😀";
fn reduceFoo(_: ?*anyopaque, g: *d.Graph, v: d.Value) d.Error!?d.Value {
    const n = if (v == .ref) try g.node(v) else return null;
    if (n != .object) return null;
    if (try g.get(v, "kind")) |kind| {
        if (!d.equal(kind, .{ .string = "foo" })) return null;
    }
    return g.get(v, "value");
}
fn reduceBar(_: ?*anyopaque, g: *d.Graph, v: d.Value) d.Error!?d.Value {
    if (v != .ref or try g.node(v) != .object) return null;
    if (try g.get(v, "kind")) |kind| {
        if (d.equal(kind, .{ .string = "bar" })) return g.get(v, "value");
    }
    return null;
}
fn reduceAnswer(_: ?*anyopaque, _: *d.Graph, v: d.Value) d.Error!?d.Value {
    return if (d.equal(v, .{ .number = 42 })) .{ .string = "forty-two" } else null;
}
const custom = [_]d.Reducer{ .{ .name = "Foo", .reduce = reduceFoo }, .{ .name = "Bar", .reduce = reduceBar } };
fn construct(g: *d.Graph, name: []const u8) !d.Value {
    if (std.mem.eql(u8, name, "distinct_empty")) {
        const v = try g.array(4);
        try g.arrayPut(v, 0, try g.array(0));
        try g.arrayPut(v, 1, try g.array(0));
        try g.arrayPut(v, 2, try g.arrayBuffer(""));
        try g.arrayPut(v, 3, try g.arrayBuffer(""));
        return v;
    }
    if (std.mem.eql(u8, name, "date_identities") or std.mem.eql(u8, name, "regexp_identities")) {
        const date = name[0] == 'd';
        const v = try g.array(3);
        const shared = if (date) try g.date(0) else try g.regexp("x", "");
        try g.arrayPut(v, 0, shared);
        try g.arrayPut(v, 1, shared);
        try g.arrayPut(v, 2, if (date) try g.date(0) else try g.regexp("x", ""));
        return v;
    }
    if (std.mem.eql(u8, name, "date_min")) return g.date(-8640000000000000);
    if (std.mem.eql(u8, name, "date_max")) return g.date(8640000000000000);
    if (std.mem.eql(u8, name, "date_year_zero")) return g.date(-62167219200000);
    if (std.mem.eql(u8, name, "date_year_negative")) return g.date(-62198755200000);
    if (std.mem.eql(u8, name, "date_year_expanded")) return g.date(253402300800000);
    if (std.mem.eql(u8, name, "sparse_max")) {
        const v = try g.array(std.math.maxInt(u32));
        try g.arrayPut(v, 0, .undefined);
        try g.arrayPut(v, 42, try g.string("x"));
        try g.arrayPut(v, 4294967294, .null);
        return v;
    }
    if (std.mem.eql(u8, name, "unicode_controls")) return g.string(controls);
    if (std.mem.eql(u8, name, "key_boundaries")) {
        const v = try g.object(false);
        for ([_][]const u8{ "z", "01", "4294967294", "4294967295", "-1", "1.0", "2", "0", "😀" }, 0..) |key, i| try g.put(v, key, .{ .number = @floatFromInt(i + 1) });
        return v;
    }
    if (std.mem.startsWith(u8, name, "number_")) return .{ .number = numbers[try std.fmt.parseInt(usize, name[7..], 10)] };
    if (std.mem.startsWith(u8, name, "sparse_boundary_")) {
        const v = try g.array(try std.fmt.parseInt(u32, name[16..], 10));
        try g.arrayPut(v, 0, try g.string("x"));
        return v;
    }
    if (std.mem.eql(u8, name, "custom_primitive") or std.mem.eql(u8, name, "custom_name")) return .{ .number = 42 };
    if (std.mem.startsWith(u8, name, "custom_")) {
        const foo = try g.object(false);
        const payload = try g.object(false);
        try g.put(foo, "value", payload);
        if (std.mem.eql(u8, name, "custom_self")) {
            try g.put(payload, "name", try g.string("self"));
            try g.put(payload, "ref", foo);
        } else {
            try g.put(foo, "kind", try g.string("foo"));
            const bar = try g.object(false);
            const inner = try g.object(false);
            try g.put(bar, "kind", try g.string("bar"));
            try g.put(bar, "value", inner);
            try g.put(payload, "name", try g.string("outer"));
            try g.put(payload, "ref", bar);
            try g.put(inner, "name", try g.string("inner"));
            try g.put(inner, "ref", foo);
        }
        return foo;
    }
    return error.UnimplementedCase;
}
test "all Zig-only upstream bytes from independent native construction and version pins" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "testdata/flat-golden.json", a, .limited(1024 * 1024));
    defer a.free(bytes);
    const Case = struct { name: []const u8, devalue: []const u8 };
    const Corpus = struct { devalue: []const u8, cases: []Case };
    const f = try std.json.parseFromSlice(Corpus, a, bytes, .{});
    defer f.deinit();
    try std.testing.expectEqualStrings(d.upstream_version, f.value.devalue);
    try std.testing.expectEqual(@as(usize, 35), f.value.cases.len);
    const pkg_bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../v5/package.json", a, .limited(8192));
    defer a.free(pkg_bytes);
    const pkg = try std.json.parseFromSlice(std.json.Value, a, pkg_bytes, .{});
    defer pkg.deinit();
    try std.testing.expectEqualStrings(d.upstream_version, pkg.value.object.get("devDependencies").?.object.get("devalue").?.string);
    try std.testing.expectEqualStrings("0.17.0", @import("builtin").zig_version_string);
    for (f.value.cases) |case| {
        var g = d.Graph.init(a);
        defer g.deinit();
        const v = try construct(&g, case.name);
        const reducers: []const d.Reducer = if (std.mem.eql(u8, case.name, "custom_name")) &.{.{ .name = "Name<\u{2028}", .reduce = reduceAnswer }} else if (std.mem.eql(u8, case.name, "custom_primitive")) &.{.{ .name = "Answer", .reduce = reduceAnswer }} else if (std.mem.startsWith(u8, case.name, "custom_")) &custom else &.{};
        const wire = try d.stringify(a, &g, v, reducers);
        defer a.free(wire);
        if (!std.mem.eql(u8, case.devalue, wire)) std.debug.print("native case {s}\n", .{case.name});
        try std.testing.expectEqualStrings(case.devalue, wire);
        if (!std.mem.startsWith(u8, case.name, "custom_")) {
            var decoded = try d.parse(a, case.devalue, &.{});
            defer decoded.deinit();
            // Explicit contents, independent of encode.
            if (std.mem.startsWith(u8, case.name, "number_")) try std.testing.expectEqual(v.number, decoded.value.number);
            if (std.mem.startsWith(u8, case.name, "date_") and !std.mem.eql(u8, case.name, "date_identities")) try std.testing.expectEqual((try g.node(v)).date, (try decoded.graph.node(decoded.value)).date);
            if (std.mem.eql(u8, case.name, "unicode_controls")) try std.testing.expectEqualStrings(controls, decoded.value.string);
            if (std.mem.eql(u8, case.name, "sparse_max")) {
                const node = try decoded.graph.node(decoded.value);
                try std.testing.expectEqual(@as(u32, 4294967295), node.array.length);
                try std.testing.expectEqual(@as(usize, 3), node.array.elements.items.len);
                try std.testing.expect((try decoded.graph.arrayGet(decoded.value, 0)).? == .undefined);
                try std.testing.expect((try decoded.graph.arrayGet(decoded.value, 1)) == null);
                try std.testing.expectEqualStrings("x", (try decoded.graph.arrayGet(decoded.value, 42)).?.string);
                try std.testing.expect((try decoded.graph.arrayGet(decoded.value, 4294967294)).? == .null);
            }
            if (std.mem.endsWith(u8, case.name, "identities")) {
                const x = (try decoded.graph.arrayGet(decoded.value, 0)).?;
                const y = (try decoded.graph.arrayGet(decoded.value, 1)).?;
                const z = (try decoded.graph.arrayGet(decoded.value, 2)).?;
                try std.testing.expect(d.equal(x, y));
                try std.testing.expect(!d.equal(x, z));
            }
            if (std.mem.eql(u8, case.name, "distinct_empty")) {
                for (0..4) |i| for (i + 1..4) |j| try std.testing.expect(!d.equal((try decoded.graph.arrayGet(decoded.value, @intCast(i))).?, (try decoded.graph.arrayGet(decoded.value, @intCast(j))).?));
            }
        }
    }
}
const Memo = struct {
    payloads: [4]?d.Value = @splat(null),
    results: [4]?d.Value = @splat(null),
    count: usize = 0,
    calls: usize = 0,
    partial: bool = false,
    full: bool = false,
    fn revive(ctx: ?*anyopaque, g: *d.Graph, payload: d.Value) d.Error!d.Value {
        const self: *Memo = @ptrCast(@alignCast(ctx.?));
        self.calls += 1;
        if (try g.get(payload, "ref") == null) self.partial = true else self.full = true;
        for (self.payloads[0..self.count], self.results[0..self.count]) |p, r| if (d.equal(p.?, payload)) return r.?;
        const result = try g.object(false);
        try g.put(result, "value", payload);
        self.payloads[self.count] = payload;
        self.results[self.count] = result;
        self.count += 1;
        return result;
    }
};
// Ported from v5.9.4/test/index.test.js circularCustomTypes (lines 2051-2120).
test "upstream self and mutual custom cycles including partial reviver views" {
    for ([_]bool{ false, true }) |mutual| {
        var foo: Memo = .{};
        var bar: Memo = .{};
        const revivers = [_]d.Reviver{ .{ .name = "Foo", .context = &foo, .revive = Memo.revive }, .{ .name = "Bar", .context = &bar, .revive = Memo.revive } };
        const wire = if (mutual) "[[\"Foo\",1],{\"name\":2,\"ref\":3},\"outer\",[\"Bar\",4],{\"name\":5,\"ref\":0},\"inner\"]" else "[[\"Foo\",1],{\"name\":2,\"ref\":0},\"self\"]";
        var r = try d.parse(a, wire, &revivers);
        defer r.deinit();
        const payload = (try r.graph.get(r.value, "value")).?;
        const back = (try r.graph.get(payload, "ref")).?;
        if (mutual) {
            const inner = (try r.graph.get(back, "value")).?;
            try std.testing.expect(d.equal(r.value, (try r.graph.get(inner, "ref")).?));
            try std.testing.expectEqual(@as(usize, 1), bar.calls);
        } else try std.testing.expect(d.equal(r.value, back));
        try std.testing.expectEqual(@as(usize, 2), foo.calls);
        try std.testing.expect(foo.partial and foo.full);
    }
    var memo: Memo = .{};
    try std.testing.expectError(error.InvalidDocument, d.parse(a, "[[\"Foo\",0]]", &.{.{ .name = "Foo", .context = &memo, .revive = Memo.revive }}));
}
test "built-in values encode independently and decode contents" {
    var g = d.Graph.init(a);
    defer g.deinit();
    const root = try g.array(8);
    const obj = try g.object(true);
    try g.put(obj, "x", .{ .number = 1 });
    const map = try g.map();
    try g.mapPut(map, .{ .string = "k" }, obj);
    try g.mapPut(map, map, map);
    const set = try g.set();
    try g.setAdd(set, .{ .number = -0.0 });
    try g.setAdd(set, .{ .number = 0 });
    try g.setAdd(set, .{ .number = std.math.nan(f64) });
    try g.setAdd(set, .{ .number = std.math.nan(f64) });
    try g.setAdd(set, set);
    const values = [_]d.Value{ try g.bigint("-123456789012345678901"), try g.date(-1), try g.regexp("a\\/b\\n", "ym"), try g.arrayBuffer(&.{ 0, 255 }), try g.boxed(.{ .boolean = false }), obj, map, set };
    for (values, 0..) |v, i| try g.arrayPut(root, @intCast(i), v);
    const wire = "[[1,2,3,4,5,7,9,11],[\"BigInt\",\"-123456789012345678901\"],[\"Date\",\"1969-12-31T23:59:59.999Z\"],[\"RegExp\",\"a\\\\/b\\\\n\",\"my\"],[\"ArrayBuffer\",\"AP8=\"],[\"Object\",6],false,[\"null\",\"x\",8],1,[\"Map\",10,7,9,9],\"k\",[\"Set\",12,-3,11],0]";
    try t.encoded(&g, root, wire);
    var r = try d.parse(a, wire, &.{});
    defer r.deinit();
    try std.testing.expectEqualStrings("-123456789012345678901", (try r.graph.arrayGet(r.value, 0)).?.bigint);
    try std.testing.expectEqual(@as(i64, -1), (try r.graph.node((try r.graph.arrayGet(r.value, 1)).?)).date);
    const re = (try r.graph.node((try r.graph.arrayGet(r.value, 2)).?)).regexp;
    try std.testing.expectEqualStrings("a\\/b\\n", re.source);
    try std.testing.expectEqualStrings("my", re.flags);
    try std.testing.expectEqualSlices(u8, &.{ 0, 255 }, (try r.graph.node((try r.graph.arrayGet(r.value, 3)).?)).array_buffer);
    try std.testing.expect(!(try r.graph.node((try r.graph.arrayGet(r.value, 4)).?)).boxed.boolean);
    const nullobj = (try r.graph.arrayGet(r.value, 5)).?;
    try std.testing.expect((try r.graph.node(nullobj)).object.null_proto);
    const rm = (try r.graph.arrayGet(r.value, 6)).?;
    const entries = (try r.graph.node(rm)).map.entries.items;
    try std.testing.expect(d.equal(entries[0].value, nullobj));
    try std.testing.expect(d.equal(entries[1].key, rm) and d.equal(entries[1].value, rm));
    const rs = (try r.graph.arrayGet(r.value, 7)).?;
    const items = (try r.graph.node(rs)).set.values.items;
    try std.testing.expectEqual(@as(usize, 3), items.len);
    try std.testing.expect(!std.math.signbit(items[0].number));
    try std.testing.expect(std.math.isNan(items[1].number));
    try std.testing.expect(d.equal(rs, items[2]));
}
test "boxed primitives and canonical BigInt zero encode independently" {
    var g = d.Graph.init(a);
    defer g.deinit();
    const arr = try g.array(4);
    try g.arrayPut(arr, 0, try g.boxed(.{ .number = 42 }));
    try g.arrayPut(arr, 1, try g.boxed(try g.string("hi")));
    try g.arrayPut(arr, 2, try g.boxed(try g.bigint("0")));
    try g.arrayPut(arr, 3, try g.boxed(.{ .number = -0.0 }));
    try t.encoded(&g, arr, "[[1,3,5,7],[\"Object\",2],42,[\"Object\",4],\"hi\",[\"Object\",6],[\"BigInt\",\"0\"],[\"Object\",-6]]");
}
