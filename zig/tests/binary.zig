const std = @import("std");
const d = @import("devalue");
const a = std.testing.allocator;
const topology = @import("graph_expect.zig");
const kinds = std.meta.tags(d.TypedArrayKind);

fn sequence(g: *d.Graph, length: usize) !d.Value {
    var bytes: [33]u8 = undefined;
    for (bytes[0..length], 0..) |*b, i| b.* = @intCast(i);
    return g.arrayBuffer(bytes[0..length]);
}
fn makeView(g: *d.Graph, kind: ?d.TypedArrayKind, b: d.Value, offset: usize, length: usize) !d.Value {
    return if (kind) |k| g.typedArray(k, b, offset, length) else g.dataView(b, offset, length);
}
fn repeated(g: *d.Graph, v: d.Value) !d.Value {
    const result = try g.array(2);
    try g.arrayPut(result, 0, v);
    try g.arrayPut(result, 1, v);
    return result;
}
fn fixtureValue(g: *d.Graph, name: []const u8) !d.Value {
    var kind: ?d.TypedArrayKind = null;
    var suffix: ?[]const u8 = null;
    for (kinds) |k| {
        const tag = @tagName(k);
        if (std.mem.startsWith(u8, name, tag) and name.len > tag.len and name[tag.len] == '_') {
            kind = k;
            suffix = name[tag.len + 1 ..];
            break;
        }
    }
    if (std.mem.startsWith(u8, name, "DataView_")) suffix = name[9..];
    if (suffix) |shape| {
        const width = if (kind) |k| k.bytesPerElement() else 1;
        if (std.mem.eql(u8, shape, "empty_buffer")) return makeView(g, kind, try g.arrayBuffer(""), 0, 0);
        const b = try sequence(g, if (std.mem.eql(u8, shape, "odd_explicit")) 33 else 32);
        if (std.mem.eql(u8, shape, "full")) return makeView(g, kind, b, 0, 32 / width);
        if (std.mem.eql(u8, shape, "sub")) return makeView(g, kind, b, width, 2);
        if (std.mem.eql(u8, shape, "empty_end")) return makeView(g, kind, b, 32, 0);
        if (std.mem.eql(u8, shape, "odd_explicit")) return makeView(g, kind, b, 0, 1);
        if (std.mem.eql(u8, shape, "identity")) {
            const v = try makeView(g, kind, b, width, 2);
            const root = try g.object(false);
            try g.put(root, "view", v);
            try g.put(root, "again", v);
            try g.put(root, "distinct", try makeView(g, kind, b, width, 2));
            try g.put(root, "buffer", b);
            try g.put(root, "self", root);
            return root;
        }
    }
    // Eight Node host-allocation sources collapse to the same native input.
    if (std.mem.eql(u8, name, "uint8") or std.mem.eql(u8, name, "browser_uint8") or std.mem.startsWith(u8, name, "source_") or std.mem.startsWith(u8, name, "reduced_")) return g.uint8ArrayCopy(&.{ 1, 2, 3 });
    if (std.mem.eql(u8, name, "node_alloc")) return g.uint8ArrayCopy("AAAA");
    if (std.mem.eql(u8, name, "empty_copy")) return g.uint8ArrayCopy("");
    if (std.mem.eql(u8, name, "isolated_copies")) {
        const first = try g.uint8ArrayCopy(&.{ 1, 2, 3 });
        const root = try g.object(false);
        try g.put(root, "first", first);
        try g.put(root, "again", first);
        try g.put(root, "second", try g.uint8ArrayCopy(&.{ 4, 5 }));
        try g.put(root, "self", root);
        return root;
    }
    if (std.mem.eql(u8, name, "file_contents")) {
        const input = @embedFile("binary-file-input.txt");
        const root = try g.object(false);
        try g.put(root, "file", try g.uint8ArrayCopy(input));
        return root;
    }
    if (std.mem.eql(u8, name, "float64_negative_zero") or std.mem.eql(u8, name, "raw_float_bits")) {
        const bytes: []const u8 = if (std.mem.eql(u8, name, "raw_float_bits"))
            &.{ 1, 0, 0, 0, 0, 0, 248, 127, 0, 0, 0, 0, 0, 0, 0, 128 }
        else
            &.{ 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 0, 0, 248, 63 };
        return g.typedArray(.Float64Array, try g.arrayBuffer(bytes), 0, 2);
    }
    if (std.mem.eql(u8, name, "bigint64") or std.mem.eql(u8, name, "biguint64") or std.mem.eql(u8, name, "bigint_repeat")) {
        const signed = std.mem.eql(u8, name, "bigint64");
        const bytes: []const u8 = if (signed)
            &.{ 1, 0, 0, 0, 0, 0, 0, 0, 254, 255, 255, 255, 255, 255, 255, 255, 3, 0, 0, 0, 0, 0, 0, 0 }
        else
            &.{ 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0 };
        const v = try g.typedArray(if (signed or std.mem.eql(u8, name, "bigint_repeat")) .BigInt64Array else .BigUint64Array, try g.arrayBuffer(bytes), 0, 3);
        return if (std.mem.eql(u8, name, "bigint_repeat")) repeated(g, v) else v;
    }
    if (std.mem.eql(u8, name, "dataview")) return g.dataView(try g.arrayBuffer(&.{ 1, 2, 3 }), 0, 3);
    if (std.mem.eql(u8, name, "uint16_sub")) return g.typedArray(.Uint16Array, try g.arrayBuffer(&.{ 10, 0, 20, 0, 30, 0, 40, 0 }), 2, 2);
    if (std.mem.eql(u8, name, "ordinary_shared")) {
        const b = try sequence(g, 6);
        const v = try g.typedArray(.Uint8Array, b, 1, 3);
        const root = try g.object(false);
        try g.put(root, "buffer", b);
        try g.put(root, "view", v);
        try g.put(root, "again", v);
        try g.put(root, "data", try g.dataView(b, 2, 2));
        return root;
    }
    const b = try sequence(g, 10);
    if (std.mem.eql(u8, name, "dataview_sub")) return g.dataView(b, 2, 4);
    if (std.mem.eql(u8, name, "data_sub_repeat")) return repeated(g, try g.dataView(b, 2, 4));
    if (std.mem.eql(u8, name, "data_repeat")) return repeated(g, try g.dataView(b, 0, 10));
    if (std.mem.eql(u8, name, "typed_repeat")) return repeated(g, try g.typedArray(.Uint8Array, b, 0, 10));
    if (std.mem.eql(u8, name, "buffer_data_repeat")) {
        const v = try g.dataView(b, 0, 10);
        const root = try g.array(3);
        try g.arrayPut(root, 0, v);
        try g.arrayPut(root, 1, v);
        try g.arrayPut(root, 2, b);
        return root;
    }
    if (std.mem.eql(u8, name, "buffer_repeat_views") or std.mem.eql(u8, name, "buffer_typed_repeat")) {
        const repeat = std.mem.eql(u8, name, "buffer_typed_repeat");
        const v = try g.typedArray(.Uint8Array, b, 0, 10);
        const root = try g.array(if (repeat) 3 else 2);
        try g.arrayPut(root, 0, v);
        if (repeat) try g.arrayPut(root, 1, v);
        try g.arrayPut(root, if (repeat) 2 else 1, try g.typedArray(.Uint16Array, b, 0, 5));
        return root;
    }
    std.debug.print("missing binary fixture input {s}\n", .{name});
    return error.UnknownFixture;
}

// Sources: https://github.com/sveltejs/devalue/blob/v5.9.4/test/index.test.js
// and /test/buffer.test.js. Encode inputs are built independently of decode;
// topology comparison checks view identity and buffer identity separately.
test "all upstream binary fixtures independently encoded and decoded" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "testdata/binary-golden.json", a, .limited(1024 * 1024));
    defer a.free(bytes);
    const Case = struct { name: []const u8, devalue: []const u8 };
    const corpus = try std.json.parseFromSlice(struct { devalue: []const u8, cases: []Case }, a, bytes, .{});
    defer corpus.deinit();
    try std.testing.expectEqualStrings(d.upstream_version, corpus.value.devalue);
    try std.testing.expectEqual(@as(usize, 109), corpus.value.cases.len);
    for (corpus.value.cases) |case| {
        var expected = d.Graph.init(a);
        defer expected.deinit();
        const value = try fixtureValue(&expected, case.name);
        const reduced_view = std.mem.eql(u8, case.name, "reduced_view");
        const reduced_buffer = std.mem.eql(u8, case.name, "reduced_buffer");
        const reducers: []const d.Reducer = if (reduced_view) &.{.{ .name = "View", .reduce = reduceView }} else if (reduced_buffer) &.{.{ .name = "Raw", .reduce = reduceBuffer }} else &.{};
        const encoded = try d.stringify(a, &expected, value, reducers);
        defer a.free(encoded);
        if (!std.mem.eql(u8, encoded, case.devalue)) std.debug.print("binary fixture {s}\n", .{case.name});
        try std.testing.expectEqualStrings(case.devalue, encoded);
        if (reduced_view) {
            var override = try d.parse(a, case.devalue, &.{.{ .name = "View", .revive = identity }});
            defer override.deinit();
            try std.testing.expectEqualStrings("payload", override.value.string);
            continue;
        }
        if (reduced_buffer) {
            // Upstream's raw-slot guard rejects a custom buffer tag even if a
            // reviver could manufacture a genuine buffer from that payload.
            try std.testing.expectError(error.InvalidDocument, d.parse(a, case.devalue, &.{.{ .name = "Raw", .revive = identity }}));
            continue;
        }
        var actual = try d.parse(a, case.devalue, &.{});
        defer actual.deinit();
        try topology.equal(&expected, value, &actual.graph, actual.value);
    }
}
fn reduceView(_: ?*anyopaque, g: *d.Graph, v: d.Value) d.Error!?d.Value {
    return if (v == .ref and (try g.node(v)) == .typed_array) try g.string("payload") else null;
}
fn reduceBuffer(_: ?*anyopaque, g: *d.Graph, v: d.Value) d.Error!?d.Value {
    return if (v == .ref and (try g.node(v)) == .array_buffer) try g.string("payload") else null;
}

test "binary constructor geometry, copy lifetime and handle growth" {
    var g = d.Graph.init(a);
    defer g.deinit();
    var source = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };
    const b = try g.arrayBuffer(&source);
    const copy = try g.uint8ArrayCopy(source[2..5]);
    @memset(&source, 255);
    const view = try g.typedArray(.Uint16Array, b, 2, 2);
    const data = try g.dataView(b, 1, 3);
    for (0..2000) |_| _ = try g.object(false);
    try std.testing.expectEqualSlices(u8, &.{ 2, 3, 4, 5 }, try g.viewBytes(view));
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, try g.viewBytes(data));
    try std.testing.expectEqualSlices(u8, &.{ 2, 3, 4 }, try g.viewBytes(copy));
    const copy2 = try g.uint8ArrayCopy(&.{ 2, 3, 4 });
    try std.testing.expect(!d.equal((try g.node(copy)).typed_array.buffer, (try g.node(copy2)).typed_array.buffer));
    for (kinds) |k| {
        const w = k.bytesPerElement();
        _ = try g.typedArray(k, b, 8, 0);
        try std.testing.expectError(error.InvalidType, g.typedArray(k, b, 9, 0));
        try std.testing.expectError(error.InvalidType, g.typedArray(k, b, 0, std.math.maxInt(usize)));
        try std.testing.expectError(error.InvalidType, g.typedArray(k, b, std.math.maxInt(usize), 0));
        if (w > 1) try std.testing.expectError(error.InvalidType, g.typedArray(k, b, 1, 0));
        try std.testing.expectError(error.InvalidType, g.typedArray(k, .null, 0, 0));
        try std.testing.expectError(error.InvalidType, g.typedArray(k, view, 0, 0));
    }
    try std.testing.expectError(error.InvalidType, g.dataView(b, 7, 2));
    try std.testing.expectError(error.InvalidType, g.dataView(b, std.math.maxInt(usize), 0));
    try std.testing.expectError(error.InvalidType, g.viewBytes(b));
    try std.testing.expectError(error.InvalidHandle, g.dataView(.{ .ref = @fromBackingInt(@intCast(999999)) }, 0, 0));
    const input = try a.dupe(u8, "[[\"Uint16Array\",1,2,2],[\"ArrayBuffer\",\"AAECAwQFBgc=\"]]");
    var parsed = try d.parse(a, input, &.{});
    @memset(input, 'x');
    a.free(input);
    defer parsed.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 2, 3, 4, 5 }, try parsed.graph.viewBytes(parsed.value));
}

test "all binary tags validate raw references and bounds before allocation" {
    // Includes index.test.js invalid typed input/self/mutual references, plus
    // strict native geometry/arity/type tests. No claimed length allocates bytes.
    const tails = [_][]const u8{
        "",                      ",0",         ",1,0,1,99", ",-1",       ",0.5",       ",1.5",    ",99",    ",\"1\"",                ",null",
        ",1,-1,1",               ",1,-0.5,1",  ",1,0,1.5",  ",1,0,null", ",1,0,\"2\"", ",1,0,-1", ",1,9,0", ",1,0,9007199254740991", ",1,0,9007199254740992",
        ",1,9007199254740991,0", ",1,0,1e999",
    };
    for (0..kinds.len + 1) |i| {
        const tag = if (i == kinds.len) "DataView" else @tagName(kinds[i]);
        for (tails) |tail| {
            const wire = try a.print("[[\"{s}\"{s}],[\"ArrayBuffer\",\"AAECAwQFBgc=\"]]", .{ tag, tail });
            defer a.free(wire);
            try std.testing.expectError(error.InvalidDocument, d.parse(a, wire, &.{}));
        }
        for ([_][]const u8{ "{\"length\":2}", "1024", "null", "[]", "[\"Uint8Array\",0]", "[\"Custom\",0]", "[\"ArrayBufferX\",\"AA==\"]" }) |raw| {
            const wire = try a.print("[[\"{s}\",1],{s},1000000000]", .{ tag, raw });
            defer a.free(wire);
            try std.testing.expectError(error.InvalidDocument, d.parse(a, wire, &.{}));
        }
        const w = if (i == kinds.len) 1 else kinds[i].bytesPerElement();
        const remainder_wire = try a.print("[[\"{s}\",1,{d}],[\"ArrayBuffer\",\"AAECAwQFBgc=\"]]", .{ tag, w });
        defer a.free(remainder_wire);
        var remainder = try d.parse(a, remainder_wire, &.{});
        defer remainder.deinit();
        try std.testing.expectEqual(@as(usize, 8) - w, (try remainder.graph.viewBytes(remainder.value)).len);
        const remainder_node = try remainder.graph.node(remainder.value);
        try std.testing.expectEqual(w, if (i == kinds.len) remainder_node.data_view.byte_offset else remainder_node.typed_array.byte_offset);
        for ([_][]const u8{ "", ",8", ",8,0", ",0,1" }) |bounds| {
            const wire = try a.print("[[\"{s}\",1{s}],[\"ArrayBuffer\",\"AAECAwQFBgc=\"]]", .{ tag, bounds });
            defer a.free(wire);
            var r = try d.parse(a, wire, &.{});
            defer r.deinit();
            const len: usize = if (std.mem.eql(u8, bounds, "")) 8 else if (std.mem.eql(u8, bounds, ",0,1")) w else 0;
            try std.testing.expectEqual(len, (try r.graph.viewBytes(r.value)).len);
        }
        if (w > 1) {
            for ([_][]const u8{ "", ",0", ",1,0", ",0,2" }) |bounds| {
                const wire = try a.print("[[\"{s}\",1{s}],[\"ArrayBuffer\",\"AAEC\"]]", .{ tag, bounds });
                defer a.free(wire);
                try std.testing.expectError(error.InvalidDocument, d.parse(a, wire, &.{}));
            }
        }
    }
    try std.testing.expectError(error.InvalidDocument, d.parse(a, "[[\"Uint8Array\",0]]", &.{}));
    try std.testing.expectError(error.InvalidDocument, d.parse(a, "[[\"Uint8Array\",1],[\"Uint8Array\",0]]", &.{}));
}

const Revival = struct {
    result: ?d.Value = null,
    returned: ?d.Value = null,
    length: usize = 16,
    calls: usize = 0,
    fn revive(ctx: ?*anyopaque, g: *d.Graph, _: d.Value) d.Error!d.Value {
        const s: *Revival = @ptrCast(@alignCast(ctx.?));
        s.calls += 1;
        const zeros: [16]u8 = @splat(0);
        const result = s.result orelse try g.arrayBuffer(zeros[0..s.length]);
        s.returned = result;
        return result;
    }
};
fn identity(_: ?*anyopaque, _: *d.Graph, v: d.Value) d.Error!d.Value {
    return v;
}
fn countedIdentity(ctx: ?*anyopaque, _: *d.Graph, v: d.Value) d.Error!d.Value {
    const calls: *usize = @ptrCast(@alignCast(ctx.?));
    calls.* += 1;
    return v;
}
// Source: v5.9.4/test/parse-operations.test.js "view backing buffers".
test "every view validates revived genuine, empty, array-like and cached buffers" {
    for (0..kinds.len + 1) |i| {
        const tag = if (i == kinds.len) "DataView" else @tagName(kinds[i]);
        for ([_][]const u8{ "", ",0,1" }) |bounds| {
            for ([_][]const u8{ "1024", "[-7,1024]", "{\"length\":3},1024" }) |payload| {
                var calls: usize = 0;
                const wire = try a.print("[[\"{s}\",1{s}],[\"ArrayBuffer\",2],{s}]", .{ tag, bounds, payload });
                defer a.free(wire);
                try std.testing.expectError(error.InvalidDocument, d.parse(a, wire, &.{.{ .name = "ArrayBuffer", .context = &calls, .revive = countedIdentity }}));
                try std.testing.expectEqual(@as(usize, 1), calls);
            }
        }
        for ([_][]const u8{ "", ",8,1" }) |bounds| {
            var state = Revival{};
            const wire = try a.print("[[\"{s}\",1{s}],[\"ArrayBuffer\",2],null]", .{ tag, bounds });
            defer a.free(wire);
            var r = try d.parse(a, wire, &.{.{ .name = "ArrayBuffer", .context = &state, .revive = Revival.revive }});
            defer r.deinit();
            const v = try r.graph.node(r.value);
            const b = if (v == .typed_array) v.typed_array.buffer else v.data_view.buffer;
            try std.testing.expect(d.equal(b, state.returned.?));
            try std.testing.expectEqual(if (bounds.len == 0) @as(usize, 0) else 8, if (v == .typed_array) v.typed_array.byte_offset else v.data_view.byte_offset);
            try std.testing.expectEqual(@as(usize, 16), (try r.graph.node(b)).array_buffer.len);
            try std.testing.expectEqual(@as(usize, 1), state.calls);
            const w = if (i == kinds.len) 1 else kinds[i].bytesPerElement();
            try std.testing.expectEqual(if (bounds.len == 0) @as(usize, 16) else w, (try r.graph.viewBytes(r.value)).len);
        }
        var empty = Revival{ .length = 0 };
        const wire = try a.print("[[\"{s}\",1],[\"ArrayBuffer\",2],null]", .{tag});
        defer a.free(wire);
        var e = try d.parse(a, wire, &.{.{ .name = "ArrayBuffer", .context = &empty, .revive = Revival.revive }});
        defer e.deinit();
        try std.testing.expectEqual(@as(usize, 0), (try e.graph.viewBytes(e.value)).len);
    }
    for ([_][]const u8{ "null", "-1", "\"1024\"", "{}", "[\"Uint8Array\",3]" }) |payload| {
        const wire = try a.print("[[\"Uint8Array\",1],[\"ArrayBuffer\",2],{s},[\"ArrayBuffer\",\"AA==\"]]", .{payload});
        defer a.free(wire);
        try std.testing.expectError(error.InvalidDocument, d.parse(a, wire, &.{.{ .name = "ArrayBuffer", .revive = identity }}));
    }
    try std.testing.expectError(error.InvalidDocument, d.parse(a, "[[1,3],[\"ArrayBuffer\",2],1024,[\"Uint8Array\",1]]", &.{.{ .name = "ArrayBuffer", .revive = identity }}));
    try std.testing.expectError(error.InvalidDocument, d.parse(a, "[[\"Uint8Array\",1],[\"ArrayBuffer\",0]]", &.{.{ .name = "ArrayBuffer", .revive = identity }}));
    // A view-tag override runs before the built-in backing-store guard.
    var override = try d.parse(a, "[[\"Uint8Array\",1],42]", &.{.{ .name = "Uint8Array", .revive = identity }});
    defer override.deinit();
    try std.testing.expectEqual(@as(f64, 42), override.value.number);
    var state = Revival{};
    var cached = try d.parse(a, "[[1,3,4],[\"ArrayBuffer\",2],null,[\"Uint8Array\",1],[\"DataView\",1,1,3]]", &.{.{ .name = "ArrayBuffer", .context = &state, .revive = Revival.revive }});
    defer cached.deinit();
    const b = (try cached.graph.arrayGet(cached.value, 0)).?;
    const v = (try cached.graph.node((try cached.graph.arrayGet(cached.value, 1)).?)).typed_array;
    const dv = (try cached.graph.node((try cached.graph.arrayGet(cached.value, 2)).?)).data_view;
    try std.testing.expect(d.equal(b, v.buffer) and d.equal(b, dv.buffer));
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    var bad_handle = Revival{ .result = .{ .ref = @fromBackingInt(@intCast(999999)) } };
    try std.testing.expectError(error.InvalidHandle, d.parse(a, "[[\"Uint8Array\",1],[\"ArrayBuffer\",2],null]", &.{.{ .name = "ArrayBuffer", .context = &bad_handle, .revive = Revival.revive }}));
    var untouched = Revival{};
    try std.testing.expectError(error.InvalidDocument, d.parse(a, "[[\"Uint8Array\",1],[\"Custom\",2],null]", &.{.{ .name = "Custom", .context = &untouched, .revive = Revival.revive }}));
    try std.testing.expectEqual(@as(usize, 0), untouched.calls);
}

fn allocationPaths(gpa: std.mem.Allocator) !void {
    var g = d.Graph.init(gpa);
    defer g.deinit();
    const root = try g.array(4);
    const copy = try g.uint8ArrayCopy(&.{ 1, 2, 3 });
    const b = try g.arrayBuffer(&.{ 0, 1, 2, 3, 4, 5, 6, 7 });
    try g.arrayPut(root, 0, copy);
    try g.arrayPut(root, 1, try g.typedArray(.Float16Array, b, 2, 2));
    try g.arrayPut(root, 2, try g.dataView(b, 1, 3));
    try g.arrayPut(root, 3, root);
    const bytes = try d.stringify(gpa, &g, root, &.{});
    defer gpa.free(bytes);
    var parsed = try d.parse(gpa, bytes, &.{});
    defer parsed.deinit();
    var state = Revival{};
    var revived = try d.parse(gpa, "[[\"Float64Array\",1,8,1],[\"ArrayBuffer\",2],null]", &.{.{ .name = "ArrayBuffer", .context = &state, .revive = Revival.revive }});
    defer revived.deinit();
}
test "binary ownership and callbacks survive every allocation failure" {
    const deterministic = std.mem.Allocator{ .ptr = a.ptr, .vtable = &.{ .alloc = a.vtable.alloc, .resize = std.mem.Allocator.noResize, .remap = std.mem.Allocator.noRemap, .free = a.vtable.free } };
    try std.testing.checkAllAllocationFailures(deterministic, allocationPaths, .{});
}
