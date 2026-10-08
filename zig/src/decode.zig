const std = @import("std");
const d = @import("root.zig");
const p = @import("primitives.zig");
const w = @import("wire.zig");
/// Input is borrowed only during parsing. The returned graph owns every retained
/// byte. Revivers may observe partial payloads and be invoked more than once.
pub fn parse(gpa: std.mem.Allocator, bytes: []const u8, revivers: []const d.Reviver) d.Error!d.ParseResult {
    var temp: std.heap.ArenaAllocator = .init(gpa);
    defer temp.deinit();
    const a = temp.allocator();
    const tape = try w.scan(a, bytes);
    var graph = d.Graph.init(gpa);
    errdefer graph.deinit();
    var dec = Decoder{ .a = a, .graph = &graph, .revivers = revivers, .tape = tape };
    const root = tape.atoms[0];
    var value: d.Value = undefined;
    if (root.token == .number or root.token == .allocated_number) {
        value = try dec.hydrate(try tape.reference(0), true, 0);
    } else {
        if (root.token != .array_begin or root.children == 0) return error.InvalidDocument;
        try dec.values.ensureTotalCapacity(a, root.children);
        try dec.cache.appendNTimes(a, null, root.children);
        try dec.pending.appendNTimes(a, false, root.children);
        var pos: usize = 1;
        while (pos < root.end) : (pos = tape.next(pos)) dec.values.appendAssumeCapacity(pos);
        value = try dec.hydrate(0, false, 0);
    }
    return .{ .graph = graph, .value = value };
}
fn constructionError(err: d.Error) d.Error {
    return switch (err) {
        error.UnsupportedValue, error.UnsupportedString, error.InvalidType => error.InvalidDocument,
        else => err,
    };
}
const Property = struct { key: []const u8, token: usize, order: usize };
fn propertyLess(_: void, a: Property, b: Property) bool {
    const ai = d.arrayIndex(a.key);
    const bi = d.arrayIndex(b.key);
    if (ai) |i| return if (bi) |j| i < j else true;
    if (bi != null) return false;
    return a.order < b.order;
}
const Decoder = struct {
    a: std.mem.Allocator,
    graph: *d.Graph,
    revivers: []const d.Reviver,
    tape: w.Tape,
    values: std.ArrayList(usize) = .empty,
    cache: std.ArrayList(?d.Value) = .empty,
    pending: std.ArrayList(bool) = .empty,
    fn edge(self: *Decoder, token: usize, depth: usize) d.Error!d.Value {
        return self.hydrate(try self.tape.reference(token), false, depth + 1);
    }
    fn remember(self: *Decoder, i: usize, v: d.Value) d.Value {
        self.cache.items[i] = v;
        return v;
    }
    fn child(self: *Decoder, token: usize, n: usize) d.Error!usize {
        return self.tape.child(token, n);
    }
    fn bound(self: *Decoder, token: usize) d.Error!usize {
        const f = try self.tape.number(token);
        if (!std.math.isFinite(f) or @trunc(f) != f or f < 0 or f > 9007199254740991.0 or f > @as(f64, @floatFromInt(std.math.maxInt(usize)))) return error.InvalidDocument;
        return @intFromFloat(f);
    }
    fn hydrate(self: *Decoder, index: i64, standalone: bool, depth: usize) d.Error!d.Value {
        switch (index) {
            -1 => return .undefined,
            -3 => return .{ .number = std.math.nan(f64) },
            -4 => return .{ .number = std.math.inf(f64) },
            -5 => return .{ .number = -std.math.inf(f64) },
            -6 => return .{ .number = -0.0 },
            else => {},
        }
        if (standalone or index < 0 or index >= self.values.items.len) return error.InvalidDocument;
        const i: usize = @intCast(index);
        if (self.cache.items[i]) |v| return v;
        if (depth >= d.max_depth) return error.DepthLimit;
        const token = self.values.items[i];
        const atom = self.tape.atoms[token];
        const value: d.Value = switch (atom.token) {
            .null => .null,
            .true => .{ .boolean = true },
            .false => .{ .boolean = false },
            .string, .allocated_string => |s| try self.graph.string(s),
            .number, .allocated_number => .{ .number = try self.tape.number(token) },
            .object_begin => blk: {
                const target = self.remember(i, try self.graph.object(false));
                var properties: std.ArrayList(Property) = .empty;
                var lookup: std.StringHashMapUnmanaged(usize) = .empty;
                try properties.ensureTotalCapacity(self.a, atom.children / 2);
                var pos = token + 1;
                while (pos < atom.end) {
                    const key = try self.tape.string(pos);
                    pos += 1;
                    if (std.mem.eql(u8, key, "__proto__")) return error.InvalidDocument;
                    if (lookup.get(key)) |old| {
                        properties.items[old].token = pos;
                    } else {
                        try lookup.put(self.a, key, properties.items.len);
                        properties.appendAssumeCapacity(.{ .key = key, .token = pos, .order = properties.items.len });
                    }
                    pos = self.tape.next(pos);
                }
                std.mem.sort(Property, properties.items, {}, propertyLess);
                for (properties.items) |prop| try self.graph.put(target, prop.key, try self.edge(prop.token, depth));
                break :blk target;
            },
            .array_begin => blk: {
                const first = if (atom.children > 0) token + 1 else atom.end;
                if (atom.children > 0 and (self.tape.atoms[first].token == .string or self.tape.atoms[first].token == .allocated_string)) {
                    const tag = try self.tape.string(first);
                    for (self.revivers) |reviver| if (std.mem.eql(u8, reviver.name, tag)) {
                        const payload_token = try self.child(token, 1);
                        const payload_kind = self.tape.atoms[payload_token].token;
                        var pi: i64 = undefined;
                        if (payload_kind == .number or payload_kind == .allocated_number) {
                            pi = try self.tape.reference(payload_token);
                        } else {
                            pi = @intCast(self.values.items.len);
                            try self.values.append(self.a, payload_token);
                            try self.cache.append(self.a, null);
                            try self.pending.append(self.a, false);
                        }
                        if (pi >= 0 and pi < self.cache.items.len) {
                            const idx: usize = @intCast(pi);
                            if (self.cache.items[idx]) |payload| {
                                const revived = try reviver.revive(reviver.context, self.graph, payload);
                                try self.graph.validate(revived);
                                break :blk revived;
                            }
                            if (self.pending.items[idx]) return error.InvalidDocument;
                            self.pending.items[idx] = true;
                        }
                        const payload = try self.hydrate(pi, false, depth + 1);
                        const revived = try reviver.revive(reviver.context, self.graph, payload);
                        try self.graph.validate(revived);
                        if (pi >= 0 and pi < self.pending.items.len) self.pending.items[@intCast(pi)] = false;
                        break :blk revived;
                    };
                    if (std.mem.eql(u8, tag, "Date")) {
                        if (atom.children != 2) return error.InvalidDocument;
                        break :blk try self.graph.date(try p.parseDate(try self.tape.string(try self.child(token, 1))));
                    }
                    if (std.mem.eql(u8, tag, "BigInt")) {
                        if (atom.children != 2) return error.InvalidDocument;
                        break :blk self.graph.bigint(try self.tape.string(try self.child(token, 1))) catch |err| return constructionError(err);
                    }
                    if (std.mem.eql(u8, tag, "RegExp")) {
                        if (atom.children != 2 and atom.children != 3) return error.InvalidDocument;
                        break :blk self.graph.regexp(try self.tape.string(try self.child(token, 1)), if (atom.children == 3) try self.tape.string(try self.child(token, 2)) else "") catch |err| return constructionError(err);
                    }
                    if (std.mem.eql(u8, tag, "ArrayBuffer")) {
                        if (atom.children != 2) return error.InvalidDocument;
                        const encoded = try self.tape.string(try self.child(token, 1));
                        const n = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return error.InvalidDocument;
                        const buf = try self.a.alloc(u8, n);
                        std.base64.standard.Decoder.decode(buf, encoded) catch return error.InvalidDocument;
                        const canonical = try self.a.alloc(u8, std.base64.standard.Encoder.calcSize(n));
                        _ = std.base64.standard.Encoder.encode(canonical, buf);
                        if (!std.mem.eql(u8, canonical, encoded)) return error.InvalidDocument;
                        break :blk try self.graph.arrayBuffer(buf);
                    }
                    if (std.mem.eql(u8, tag, "Object")) {
                        if (atom.children != 2) return error.InvalidDocument;
                        const wrapped = try self.tape.reference(try self.child(token, 1));
                        if (wrapped >= 0) {
                            if (wrapped >= self.values.items.len) return error.InvalidDocument;
                            const raw = self.values.items[@intCast(wrapped)];
                            const kind = self.tape.atoms[raw].token;
                            if (kind == .object_begin or kind == .null) return error.InvalidDocument;
                            if (kind == .array_begin) {
                                const tag_token = try self.child(raw, 0);
                                const raw_tag = self.tape.string(tag_token) catch return error.InvalidDocument;
                                if (!std.mem.eql(u8, raw_tag, "BigInt")) return error.InvalidDocument;
                            }
                        }
                        const primitive = try self.hydrate(wrapped, false, depth + 1);
                        // JS Object(reference) preserves the original reference.
                        if (primitive == .ref) break :blk primitive;
                        if (primitive == .undefined or primitive == .null) break :blk try self.graph.object(false);
                        break :blk try self.graph.boxed(primitive);
                    }
                    if (std.mem.eql(u8, tag, "Set")) {
                        const target = self.remember(i, try self.graph.set());
                        var pos = first + 1;
                        while (pos < atom.end) : (pos = self.tape.next(pos)) try self.graph.setAdd(target, try self.edge(pos, depth));
                        break :blk target;
                    }
                    if (std.mem.eql(u8, tag, "Map") or std.mem.eql(u8, tag, "null")) {
                        if (atom.children % 2 != 1) return error.InvalidDocument;
                        const map = std.mem.eql(u8, tag, "Map");
                        const target = self.remember(i, if (map) try self.graph.map() else try self.graph.object(true));
                        var pos = first + 1;
                        while (pos < atom.end) {
                            const val_token = self.tape.next(pos);
                            if (map) {
                                const key = try self.edge(pos, depth);
                                const val = try self.edge(val_token, depth);
                                try self.graph.mapPut(target, key, val);
                            } else {
                                const key = try self.tape.string(pos);
                                if (std.mem.eql(u8, key, "__proto__")) return error.InvalidDocument;
                                try self.graph.put(target, key, try self.edge(val_token, depth));
                            }
                            pos = self.tape.next(val_token);
                        }
                        break :blk target;
                    }
                    const typed_kind = std.meta.stringToEnum(d.TypedArrayKind, tag);
                    if (typed_kind != null or std.mem.eql(u8, tag, "DataView")) {
                        if (atom.children < 2 or atom.children > 4) return error.InvalidDocument;
                        const bi = try self.tape.reference(try self.child(token, 1));
                        if (bi < 0 or bi >= self.values.items.len) return error.InvalidDocument;
                        const raw = self.values.items[@intCast(bi)];
                        if (self.tape.atoms[raw].token != .array_begin or self.tape.atoms[raw].children == 0) return error.InvalidDocument;
                        const raw_tag = self.tape.string(try self.child(raw, 0)) catch return error.InvalidDocument;
                        // Guard raw slots before hydration or callbacks: array-like
                        // values and view cycles can never become backing stores.
                        if (!std.mem.eql(u8, raw_tag, "ArrayBuffer")) return error.InvalidDocument;
                        const buffer = try self.hydrate(bi, false, depth + 1);
                        const backing = self.graph.node(buffer) catch |err| return constructionError(err);
                        if (backing != .array_buffer) return error.InvalidDocument;
                        const width = if (typed_kind) |kind| kind.bytesPerElement() else 1;
                        const offset = if (atom.children >= 3) try self.bound(try self.child(token, 2)) else 0;
                        if (offset > backing.array_buffer.len or offset % width != 0) return error.InvalidDocument;
                        const remaining = backing.array_buffer.len - offset;
                        if (atom.children < 4 and remaining % width != 0) return error.InvalidDocument;
                        const length = if (atom.children == 4) try self.bound(try self.child(token, 3)) else remaining / width;
                        break :blk (if (typed_kind) |kind| self.graph.typedArray(kind, buffer, offset, length) else self.graph.dataView(buffer, offset, length)) catch |err| return constructionError(err);
                    }
                    for ([_][]const u8{ "URL", "URLSearchParams", "Temporal.Duration", "Temporal.Instant", "Temporal.PlainDate", "Temporal.PlainTime", "Temporal.PlainDateTime", "Temporal.PlainMonthDay", "Temporal.PlainYearMonth", "Temporal.ZonedDateTime" }) |excluded| if (std.mem.eql(u8, tag, excluded)) return error.UnsupportedValue;
                    return error.InvalidDocument;
                }
                const sparse = atom.children > 0 and ((self.tape.atoms[first].token == .number or self.tape.atoms[first].token == .allocated_number) and (try self.tape.number(first)) == -7);
                if (sparse) {
                    if (atom.children < 2 or atom.children % 2 != 0) return error.InvalidDocument;
                    const len = try self.tape.reference(try self.child(token, 1));
                    if (len < 0 or len > std.math.maxInt(u32)) return error.InvalidDocument;
                    const target = self.remember(i, try self.graph.array(@intCast(len)));
                    var pos = try self.child(token, 1);
                    pos = self.tape.next(pos);
                    while (pos < atom.end) {
                        const idx = try self.tape.reference(pos);
                        if (idx < 0 or idx >= len) return error.InvalidDocument;
                        const val_token = self.tape.next(pos);
                        try self.graph.arrayPut(target, @intCast(idx), try self.edge(val_token, depth));
                        pos = self.tape.next(val_token);
                    }
                    break :blk target;
                }
                if (atom.children > std.math.maxInt(u32)) return error.InvalidDocument;
                const target = self.remember(i, try self.graph.array(@intCast(atom.children)));
                var pos = token + 1;
                var idx: u32 = 0;
                while (pos < atom.end) : (idx += 1) {
                    if (try self.tape.reference(pos) != -2) try self.graph.arrayPut(target, idx, try self.edge(pos, depth));
                    pos = self.tape.next(pos);
                }
                break :blk target;
            },
            else => return error.InvalidDocument,
        };
        return self.remember(i, value);
    }
};
