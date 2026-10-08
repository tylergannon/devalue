const std = @import("std");
const d = @import("root.zig");
const p = @import("primitives.zig");
const Context = d.ValueContext;
pub fn truthy(v: d.Value) bool {
    return switch (v) {
        .null, .undefined => false,
        .boolean => |b| b,
        .number => |f| f != 0 and !std.math.isNan(f),
        .string => |s| s.len != 0,
        .bigint => |s| !std.mem.eql(u8, s, "0"),
        .ref => true,
    };
}
fn sentinel(v: d.Value) ?i64 {
    if (v == .undefined) return -1;
    if (v == .number) {
        if (std.math.isNan(v.number)) return -3;
        if (std.math.isInf(v.number)) return if (v.number > 0) -4 else -5;
        if (v.number == 0 and std.math.signbit(v.number)) return -6;
    }
    return null;
}
/// Returned bytes belong to gpa; caller frees them. The graph remains owned by
/// the caller. Reducers may allocate replacement nodes, but must not mutate
/// values/containers currently being traversed. Errors never transfer ownership.
pub fn stringify(gpa: std.mem.Allocator, graph: *d.Graph, value: d.Value, reducers: []const d.Reducer) d.Error![]u8 {
    for (reducers) |r| {
        if (!std.unicode.utf8ValidateSlice(r.name)) return error.InvalidReducerName;
        for (r.name) |c| if (c < 32 or c == '"' or c == '\\') return error.InvalidReducerName;
    }
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var e = Encoder{ .a = arena.allocator(), .graph = graph, .reducers = reducers };
    const root = try e.flatten(value, 0);
    var out: p.Buffer = .empty;
    errdefer out.deinit(gpa);
    if (root < 0) {
        try p.integer(&out, gpa, root);
    } else {
        try out.append(gpa, '[');
        for (e.slots.items, 0..) |slot, i| {
            if (i > 0) try out.append(gpa, ',');
            try out.appendSlice(gpa, slot);
        }
        try out.append(gpa, ']');
    }
    return out.toOwnedSlice(gpa);
}
const Encoder = struct {
    a: std.mem.Allocator,
    graph: *d.Graph,
    reducers: []const d.Reducer,
    slots: std.ArrayList([]const u8) = .empty,
    indices: std.HashMapUnmanaged(d.Value, i64, Context, 80) = .empty,
    fn flatten(self: *Encoder, v: d.Value, depth: usize) d.Error!i64 {
        try self.graph.validate(v);
        if (sentinel(v)) |n| return n;
        if (self.indices.getContext(v, .{ .graph = self.graph })) |n| return n;
        if (depth >= d.max_depth) return error.DepthLimit;
        const index: i64 = @intCast(self.slots.items.len);
        try self.slots.append(self.a, "");
        try self.indices.putContext(self.a, v, index, .{ .graph = self.graph });
        var b: p.Buffer = .empty;
        for (self.reducers) |r| {
            if (try r.reduce(r.context, self.graph, v)) |replacement| {
                try self.graph.validate(replacement);
                if (!truthy(replacement)) continue;
                const n = try self.flatten(replacement, depth + 1);
                try p.text(&b, self.a, "[\"");
                try p.text(&b, self.a, r.name);
                try p.text(&b, self.a, "\",");
                try p.integer(&b, self.a, n);
                try p.text(&b, self.a, "]");
                self.slots.items[@intCast(index)] = b.items;
                return index;
            }
        }
        switch (v) {
            .null => try p.text(&b, self.a, "null"),
            .undefined => unreachable,
            .boolean => |yes| try p.text(&b, self.a, if (yes) "true" else "false"),
            .number => |f| try p.number(&b, self.a, f),
            .string => |s| try p.quote(&b, self.a, s),
            .bigint => |s| {
                try p.text(&b, self.a, "[\"BigInt\",");
                try p.quote(&b, self.a, s);
                try p.text(&b, self.a, "]");
            },
            .ref => switch (try self.graph.node(v)) {
                .object => |obj| {
                    try p.text(&b, self.a, if (obj.null_proto) "[\"null\"" else "{");
                    for (obj.properties.items, 0..) |prop, i| {
                        if (obj.null_proto or i > 0) try p.text(&b, self.a, ",");
                        try p.quote(&b, self.a, prop.key);
                        try p.text(&b, self.a, if (obj.null_proto) "," else ":");
                        try p.integer(&b, self.a, try self.flatten(prop.value, depth + 1));
                    }
                    try p.text(&b, self.a, if (obj.null_proto) "]" else "}");
                },
                .array => |arr| {
                    var num: [16]u8 = undefined;
                    const digits = (std.fmt.bufPrint(&num, "{d}", .{arr.length}) catch unreachable).len;
                    const population: u64 = arr.elements.items.len;
                    const sparse = (@as(u64, arr.length) - population) * 3 > 4 + digits + population * (digits + 1);
                    if (sparse) {
                        try p.text(&b, self.a, "[-7,");
                        try p.integer(&b, self.a, arr.length);
                        for (arr.elements.items) |e| {
                            try p.text(&b, self.a, ",");
                            try p.integer(&b, self.a, e.index);
                            try self.edge(&b, e.value, depth);
                        }
                    } else {
                        try p.text(&b, self.a, "[");
                        var pos: usize = 0;
                        var i: u64 = 0;
                        while (i < arr.length) : (i += 1) {
                            if (i > 0) try p.text(&b, self.a, ",");
                            if (pos < arr.elements.items.len and arr.elements.items[pos].index == i) {
                                try p.integer(&b, self.a, try self.flatten(arr.elements.items[pos].value, depth + 1));
                                pos += 1;
                            } else try p.text(&b, self.a, "-2");
                        }
                    }
                    try p.text(&b, self.a, "]");
                },
                .map => |map| {
                    try p.text(&b, self.a, "[\"Map\"");
                    for (map.entries.items) |e| {
                        try self.edge(&b, e.key, depth);
                        try self.edge(&b, e.value, depth);
                    }
                    try p.text(&b, self.a, "]");
                },
                .set => |set| {
                    try p.text(&b, self.a, "[\"Set\"");
                    for (set.values.items) |e| try self.edge(&b, e, depth);
                    try p.text(&b, self.a, "]");
                },
                .date => |ms| {
                    var buf: [27]u8 = undefined;
                    try p.text(&b, self.a, "[\"Date\",");
                    try p.quote(&b, self.a, p.dateString(&buf, ms));
                    try p.text(&b, self.a, "]");
                },
                .regexp => |re| {
                    try p.text(&b, self.a, "[\"RegExp\",");
                    try p.quote(&b, self.a, re.source);
                    if (re.flags.len > 0) {
                        try p.text(&b, self.a, ",");
                        try p.quote(&b, self.a, re.flags);
                    }
                    try p.text(&b, self.a, "]");
                },
                .array_buffer => |bytes| {
                    const n = std.base64.standard.Encoder.calcSize(bytes.len);
                    const buf = try self.a.alloc(u8, n);
                    _ = std.base64.standard.Encoder.encode(buf, bytes);
                    try p.text(&b, self.a, "[\"ArrayBuffer\",");
                    try p.quote(&b, self.a, buf);
                    try p.text(&b, self.a, "]");
                },
                .typed_array => |view| try self.writeView(&b, @tagName(view.kind), view.buffer, view.byte_offset, view.length, view.kind.bytesPerElement(), depth),
                .data_view => |view| try self.writeView(&b, "DataView", view.buffer, view.byte_offset, view.byte_length, 1, depth),
                .boxed => |unboxed| {
                    try p.text(&b, self.a, "[\"Object\"");
                    try self.edge(&b, unboxed, depth);
                    try p.text(&b, self.a, "]");
                },
            },
        }
        self.slots.items[@intCast(index)] = b.items;
        return index;
    }
    fn edge(self: *Encoder, b: *p.Buffer, v: d.Value, depth: usize) d.Error!void {
        try p.text(b, self.a, ",");
        try p.integer(b, self.a, try self.flatten(v, depth + 1));
    }
    fn writeView(self: *Encoder, b: *p.Buffer, tag: []const u8, buffer: d.Value, offset: usize, length: usize, width: usize, depth: usize) d.Error!void {
        const n = try self.graph.node(buffer);
        if (n != .array_buffer) return error.InvalidType;
        const size = n.array_buffer.len;
        if (offset > size or offset % width != 0 or length > (size - offset) / width) return error.InvalidType;
        try p.text(b, self.a, "[");
        try p.quote(b, self.a, tag);
        try self.edge(b, buffer, depth);
        if (length * width != size) {
            try p.text(b, self.a, ",");
            try p.integer(b, self.a, offset);
            try p.text(b, self.a, ",");
            try p.integer(b, self.a, length);
        }
        try p.text(b, self.a, "]");
    }
};
