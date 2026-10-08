const std = @import("std");
const d = @import("devalue");
const t = @import("tests.zig");
const a = t.a;
// Failure injection needs repeatable backing-allocation counts. Successful
// in-place growth in SafeAllocator can depend on previously freed addresses.
// Refuse resize/remap here so every arena growth takes the allocation path;
// ordinary tests still exercise the normal allocator's growth behavior.
const no_growth = std.mem.Allocator{ .ptr = a.ptr, .vtable = &.{
    .alloc = a.vtable.alloc,
    .resize = std.mem.Allocator.noResize,
    .remap = std.mem.Allocator.noRemap,
    .free = a.vtable.free,
} };
test "sentinels independently encoded and decoded, holes distinct from undefined" {
    const values = [_]d.Value{ .undefined, .{ .number = std.math.nan(f64) }, .{ .number = std.math.inf(f64) }, .{ .number = -std.math.inf(f64) }, .{ .number = -0.0 } };
    for (values, [_][]const u8{ "-1", "-3", "-4", "-5", "-6" }) |v, wire| {
        var g = d.Graph.init(a);
        defer g.deinit();
        try t.encoded(&g, v, wire);
        var r = try d.parse(a, wire, &.{});
        defer r.deinit();
        try std.testing.expect(d.equal(v, r.value));
        if (v == .number and v.number == 0) try std.testing.expect(std.math.signbit(r.value.number));
    }
    var r = try d.parse(a, "[[-2,-1,-6]]", &.{});
    defer r.deinit();
    try std.testing.expect(try r.graph.arrayGet(r.value, 0) == null);
    try std.testing.expect((try r.graph.arrayGet(r.value, 1)).? == .undefined);
    try std.testing.expect(std.math.signbit((try r.graph.arrayGet(r.value, 2)).?.number));
}
test "malformed input and explicit profile rejection" {
    for ([_][]const u8{ "", "null", "{}", "[]", "0", "-2", "-7", "[[1.5]]", "[[2]]", "[[-8]]", "[[\"Map\",0]]", "[[\"null\",1,0]]", "[{\"__proto__\":0}]", "[[\"null\",\"__proto__\",0]]", "[[\"Date\",\"2023-02-29T00:00:00.000Z\"]]", "[[\"Date\",\"2000-01-01\"]]", "[[\"Date\",\"+000000-01-01T00:00:00.000Z\"]]", "[[\"BigInt\",\"01\"]]", "[[\"BigInt\",\"0x10\"]]", "[[\"BigInt\",\"-0\"]]", "[[\"BigInt\",\"\"]]", "[[\"RegExp\",\"x\",\"gg\"]]", "[[\"RegExp\",\"x\",\"uv\"]]", "[[\"ArrayBuffer\",\"AP9=\"]]", "[[\"ArrayBuffer\",\"a\"]]", "[[\"ArrayBuffer\",5]]", "[[\"Object\",0]]", "[[\"Object\",1],{}]", "[[-7,-1]]", "[[-7,4294967296]]", "[[-7,4,4,0]]", "[[-7,4,0]]", "[[-7,4,0.5,0]]", "[[\"Unknown\",0]]", "[\"\\uD800\"]", "[\"a\\uDC00b\"]", "[\"\xed\xa0\x80\"]" }) |wire| {
        if (d.parse(a, wire, &.{})) |parsed| {
            var r = parsed;
            r.deinit();
            std.debug.print("accepted {s}\n", .{wire});
            return error.ExpectedRejection;
        } else |err| try std.testing.expect(err == error.InvalidDocument);
    }
    for ([_][]const u8{ "[[\"URL\",\"https://x\"]]", "[[\"Uint8Array\",1],[\"ArrayBuffer\",\"\"]]", "[[\"Temporal.Instant\",\"x\"]]" }) |wire| try std.testing.expectError(error.UnsupportedValue, d.parse(a, wire, &.{}));
    var r = try d.parse(a, "[\"\\uD83D\\uDE00\"]", &.{});
    defer r.deinit();
    try std.testing.expectEqualStrings("😀", r.value.string);
}
test "graph handles growth, update/delete/reinsert ordering, borrowed input lifetime" {
    var g = d.Graph.init(a);
    defer g.deinit();
    const obj = try g.object(false);
    try g.put(obj, "a", .null);
    try g.put(obj, "b", .undefined);
    try g.put(obj, "a", .{ .boolean = true });
    _ = try g.remove(obj, "a");
    try g.put(obj, "a", .null);
    try g.put(obj, "2", .null);
    try g.put(obj, "0", .null);
    for (0..2000) |_| _ = try g.object(false);
    try t.encoded(&g, obj, "[{\"0\":1,\"2\":1,\"b\":-1,\"a\":1},null]");
    try std.testing.expectError(error.InvalidHandle, g.node(.{ .ref = @fromBackingInt(@intCast(999999)) }));
    try std.testing.expectError(error.UnsupportedString, g.string("\xff"));
    try std.testing.expectError(error.UnsupportedString, d.stringify(a, &g, .{ .string = "\xff" }, &.{}));
    try std.testing.expectError(error.UnsupportedValue, g.bigint(" 1"));
    const input = try a.dupe(u8, "[{\"hello\":1},\"owned\"]");
    var r = try d.parse(a, input, &.{});
    @memset(input, 'x');
    a.free(input);
    defer r.deinit();
    try std.testing.expectEqualStrings("owned", (try r.graph.get(r.value, "hello")).?.string);
}
fn allocated(gpa: std.mem.Allocator) !void {
    var g = d.Graph.init(gpa);
    defer g.deinit();
    const root = try g.object(false);
    const arr = try g.array(1000000);
    try g.arrayPut(arr, 10, root);
    try g.arrayPut(arr, 999999, try g.string("owned\n😀"));
    try g.put(root, "array", arr);
    const set = try g.set();
    try g.setAdd(set, root);
    try g.put(root, "set", set);
    const bytes = try d.stringify(gpa, &g, root, &.{});
    defer gpa.free(bytes);
    var r = try d.parse(gpa, bytes, &.{});
    defer r.deinit();
    const builtins = "[[1,2,3,4,5,6],[\"Date\",\"0000-01-01T00:00:00.000Z\"],[\"RegExp\",\"x\",\"g\"],[\"ArrayBuffer\",\"AP8=\"],[\"BigInt\",\"123\"],[\"Object\",7],[\"Map\",7,0],true]";
    var b = try d.parse(gpa, builtins, &.{});
    defer b.deinit();
    const out = try d.stringify(gpa, &b.graph, b.value, &.{});
    defer gpa.free(out);
}
test "all allocation failures through construction, stringify and parse" {
    try std.testing.checkAllAllocationFailures(no_growth, allocated, .{});
}
test "deep graphs and JSON nesting fail with a bounded resource error" {
    var g = d.Graph.init(a);
    defer g.deinit();
    const root = try g.object(false);
    var child = root;
    for (0..300) |_| {
        const next = try g.object(false);
        try g.put(child, "next", next);
        child = next;
    }
    try std.testing.expectError(error.DepthLimit, d.stringify(a, &g, root, &.{}));
    var wire: std.ArrayList(u8) = .empty;
    defer wire.deinit(a);
    try wire.appendSlice(a, "[");
    for (0..300) |i| {
        const part = try a.print("{{\"next\":{d}}},", .{i + 1});
        defer a.free(part);
        try wire.appendSlice(a, part);
    }
    try wire.appendSlice(a, "{}]");
    try std.testing.expectError(error.DepthLimit, d.parse(a, wire.items, &.{}));
    wire.clearRetainingCapacity();
    try wire.appendNTimes(a, '[', 300);
    try wire.appendNTimes(a, ']', 300);
    try std.testing.expectError(error.DepthLimit, d.parse(a, wire.items, &.{}));
}
test "deterministic input mutations clean up without crashes" {
    const seed = "[{\"a\":1,\"cycle\":0},[-7,1000000,42,2],\"hello\"]";
    var buf: [seed.len]u8 = undefined;
    for (0..seed.len) |i| for ([_]u8{ 0, '0', '[', ']', '"', 255 }) |byte| {
        @memcpy(&buf, seed);
        buf[i] = byte;
        if (d.parse(a, &buf, &.{})) |parsed| {
            var r = parsed;
            defer r.deinit();
            const out = try d.stringify(a, &r.graph, r.value, &.{});
            defer a.free(out);
            var second = try d.parse(a, out, &.{});
            defer second.deinit();
        } else |err| try std.testing.expect(err != error.OutOfMemory);
    };
}
const ReducerState = struct {
    calls: usize = 0,
    matches: usize = 0,
    replacement: ?d.Value = null,
    fail: bool = false,
    fn reduce(ctx: ?*anyopaque, _: *d.Graph, _: d.Value) d.Error!?d.Value {
        const self: *ReducerState = @ptrCast(@alignCast(ctx.?));
        self.calls += 1;
        if (self.fail) return error.CallbackError;
        if (self.replacement) |v| {
            self.matches += 1;
            return v;
        }
        return null;
    }
};
fn passthrough(_: ?*anyopaque, _: *d.Graph, payload: d.Value) d.Error!d.Value {
    return payload;
}
fn callbackFail(_: ?*anyopaque, _: *d.Graph, _: d.Value) d.Error!d.Value {
    return error.CallbackError;
}
test "ordered reducers, falsy decline, sentinel bypass, dedup and built-in override" {
    var g = d.Graph.init(a);
    defer g.deinit();
    for ([_]d.Value{ .null, .undefined, .{ .boolean = false }, .{ .number = 0 }, .{ .number = -0.0 }, .{ .number = std.math.nan(f64) }, .{ .string = "" }, .{ .bigint = "0" } }) |falsy| {
        var state = ReducerState{ .replacement = falsy };
        const out = try d.stringify(a, &g, .{ .number = 1 }, &.{.{ .name = "Falsy", .context = &state, .reduce = ReducerState.reduce }});
        defer a.free(out);
        try std.testing.expectEqualStrings("[1]", out);
        try std.testing.expectEqual(@as(usize, 1), state.calls);
    }
    const root = try g.array(4);
    const shared = try g.object(false);
    try g.arrayPut(root, 0, shared);
    try g.arrayPut(root, 1, shared);
    try g.arrayPut(root, 2, .{ .string = "same" });
    try g.arrayPut(root, 3, .{ .string = "same" });
    var state: ReducerState = .{};
    const out = try d.stringify(a, &g, root, &.{.{ .name = "Count", .context = &state, .reduce = ReducerState.reduce }});
    defer a.free(out);
    try std.testing.expectEqual(@as(usize, 3), state.calls);
    state.calls = 0;
    const special = try d.stringify(a, &g, .{ .number = std.math.inf(f64) }, &.{.{ .name = "Count", .context = &state, .reduce = ReducerState.reduce }});
    defer a.free(special);
    try std.testing.expectEqual(@as(usize, 0), state.calls);
    // Matching reducer returns same target: index was registered beforehand.
    state.replacement = shared;
    var later: ReducerState = .{};
    const reduced = try d.stringify(a, &g, shared, &.{ .{ .name = "First", .context = &state, .reduce = ReducerState.reduce }, .{ .name = "Second", .context = &later, .reduce = ReducerState.reduce } });
    defer a.free(reduced);
    try std.testing.expectEqualStrings("[[\"First\",0]]", reduced);
    try std.testing.expectEqual(@as(usize, 0), later.calls);
    for ([_][]const u8{ "quote\"", "slash\\", "control\n", "\xff" }) |name| try std.testing.expectError(error.InvalidReducerName, d.stringify(a, &g, .null, &.{.{ .name = name, .context = &state, .reduce = ReducerState.reduce }}));
    state.fail = true;
    try std.testing.expectError(error.CallbackError, d.stringify(a, &g, .null, &.{.{ .name = "Fail", .context = &state, .reduce = ReducerState.reduce }}));
    var r = try d.parse(a, "[[\"Date\",\"2000-01-01T00:00:00.000Z\"]]", &.{.{ .name = "Date", .revive = passthrough }});
    defer r.deinit();
    try std.testing.expectEqualStrings("2000-01-01T00:00:00.000Z", r.value.string);
    var s = try d.parse(a, "[[\"Custom\",1],42]", &.{.{ .name = "Custom", .revive = passthrough }});
    defer s.deinit();
    try std.testing.expectEqual(@as(f64, 42), s.value.number);
    try std.testing.expectError(error.CallbackError, d.parse(a, "[[\"Custom\",1],42]", &.{.{ .name = "Custom", .revive = callbackFail }}));
}
fn allocatingReviver(_: ?*anyopaque, g: *d.Graph, payload: d.Value) d.Error!d.Value {
    const v = try g.object(false);
    try g.put(v, "value", payload);
    return v;
}
fn allocatingReducer(_: ?*anyopaque, g: *d.Graph, v: d.Value) d.Error!?d.Value {
    if (v == .number and v.number == 42) {
        const obj = try g.object(false);
        try g.put(obj, "name", try g.string("answer"));
        return obj;
    }
    return null;
}
fn callbackAllocations(gpa: std.mem.Allocator) !void {
    var r = try d.parse(gpa, "[[\"Custom\",1],{\"text\":2},\"owned\"]", &.{.{ .name = "Custom", .revive = allocatingReviver }});
    defer r.deinit();
    const bytes = try d.stringify(gpa, &r.graph, .{ .number = 42 }, &.{.{ .name = "Custom", .reduce = allocatingReducer }});
    defer gpa.free(bytes);
}
test "allocation failures in allocating callbacks" {
    try std.testing.checkAllAllocationFailures(no_growth, callbackAllocations, .{});
}
test "deterministic varied graphs preserve every supported node family and topology" {
    var random = std.Random.DefaultPrng.init(42);
    for (0..40) |trial| {
        var g = d.Graph.init(a);
        defer g.deinit();
        const root = try g.object(trial % 2 == 0);
        const sparse = try g.array(1000000);
        const shared = try g.object(false);
        try g.put(shared, "root", root);
        try g.put(shared, "self", shared);
        const map = try g.map();
        const set = try g.set();
        const dense = try g.array(12);
        try g.put(root, "first", shared);
        try g.put(root, "alias", shared);
        try g.put(root, "sparse", sparse);
        try g.put(root, "dense", dense);
        try g.put(root, "map", map);
        try g.put(root, "set", set);
        try g.put(root, "self", root);
        try g.arrayPut(sparse, 999999, shared);
        try g.arrayPut(sparse, 0, .undefined);
        try g.arrayPut(sparse, 42, dense);
        try g.mapPut(map, root, sparse);
        try g.mapPut(map, shared, map);
        try g.setAdd(set, shared);
        try g.setAdd(set, set);
        try g.setAdd(set, .{ .number = std.math.nan(f64) });
        const n = random.random().intRangeAtMost(i64, -8640000000000000, 8640000000000000);
        var bytes: [32]u8 = undefined;
        random.random().bytes(&bytes);
        const text = try g.string("owned <Zig>\n雪😀");
        const values = [_]d.Value{
            text,                             text,                        try g.bigint("-123456789012345678901"),
            try g.date(n),                    try g.regexp("a\\/b", "my"), try g.arrayBuffer(&bytes),
            try g.boxed(.{ .number = -0.0 }), try g.boxed(text),           shared,
            try g.object(false),              try g.object(false),         .null,
        };
        // Vary population and insertion order while keeping independently built
        // expected graph semantics, including holes and equal distinct nodes.
        for (0..values.len) |j| {
            const i = if (trial % 2 == 0) values.len - 1 - j else j;
            if (i == 11 and random.random().boolean()) continue;
            try g.arrayPut(dense, @intCast(i), values[i]);
        }
        const encoded = try d.stringify(a, &g, root, &.{});
        defer a.free(encoded);
        var parsed = try d.parse(a, encoded, &.{});
        defer parsed.deinit();
        try @import("graph_expect.zig").equal(&g, root, &parsed.graph, parsed.value);
    }
}
test "malformed boxed reference cycles are invalid documents immediately" {
    for ([_][]const u8{ "[[\"Object\",0]]", "[[\"Object\",1],[\"Object\",0]]", "[[\"Object\",1],{}]" }) |wire| try std.testing.expectError(error.InvalidDocument, d.parse(a, wire, &.{}));
}
test "large and reverse ordered collections use indexed storage" {
    var g = d.Graph.init(a);
    defer g.deinit();
    const obj = try g.object(false);
    const map = try g.map();
    const set = try g.set();
    const arr = try g.array(20000);
    for (0..20000) |j| {
        const i = 19999 - j;
        var buf: [24]u8 = undefined;
        const key = try std.fmt.bufPrint(&buf, "{d}", .{i});
        const value = d.Value{ .number = @floatFromInt(i) };
        try g.put(obj, key, value);
        try g.arrayPut(arr, @intCast(i), value);
        try g.mapPut(map, value, obj);
        try g.setAdd(set, value);
    }
    try std.testing.expectEqual(@as(usize, 20000), (try g.node(obj)).object.properties.items.len);
    try std.testing.expectEqualStrings("0", (try g.node(obj)).object.properties.items[0].key);
    try std.testing.expectEqual(@as(u32, 0), (try g.node(arr)).array.elements.items[0].index);
    try std.testing.expectEqual(@as(f64, 19999), (try g.get(obj, "19999")).?.number);
    try g.put(obj, "42", .{ .boolean = true });
    try std.testing.expect((try g.get(obj, "42")).?.boolean);
    try g.arrayPut(arr, 42, .undefined);
    try std.testing.expect((try g.arrayGet(arr, 42)).? == .undefined);
    const bytes = try d.stringify(a, &g, obj, &.{});
    defer a.free(bytes);
    var r = try d.parse(a, bytes, &.{});
    defer r.deinit();
    try std.testing.expectEqual(@as(f64, 19999), (try r.graph.get(r.value, "19999")).?.number);
    try std.testing.expect((try r.graph.get(r.value, "42")).?.boolean);
    try std.testing.expectEqual(@as(usize, 20000), (try g.node(map)).map.entries.items.len);
    try std.testing.expectEqual(@as(usize, 20000), (try g.node(set)).set.values.items.len);
}
test "long string aliases retain identity without rescanning each edge" {
    var g = d.Graph.init(a);
    defer g.deinit();
    const source = try a.alloc(u8, 1024 * 1024);
    defer a.free(source);
    @memset(source, 'x');
    const s = try g.string(source);
    const arr = try g.array(4000);
    for (0..4000) |i| try g.arrayPut(arr, @intCast(i), s);
    const bytes = try d.stringify(a, &g, arr, &.{});
    defer a.free(bytes);
    var r = try d.parse(a, bytes, &.{});
    defer r.deinit();
    const first = (try r.graph.arrayGet(r.value, 0)).?.string;
    try std.testing.expectEqual(@as(usize, 1024 * 1024), first.len);
    for (1..4000) |i| try std.testing.expect(first.ptr == (try r.graph.arrayGet(r.value, @intCast(i))).?.string.ptr);
}
test "ordinary stringify preserves public input graph across repeated encodes" {
    var g = d.Graph.init(a);
    defer g.deinit();
    const root = try g.object(false);
    const child = try g.array(4);
    const s = try g.string("same");
    try g.put(root, "2", s);
    try g.put(root, "0", child);
    try g.put(root, "self", root);
    try g.arrayPut(child, 3, s);
    try g.arrayPut(child, 0, root);
    const before = (try g.node(root)).object.properties.items;
    const elems = (try g.node(child)).array.elements.items;
    const props = try a.dupe(d.Property, before);
    defer a.free(props);
    const entries = try a.dupe(d.Element, elems);
    defer a.free(entries);
    const nodes = g.nodes.items.len;
    const owned = g.bytes.count();
    const one = try d.stringify(a, &g, root, &.{});
    defer a.free(one);
    for (0..3) |_| {
        const out = try d.stringify(a, &g, root, &.{});
        defer a.free(out);
        try std.testing.expectEqualStrings(one, out);
    }
    try std.testing.expectEqual(nodes, g.nodes.items.len);
    try std.testing.expectEqual(owned, g.bytes.count());
    for (props, (try g.node(root)).object.properties.items) |old, new| {
        try std.testing.expectEqualStrings(old.key, new.key);
        try std.testing.expect(d.equal(old.value, new.value));
    }
    for (entries, (try g.node(child)).array.elements.items) |old, new| {
        try std.testing.expectEqual(old.index, new.index);
        try std.testing.expect(d.equal(old.value, new.value));
    }
}
test "mutations seeded from every shared and Zig corpus document" {
    for ([_][]const u8{ @import("fixtures").golden_path, "testdata/flat-golden.json", "testdata/upstream-flat-golden.json" }) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(16 * 1024 * 1024));
        defer a.free(bytes);
        const Case = struct { name: []const u8, devalue: []const u8 };
        const Corpus = struct { devalue: []const u8, cases: []Case };
        const fixture = try std.json.parseFromSlice(Corpus, a, bytes, .{ .ignore_unknown_fields = true });
        defer fixture.deinit();
        for (fixture.value.cases) |case| {
            const buf = try a.dupe(u8, case.devalue);
            defer a.free(buf);
            const positions = [_]usize{ 0, buf.len / 2, buf.len - 1 };
            for (positions) |i| for ([_]u8{ '0', '[', '"', 255 }) |byte| {
                const saved = buf[i];
                buf[i] = byte;
                defer buf[i] = saved;
                if (d.parse(a, buf, &.{})) |parsed| {
                    var r = parsed;
                    defer r.deinit();
                    const out = try d.stringify(a, &r.graph, r.value, &.{});
                    defer a.free(out);
                    var second = try d.parse(a, out, &.{});
                    defer second.deinit();
                    const final = try d.stringify(a, &second.graph, second.value, &.{});
                    defer a.free(final);
                    try std.testing.expectEqualStrings(out, final);
                } else |err| try std.testing.expect(err != error.OutOfMemory);
            };
        }
    }
}
