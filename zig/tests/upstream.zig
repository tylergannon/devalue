const std = @import("std");
const d = @import("devalue");
const t = @import("tests.zig");
const a = t.a;
const expectGraph = @import("graph_expect.zig").equal;
// Source: https://github.com/sveltejs/devalue/blob/v5.9.4/test/index.test.js
// Common fixtures: primitives, boxed_primitives, basics, strings, cycles,
// repetition, XSS, misc. Native mechanics replace JS prototypes/classes/realms.
const Scalar = enum { integer_positive, integer_negative, decimal_positive, decimal_negative, nan, infinity_positive, infinity_negative, zero, negative_zero, string, boolean, bigint, undefined, null };
fn primitive(g: *d.Graph, name: []const u8, boxed: bool) !d.Value {
    const kind = std.meta.stringToEnum(Scalar, name) orelse return error.UnknownFixture;
    const v: d.Value = switch (kind) {
        .integer_positive => .{ .number = 42 },
        .integer_negative => .{ .number = if (boxed) -2 else -5 },
        .decimal_positive => .{ .number = 0.1 },
        .decimal_negative => .{ .number = -0.1 },
        .nan => .{ .number = std.math.nan(f64) },
        .infinity_positive => .{ .number = std.math.inf(f64) },
        .infinity_negative => .{ .number = -std.math.inf(f64) },
        .zero => .{ .number = 0 },
        .negative_zero => .{ .number = -0.0 },
        .string => try g.string("woo!!!"),
        .boolean => .{ .boolean = true },
        .bigint => try g.bigint("1"),
        .undefined => .undefined,
        .null => .null,
    };
    return if (boxed) g.boxed(v) else v;
}
const Case = enum {
    regexp,
    date,
    array,
    array_zero,
    array_empty,
    array_sparse,
    array_very_sparse,
    array_multi_sparse,
    object,
    set,
    map,
    buffer,
    string_newline,
    string_quotes,
    string_surrogate_pair,
    string_nul,
    string_control,
    string_control_extreme,
    string_backslash,
    cycle_map,
    cycle_set,
    cycle_array,
    cycle_object,
    cycle_null_object,
    cycle_class_equivalent,
    cycle_mutual,
    repeat_string,
    repeat_null,
    repeat_nan,
    repeat_number_box,
    repeat_bigint_box,
    repeat_nan_box,
    repeat_object,
    repeat_map,
    repeat_set,
    repeat_regexp,
    repeat_date,
    repeat_map_key,
    interlinked_map_keys,
    xss_string,
    xss_key,
    xss_regexp,
    xss_regexp_repeat,
    null_object_empty,
    plain_object_empty,
    enumerable_object,
    null_object_keys,
    native_alias_cycle,
    custom_nested,
    function_wrapped,
    function_nested,
    native_boxed_variants,
    native_builtins,
};
fn list(g: *d.Graph, items: []const d.Value) !d.Value {
    const arr = try g.array(@intCast(items.len));
    for (items, 0..) |v, i| try g.arrayPut(arr, @intCast(i), v);
    return arr;
}
const danger = "</script><script src='https://evil.com/script.js'>alert('pwned')</script><script>";
const dangerous_regex = "[</script><script>alert('xss')//]";
fn wrapped(g: *d.Graph, kind: []const u8, payload: d.Value) d.Error!d.Value {
    const v = try g.object(false);
    try g.put(v, "kind", try g.string(kind));
    try g.put(v, "value", payload);
    return v;
}
fn reduce(ctx: ?*anyopaque, g: *d.Graph, v: d.Value) d.Error!?d.Value {
    const name: *const []const u8 = @ptrCast(@alignCast(ctx.?));
    if (v != .ref or try g.node(v) != .object) return null;
    const kind = (try g.get(v, "kind")) orelse return null;
    if (!d.equal(kind, .{ .string = name.* })) return null;
    return g.get(v, "value");
}
fn revive(ctx: ?*anyopaque, g: *d.Graph, v: d.Value) d.Error!d.Value {
    const name: *const []const u8 = @ptrCast(@alignCast(ctx.?));
    return wrapped(g, name.*, v);
}
fn construct(g: *d.Graph, name: []const u8) !d.Value {
    if (std.mem.startsWith(u8, name, "primitive_")) return primitive(g, name[10..], false);
    if (std.mem.startsWith(u8, name, "boxed_")) return primitive(g, name[6..], true);
    const case = std.meta.stringToEnum(Case, name) orelse return error.UnknownFixture;
    switch (case) {
        .custom_nested => {
            const inner = try g.object(false);
            try g.put(inner, "answer", .{ .number = 42 });
            const payload = try g.object(false);
            try g.put(payload, "bar", try wrapped(g, "Bar", inner));
            const foo = try wrapped(g, "Foo", payload);
            return list(g, &.{ foo, foo });
        },
        .function_wrapped, .function_nested => {
            const f = try wrapped(g, "FunctionRef", try g.string("(x) => x * 2"));
            if (case == .function_wrapped) return f;
            const obj = try g.object(false);
            const nested_obj = try g.object(false);
            try g.put(nested_obj, "data", .{ .number = 42 });
            try g.put(obj, "fn", f);
            try g.put(obj, "nested", nested_obj);
            return obj;
        },
        .regexp => return g.regexp("regexp", "gim"),
        .date => return g.date(1000000000000),
        .array => return list(g, &.{ try g.string("a"), try g.string("b"), try g.string("c") }),
        .array_zero => return list(g, &.{ .{ .number = 0 }, .{ .number = -0.0 } }),
        .array_empty => return g.array(0),
        .array_sparse, .array_very_sparse, .array_multi_sparse => {
            const arr = try g.array(if (case == .array_sparse) 3 else if (case == .array_very_sparse) 1000001 else 21);
            if (case == .array_multi_sparse) {
                try g.arrayPut(arr, 10, try g.string("a"));
                try g.arrayPut(arr, 20, try g.string("b"));
            } else try g.arrayPut(arr, if (case == .array_sparse) 1 else 1000000, try g.string(if (case == .array_sparse) "b" else "x"));
            return arr;
        },
        .object => {
            const obj = try g.object(false);
            try g.put(obj, "foo", try g.string("bar"));
            try g.put(obj, "x-y", try g.string("z"));
            return obj;
        },
        .set => {
            const v = try g.set();
            for (1..4) |i| try g.setAdd(v, .{ .number = @floatFromInt(i) });
            return v;
        },
        .map => {
            const v = try g.map();
            try g.mapPut(v, try g.string("a"), try g.string("b"));
            return v;
        },
        .buffer => return g.arrayBuffer(&.{ 1, 2, 3 }),
        .string_newline => return g.string("a\nb"),
        .string_quotes => return g.string("\"yar\""),
        .string_surrogate_pair => return g.string("𝌆"),
        .string_nul => return g.string("\x00"),
        .string_control => return g.string("\x01"),
        .string_control_extreme => return g.string("\x1f"),
        .string_backslash => return g.string("\\"),
        .cycle_map => {
            const v = try g.map();
            try g.mapPut(v, try g.string("self"), v);
            return v;
        },
        .cycle_set => {
            const v = try g.set();
            try g.setAdd(v, v);
            try g.setAdd(v, .{ .number = 42 });
            return v;
        },
        .cycle_array => {
            const v = try g.array(1);
            try g.arrayPut(v, 0, v);
            return v;
        },
        .cycle_object, .cycle_null_object, .cycle_class_equivalent => {
            const v = try g.object(case == .cycle_null_object);
            if (case == .cycle_class_equivalent) try g.put(v, "foo", try g.string("bar"));
            try g.put(v, "self", v);
            return v;
        },
        .cycle_mutual => {
            const x = try g.object(false);
            const y = try g.object(false);
            try g.put(x, "second", y);
            try g.put(y, "first", x);
            return list(g, &.{ x, y });
        },
        .repeat_string, .repeat_null, .repeat_nan, .repeat_number_box, .repeat_bigint_box, .repeat_nan_box, .repeat_object, .repeat_map, .repeat_set, .repeat_regexp, .repeat_date => {
            const v: d.Value = switch (case) {
                .repeat_string => try g.string("a string"),
                .repeat_null => .null,
                .repeat_nan => .{ .number = std.math.nan(f64) },
                .repeat_number_box => try g.boxed(.{ .number = 42 }),
                .repeat_bigint_box => try g.boxed(try g.bigint("1")),
                .repeat_nan_box => try g.boxed(.{ .number = std.math.nan(f64) }),
                .repeat_object => try g.object(false),
                .repeat_map => try g.map(),
                .repeat_set => try g.set(),
                .repeat_regexp => try g.regexp("regexp", ""),
                .repeat_date => try g.date(1000000000000),
                else => unreachable,
            };
            return list(g, &.{ v, v });
        },
        .repeat_map_key => {
            const obj = try g.object(false);
            try g.put(obj, "id", .{ .number = 1 });
            const m = try g.map();
            try g.mapPut(m, obj, try g.string("v"));
            return list(g, &.{ obj, m });
        },
        .interlinked_map_keys => {
            const m = try g.map();
            var nodes: [3]d.Value = undefined;
            for (&nodes, 1..) |*node, i| {
                node.* = try g.object(false);
                try g.put(node.*, "id", .{ .number = @floatFromInt(i) });
            }
            for (nodes, 0..) |node, i| {
                const sibling = try g.map();
                for (nodes, 0..) |key, j| if (i != j) {
                    try g.mapPut(sibling, key, .{ .number = 1 });
                };
                try g.mapPut(m, node, sibling);
            }
            return m;
        },
        .xss_string => return g.string(danger),
        .xss_key => {
            const v = try g.object(false);
            try g.put(v, "<svg onload=alert(\"xss_works\")>", try g.string("bar"));
            return v;
        },
        .xss_regexp => return g.regexp(dangerous_regex, ""),
        .xss_regexp_repeat => {
            const v = try g.regexp(dangerous_regex, "");
            return list(g, &.{ v, v });
        },
        .null_object_empty, .plain_object_empty => return g.object(case == .null_object_empty),
        .enumerable_object => {
            const v = try g.object(false);
            try g.put(v, "x", .{ .number = 1 });
            return v;
        },
        .null_object_keys => {
            const v = try g.object(true);
            for ([_][]const u8{ "", "0", "constructor", "toString" }, [_][]const u8{ "empty", "numeric", "constructor", "toString" }) |key, val| try g.put(v, key, try g.string(val));
            return v;
        },
        .native_alias_cycle => {
            const v = try g.object(false);
            const arr = try list(g, &.{ try g.string("<hi>\n😀"), .undefined });
            try g.put(v, "first", arr);
            try g.put(v, "alias", arr);
            try g.put(v, "self", v);
            return v;
        },
        .native_boxed_variants => return list(g, &.{ try g.boxed(.{ .number = 42 }), try g.boxed(try g.string("hi")), try g.boxed(try g.bigint("0")), try g.boxed(.{ .number = -0.0 }) }),
        .native_builtins => {
            const o = try g.object(true);
            try g.put(o, "x", .{ .number = 1 });
            const m = try g.map();
            try g.mapPut(m, try g.string("k"), o);
            try g.mapPut(m, m, m);
            const s = try g.set();
            try g.setAdd(s, .{ .number = -0.0 });
            try g.setAdd(s, .{ .number = 0 });
            try g.setAdd(s, .{ .number = std.math.nan(f64) });
            try g.setAdd(s, .{ .number = std.math.nan(f64) });
            try g.setAdd(s, s);
            return list(g, &.{ try g.bigint("-123456789012345678901"), try g.date(-1), try g.regexp("a\\/b\\n", "my"), try g.arrayBuffer(&.{ 0, 255 }), try g.boxed(.{ .boolean = false }), o, m, s });
        },
    }
}
test "upstream common fixtures independently encode and preserve decoded contents and topology" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "testdata/upstream-flat-golden.json", a, .limited(1024 * 1024));
    defer a.free(bytes);
    const Fixture = struct { devalue: []const u8, cases: []struct { name: []const u8, devalue: []const u8 } };
    const fixture = try std.json.parseFromSlice(Fixture, a, bytes, .{});
    defer fixture.deinit();
    try std.testing.expectEqualStrings(d.upstream_version, fixture.value.devalue);
    try std.testing.expectEqual(@as(usize, 79), fixture.value.cases.len);
    var names: std.StringHashMapUnmanaged(void) = .empty;
    defer names.deinit(a);
    for (fixture.value.cases) |case| {
        try std.testing.expect(!names.contains(case.name));
        try names.put(a, case.name, {});
        var g = d.Graph.init(a);
        defer g.deinit();
        const v = try construct(&g, case.name);
        var tags = [_][]const u8{ "Foo", "Bar", "FunctionRef" };
        var reducers: [3]d.Reducer = undefined;
        var revivers: [3]d.Reviver = undefined;
        for (&tags, &reducers, &revivers) |*tag, *reducer, *reviver| {
            reducer.* = .{ .name = tag.*, .context = @ptrCast(tag), .reduce = reduce };
            reviver.* = .{ .name = tag.*, .context = @ptrCast(tag), .revive = revive };
        }
        const custom = std.mem.eql(u8, case.name, "custom_nested") or std.mem.startsWith(u8, case.name, "function_");
        const encoded = try d.stringify(a, &g, v, if (custom) &reducers else &.{});
        defer a.free(encoded);
        if (!std.mem.eql(u8, encoded, case.devalue)) std.debug.print("upstream native case {s}\n", .{case.name});
        try std.testing.expectEqualStrings(case.devalue, encoded);
        var parsed = try d.parse(a, case.devalue, if (custom) &revivers else &.{});
        defer parsed.deinit();
        try expectGraph(&g, v, &parsed.graph, parsed.value);
    }
}

fn passthrough(_: ?*anyopaque, _: *d.Graph, v: d.Value) d.Error!d.Value {
    return v;
}
// index.test.js invalid table (1110-1254) and key guards (1271-1314).
// View-specific invalid documents are ported in binary.zig.
test "upstream invalid documents and null-prototype key guards" {
    const invalid = [_][]const u8{
        "[[\"ArrayBuffer\",{\"length\":100}]]",                            "",                                    "][",                                                  "-2",                                          "\"hello\"",                                                        "42",             "true",      "null",       "{}",             "[]",
        "[{\"__proto__\":1},{}]",                                          "[[-7,1,\"__proto__\",{}]]",           "[[-7,5,\"foo\",1]]",                                  "[[-7,5,-1,1]]",                               "[[-7,2,5,1]]",                                                     "[[-7,\"abc\"]]", "[[-7,-3]]", "[[-7,1.5]]", "[[-7,5,1.5,1]]", "[[\"null\",\"__proto__\",1],{}]",
        "[{\"data\":1},[\"null\",\"__proto__\",2],{\"polluted\":3},true]", "[[\"Object\",{\"__proto__\":1}],{}]", "[{\"wrapped\":1},[\"Object\",{\"__proto__\":2}],{}]", "[{\"0\":1,\"toString\":\"push\"},\"hello\"]", "[{\"data\":1},[\"null\",[\"__proto__\"],2],{\"isAdmin\":3},true]", "[[\"Set\",7]]",
    };
    for (invalid) |wire| try std.testing.expectError(error.InvalidDocument, d.parse(a, wire, &.{}));
    try std.testing.expectError(error.InvalidDocument, d.parse(a, "[[\"Custom\",0]]", &.{.{ .name = "Custom", .revive = passthrough }}));
    for ([_][]const u8{ "[\"__proto__\"]", "[[\"__proto__\"]]", "[]", "{}", "0", "true", "null" }) |key| {
        const wire = try a.print("[[\"null\",{s},1],{{\"isAdmin\":2}},true]", .{key});
        defer a.free(wire);
        try std.testing.expectError(error.InvalidDocument, d.parse(a, wire, &.{}));
    }
    var g = d.Graph.init(a);
    defer g.deinit();
    for ([_]bool{ false, true }) |null_proto| {
        const obj = try g.object(null_proto);
        try std.testing.expectError(error.UnsupportedValue, g.put(obj, "__proto__", .null));
    }
}
const Calls = struct {
    calls: usize = 0,
    fn revive(ctx: ?*anyopaque, _: *d.Graph, v: d.Value) d.Error!d.Value {
        const self: *@This() = @ptrCast(@alignCast(ctx.?));
        self.calls += 1;
        return v;
    }
};
// parse-operations.test.js: invalid keys are rejected before hydration/assignment.
// index.test.js: sparse type confusion rejects before custom Vector revival.
test "upstream invalid keys and sparse type confusion reject before reviver effects" {
    var calls: Calls = .{};
    const revivers = [_]d.Reviver{.{ .name = "Vector", .context = &calls, .revive = Calls.revive }};
    for ([_][]const u8{
        "[[\"null\",[\"__proto__\"],1],[\"Vector\",2],42]",
        "[[-7,0,\"x\",1,\"y\",2,\"magnitude\",3,\"__proto__\",4],3,4,\"nope\",[\"Vector\",5],[6,7],8,9]",
    }) |wire| try std.testing.expectError(error.InvalidDocument, d.parse(a, wire, &revivers));
    try std.testing.expectEqual(@as(usize, 0), calls.calls);
}
// index.test.js: sparse array CPU exhaustion (49,000 prototype-chain layers).
test "upstream 49000-layer sparse prototype attack is rejected" {
    var wire: std.ArrayList(u8) = .empty;
    defer wire.deinit(a);
    try wire.appendSlice(a, "[[-7,0");
    for (3..49003) |i| {
        var buf: [64]u8 = undefined;
        try wire.appendSlice(a, try std.fmt.bufPrint(&buf, ",\"__proto__\",{d}", .{i}));
    }
    try wire.appendSlice(a, "],0,[]");
    for (3..49003) |i| {
        var buf: [64]u8 = undefined;
        try wire.appendSlice(a, try std.fmt.bufPrint(&buf, ",[-7,0,\"__proto__\",{d}]", .{i - 1}));
    }
    try wire.appendSlice(a, "]");
    try std.testing.expectError(error.InvalidDocument, d.parse(a, wire.items, &.{}));
}
// index.test.js: valid sparse array length/content/holes after pollution fixes.
test "upstream legitimate sparse input retains holes and declared length" {
    var r = try d.parse(a, "[[-7,3,0,1,2,2],\"a\",\"c\"]", &.{});
    defer r.deinit();
    try std.testing.expectEqual(@as(u32, 3), (try r.graph.node(r.value)).array.length);
    try std.testing.expectEqualStrings("a", (try r.graph.arrayGet(r.value, 0)).?.string);
    try std.testing.expect(try r.graph.arrayGet(r.value, 1) == null);
    try std.testing.expectEqualStrings("c", (try r.graph.arrayGet(r.value, 2)).?.string);
}
// index.test.js: sparseDoSCases, preserving all five upstream sizes. These
// imply ~20GB of dense slots each; allocation must follow actual population.
test "upstream full sparse allocation exhaustion matrix" {
    const Row = struct { length: u32, count: usize };
    for ([_]Row{ .{ .length = 10000, .count = 250000 }, .{ .length = 100000, .count = 25000 }, .{ .length = 1000000, .count = 2500 }, .{ .length = 10000000, .count = 250 }, .{ .length = 100000000, .count = 25 } }) |row| {
        var wire: std.ArrayList(u8) = .empty;
        defer wire.deinit(a);
        try wire.appendSlice(a, "[{");
        for (0..row.count) |i| {
            var buf: [80]u8 = undefined;
            try wire.appendSlice(a, try std.fmt.bufPrint(&buf, "{s}\"k{d}\":{d}", .{ if (i == 0) "" else ",", i, i + 1 }));
        }
        try wire.appendSlice(a, "}");
        var buf: [80]u8 = undefined;
        const entry = try std.fmt.bufPrint(&buf, ",[-7,{d},0,{d}]", .{ row.length, row.count + 1 });
        for (0..row.count) |_| try wire.appendSlice(a, entry);
        try wire.appendSlice(a, ",42]");
        var r = try d.parse(a, wire.items, &.{});
        defer r.deinit();
        const obj = (try r.graph.node(r.value)).object;
        try std.testing.expectEqual(row.count, obj.properties.items.len);
        for ([_]usize{ 0, row.count - 1 }) |i| {
            var key: [32]u8 = undefined;
            const arr = (try r.graph.get(r.value, try std.fmt.bufPrint(&key, "k{d}", .{i}))).?;
            const node = (try r.graph.node(arr)).array;
            try std.testing.expectEqual(row.length, node.length);
            try std.testing.expectEqual(@as(usize, 1), node.elements.items.len);
            try std.testing.expectEqual(@as(f64, 42), (try r.graph.arrayGet(arr, 0)).?.number);
            try std.testing.expect(try r.graph.arrayGet(arr, row.length - 1) == null);
        }
    }
}
// operations.test.js: filterArrayIndices leading valid indices / rejection.
// The native array API admits only u32 indices; object enumeration uses the
// same JS valid-index predicate and must leave source bytes unchanged.
test "upstream index classification boundaries and native array property boundary" {
    for ([_][]const u8{ "0", "1", "2", "7", "4294967294" }, [_]u32{ 0, 1, 2, 7, 4294967294 }) |key, index| try std.testing.expectEqual(index, d.arrayIndex(key).?);
    for ([_][]const u8{ "01", "-1", "1.5", "4294967295", "extra", "a", "b", "" }) |key| try std.testing.expectEqual(@as(?u32, null), d.arrayIndex(key));
    var g = d.Graph.init(a);
    defer g.deinit();
    for ([_]u32{ 3, 1000001 }) |length| {
        const arr = try g.array(length);
        try std.testing.expectError(error.InvalidType, g.put(arr, "extra", .null));
        try g.arrayPut(arr, 0, .{ .number = 1 });
        try std.testing.expectEqual(@as(usize, 1), (try g.node(arr)).array.elements.items.len);
    }
}

// JSON.parse overwrites duplicate keys before upstream hydrate sees them. The
// scanner-based native decoder must preserve that behavior without reviving a
// discarded value; numeric keys still enumerate ahead of string keys.
test "duplicate JSON keys keep the last value and never revive discarded payloads" {
    var calls: Calls = .{};
    const revivers = [_]d.Reviver{.{ .name = "Discarded", .context = &calls, .revive = Calls.revive }};
    var r = try d.parse(a, "[{\"z\":1,\"2\":2,\"z\":3},[\"Discarded\",4],9,42,99]", &revivers);
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 0), calls.calls);
    try std.testing.expectEqual(@as(f64, 42), (try r.graph.get(r.value, "z")).?.number);
    try std.testing.expectEqual(@as(f64, 9), (try r.graph.get(r.value, "2")).?.number);
    const props = (try r.graph.node(r.value)).object.properties.items;
    try std.testing.expectEqual(@as(usize, 2), props.len);
    try std.testing.expectEqualStrings("2", props[0].key);
    try std.testing.expectEqualStrings("z", props[1].key);
}
