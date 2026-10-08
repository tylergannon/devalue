const std = @import("std");
pub const upstream_version = "5.9.4";
pub const Error = error{ OutOfMemory, InvalidDocument, UnsupportedValue, UnsupportedString, InvalidHandle, InvalidType, InvalidReducerName, CallbackError, DepthLimit };
pub const Handle = enum(u32) { _ };
pub const Value = union(enum) {
    null,
    undefined,
    boolean: bool,
    number: f64,
    string: []const u8,
    bigint: []const u8,
    ref: Handle,
};
pub const Property = struct { key: []const u8, value: Value, order: usize = 0 };
pub const Element = struct { index: u32, value: Value };
pub const Entry = struct { key: Value, value: Value };
pub const Object = struct { null_proto: bool, properties: std.ArrayList(Property) = .empty, lookup: std.StringHashMapUnmanaged(usize) = .empty, next_order: usize = 0, ordered: bool = true };
pub const Array = struct { length: u32, elements: std.ArrayList(Element) = .empty, lookup: std.AutoHashMapUnmanaged(u32, usize) = .empty, ordered: bool = true };
pub const RegExp = struct { source: []const u8, flags: []const u8 };
pub const Map = struct { entries: std.ArrayList(Entry) = .empty, lookup: std.HashMapUnmanaged(Value, usize, ValueContext, 80) = .empty };
pub const Set = struct { values: std.ArrayList(Value) = .empty, lookup: std.HashMapUnmanaged(Value, void, ValueContext, 80) = .empty };
pub const ByteKey = struct { ptr: usize, len: usize };
const ByteInfo = struct { hash: u64, bigint: bool };
pub fn byteKey(bytes: []const u8) ByteKey {
    return .{ .ptr = @intFromPtr(bytes.ptr), .len = bytes.len };
}
pub const ValueContext = struct {
    graph: *const Graph,
    pub fn hash(self: @This(), v: Value) u64 {
        const tag: u64 = @backingInt(std.meta.activeTag(v));
        const h: u64 = switch (v) {
            .null, .undefined => 0,
            .boolean => |b| @intFromBool(b),
            .number => |f| if (f == 0) 0 else if (std.math.isNan(f)) 0x7ff8000000000000 else @bitCast(f),
            .ref => |r| @backingInt(r),
            .string, .bigint => |bytes| if (self.graph.bytes.get(byteKey(bytes))) |info| info.hash else std.hash.Wyhash.hash(0, bytes),
        };
        return std.hash.Wyhash.hash(tag, std.mem.asBytes(&h));
    }
    pub fn eql(_: @This(), a: Value, b: Value) bool {
        return equal(a, b);
    }
};
fn propertyLess(_: void, a: Property, b: Property) bool {
    const ai = arrayIndex(a.key);
    const bi = arrayIndex(b.key);
    if (ai) |i| return if (bi) |j| i < j else true;
    if (bi != null) return false;
    return a.order < b.order;
}
fn elementLess(_: void, a: Element, b: Element) bool {
    return a.index < b.index;
}
pub const Node = union(enum) {
    object: Object,
    array: Array,
    map: Map,
    set: Set,
    date: i64,
    regexp: RegExp,
    array_buffer: []const u8,
    boxed: Value,
};

/// Owns all values made by its constructors, including parsed strings. Never copy
/// a live Graph. Handles belong to this graph and survive growth. Returned views
/// must not be retained across mutation. Release the graph once with deinit.
pub const Graph = struct {
    arena: std.heap.ArenaAllocator,
    nodes: std.ArrayList(Node) = .empty,
    bytes: std.AutoHashMapUnmanaged(ByteKey, ByteInfo) = .empty,

    pub fn init(gpa: std.mem.Allocator) Graph {
        return .{ .arena = .init(gpa) };
    }
    pub fn deinit(self: *Graph) void {
        self.arena.deinit();
        self.* = undefined;
    }
    pub fn allocator(self: *Graph) std.mem.Allocator {
        return self.arena.allocator();
    }
    pub fn string(self: *Graph, bytes: []const u8) Error!Value {
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.UnsupportedString;
        const copy = try self.allocator().dupe(u8, bytes);
        try self.bytes.put(self.allocator(), byteKey(copy), .{ .hash = std.hash.Wyhash.hash(0, copy), .bigint = false });
        return .{ .string = copy };
    }
    pub fn bigint(self: *Graph, digits: []const u8) Error!Value {
        if (!canonicalBigInt(digits)) return error.UnsupportedValue;
        const copy = try self.allocator().dupe(u8, digits);
        try self.bytes.put(self.allocator(), byteKey(copy), .{ .hash = std.hash.Wyhash.hash(0, copy), .bigint = true });
        return .{ .bigint = copy };
    }
    fn add(self: *Graph, new_node: Node) Error!Value {
        if (self.nodes.items.len >= std.math.maxInt(u32)) return error.UnsupportedValue;
        const handle: Handle = @fromBackingInt(@intCast(@as(u32, @intCast(self.nodes.items.len))));
        try self.nodes.append(self.allocator(), new_node);
        return .{ .ref = handle };
    }
    pub fn object(self: *Graph, null_proto: bool) Error!Value {
        return self.add(.{ .object = .{ .null_proto = null_proto } });
    }
    pub fn array(self: *Graph, length: u32) Error!Value {
        return self.add(.{ .array = .{ .length = length } });
    }
    pub fn map(self: *Graph) Error!Value {
        return self.add(.{ .map = .{} });
    }
    pub fn set(self: *Graph) Error!Value {
        return self.add(.{ .set = .{} });
    }
    pub fn date(self: *Graph, millis: i64) Error!Value {
        if (millis < -8640000000000000 or millis > 8640000000000000) return error.UnsupportedValue;
        return self.add(.{ .date = millis });
    }
    pub fn regexp(self: *Graph, source: []const u8, flags: []const u8) Error!Value {
        if (!std.unicode.utf8ValidateSlice(source)) return error.UnsupportedString;
        var canonical: [8]u8 = undefined;
        const len = try canonicalFlags(flags, &canonical);
        const a = self.allocator();
        return self.add(.{ .regexp = .{ .source = try a.dupe(u8, source), .flags = try a.dupe(u8, canonical[0..len]) } });
    }
    pub fn arrayBuffer(self: *Graph, bytes: []const u8) Error!Value {
        return self.add(.{ .array_buffer = try self.allocator().dupe(u8, bytes) });
    }
    pub fn boxed(self: *Graph, value: Value) Error!Value {
        switch (value) {
            .boolean, .number, .string, .bigint => {},
            else => return error.UnsupportedValue,
        }
        try self.validate(value);
        return self.add(.{ .boxed = value });
    }
    pub fn validate(self: *const Graph, value: Value) Error!void {
        switch (value) {
            .ref => |h| {
                if (@backingInt(h) >= self.nodes.items.len) return error.InvalidHandle;
            },
            .string => |s| {
                if (!self.bytes.contains(byteKey(s)) and !std.unicode.utf8ValidateSlice(s)) return error.UnsupportedString;
            },
            .bigint => |s| {
                if (!(if (self.bytes.get(byteKey(s))) |info| info.bigint else false) and !canonicalBigInt(s)) return error.UnsupportedValue;
            },
            else => {},
        }
    }
    fn rawNode(self: *const Graph, value: Value) Error!Node {
        if (value != .ref) return error.InvalidType;
        try self.validate(value);
        return self.nodes.items[@backingInt(value.ref)];
    }
    pub fn node(self: *Graph, value: Value) Error!Node {
        const n = try self.nodePtr(value);
        switch (n.*) {
            .object => |*obj| if (!obj.ordered) {
                std.mem.sort(Property, obj.properties.items, {}, propertyLess);
                for (obj.properties.items, 0..) |prop, i| obj.lookup.getPtr(prop.key).?.* = i;
                obj.ordered = true;
            },
            .array => |*arr| if (!arr.ordered) {
                std.mem.sort(Element, arr.elements.items, {}, elementLess);
                for (arr.elements.items, 0..) |element, i| arr.lookup.getPtr(element.index).?.* = i;
                arr.ordered = true;
            },
            else => {},
        }
        return n.*;
    }
    fn nodePtr(self: *Graph, value: Value) Error!*Node {
        if (value != .ref) return error.InvalidType;
        try self.validate(value);
        return &self.nodes.items[@backingInt(value.ref)];
    }
    /// Properties enumerate in JS order: array-index keys first, numerically,
    /// followed by other keys in insertion order. __proto__ is not supported.
    pub fn put(self: *Graph, target: Value, key: []const u8, value: Value) Error!void {
        try self.validate(value);
        if (!std.unicode.utf8ValidateSlice(key)) return error.UnsupportedString;
        if (std.mem.eql(u8, key, "__proto__")) return error.UnsupportedValue;
        const n = try self.nodePtr(target);
        if (n.* != .object) return error.InvalidType;
        if (n.object.lookup.get(key)) |i| {
            n.object.properties.items[i].value = value;
            return;
        }
        const a = self.allocator();
        try n.object.properties.ensureUnusedCapacity(a, 1);
        try n.object.lookup.ensureUnusedCapacity(a, 1);
        const copy = try a.dupe(u8, key);
        if (n.object.next_order == std.math.maxInt(usize)) return error.UnsupportedValue;
        const i = n.object.properties.items.len;
        n.object.properties.appendAssumeCapacity(.{ .key = copy, .value = value, .order = n.object.next_order });
        n.object.next_order += 1;
        n.object.lookup.putAssumeCapacity(copy, i);
        n.object.ordered = false;
    }
    pub fn remove(self: *Graph, target: Value, key: []const u8) Error!bool {
        const n = try self.nodePtr(target);
        if (n.* != .object) return error.InvalidType;
        const i = n.object.lookup.get(key) orelse return false;
        _ = n.object.lookup.remove(key);
        _ = n.object.properties.swapRemove(i);
        if (i < n.object.properties.items.len) n.object.lookup.getPtr(n.object.properties.items[i].key).?.* = i;
        n.object.ordered = false;
        return true;
    }
    pub fn get(self: *const Graph, target: Value, key: []const u8) Error!?Value {
        const n = try self.rawNode(target);
        if (n != .object) return error.InvalidType;
        return if (n.object.lookup.get(key)) |i| n.object.properties.items[i].value else null;
    }
    pub fn arrayPut(self: *Graph, target: Value, index: u32, value: Value) Error!void {
        try self.validate(value);
        const n = try self.nodePtr(target);
        if (n.* != .array or index >= n.array.length) return error.InvalidType;
        if (n.array.lookup.get(index)) |i| {
            n.array.elements.items[i].value = value;
            return;
        }
        const a = self.allocator();
        try n.array.elements.ensureUnusedCapacity(a, 1);
        try n.array.lookup.ensureUnusedCapacity(a, 1);
        const i = n.array.elements.items.len;
        if (i > 0 and n.array.elements.items[i - 1].index > index) n.array.ordered = false;
        n.array.elements.appendAssumeCapacity(.{ .index = index, .value = value });
        n.array.lookup.putAssumeCapacity(index, i);
    }
    /// null means a hole; .undefined means an explicitly populated undefined.
    pub fn arrayGet(self: *const Graph, target: Value, index: u32) Error!?Value {
        const n = try self.rawNode(target);
        if (n != .array or index >= n.array.length) return error.InvalidType;
        return if (n.array.lookup.get(index)) |i| n.array.elements.items[i].value else null;
    }
    pub fn mapPut(self: *Graph, target: Value, key: Value, value: Value) Error!void {
        try self.validate(key);
        try self.validate(value);
        const n = try self.nodePtr(target);
        if (n.* != .map) return error.InvalidType;
        const ctx = ValueContext{ .graph = self };
        if (n.map.lookup.getContext(key, ctx)) |i| {
            n.map.entries.items[i].value = value;
            return;
        }
        const a = self.allocator();
        try n.map.entries.ensureUnusedCapacity(a, 1);
        try n.map.lookup.ensureUnusedCapacityContext(a, 1, ctx);
        const i = n.map.entries.items.len;
        n.map.entries.appendAssumeCapacity(.{ .key = normalizeZero(key), .value = value });
        n.map.lookup.putAssumeCapacityContext(normalizeZero(key), i, ctx);
    }
    pub fn setAdd(self: *Graph, target: Value, value: Value) Error!void {
        try self.validate(value);
        const n = try self.nodePtr(target);
        if (n.* != .set) return error.InvalidType;
        const ctx = ValueContext{ .graph = self };
        if (n.set.lookup.containsContext(value, ctx)) return;
        const a = self.allocator();
        try n.set.values.ensureUnusedCapacity(a, 1);
        try n.set.lookup.ensureUnusedCapacityContext(a, 1, ctx);
        n.set.values.appendAssumeCapacity(normalizeZero(value));
        n.set.lookup.putAssumeCapacityContext(normalizeZero(value), {}, ctx);
    }
};

fn bytesEqual(a: []const u8, b: []const u8) bool {
    return a.len == b.len and (a.ptr == b.ptr or std.mem.eql(u8, a, b));
}
pub fn equal(a: Value, b: Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .null, .undefined => true,
        .boolean => |v| v == b.boolean,
        .number => |v| v == b.number or (std.math.isNan(v) and std.math.isNan(b.number)),
        .string => |v| bytesEqual(v, b.string),
        .bigint => |v| bytesEqual(v, b.bigint),
        .ref => |v| v == b.ref,
    };
}
fn normalizeZero(v: Value) Value {
    return if (v == .number and v.number == 0) .{ .number = 0 } else v;
}
pub fn canonicalBigInt(s: []const u8) bool {
    if (std.mem.eql(u8, s, "0")) return true;
    const digits = if (s.len > 0 and s[0] == '-') s[1..] else s;
    if (digits.len == 0 or digits[0] < '1' or digits[0] > '9') return false;
    for (digits) |c| if (c < '0' or c > '9') return false;
    return true;
}
pub fn arrayIndex(s: []const u8) ?u32 {
    if (s.len == 0 or s.len > 10 or (s.len > 1 and s[0] == '0')) return null;
    for (s) |c| if (c < '0' or c > '9') return null;
    const n = std.fmt.parseInt(u32, s, 10) catch return null;
    return if (n == std.math.maxInt(u32)) null else n;
}
fn canonicalFlags(flags: []const u8, out: *[8]u8) Error!usize {
    const order = "dgimsuvy";
    var seen: [8]bool = @splat(false);
    for (flags) |flag| {
        const i = std.mem.indexOfScalar(u8, order, flag) orelse return error.UnsupportedValue;
        if (seen[i]) return error.UnsupportedValue;
        seen[i] = true;
    }
    if (seen[5] and seen[6]) return error.UnsupportedValue;
    var len: usize = 0;
    for (order, seen) |c, yes| if (yes) {
        out[len] = c;
        len += 1;
    };
    return len;
}

pub const Reducer = struct { name: []const u8, context: ?*anyopaque = null, reduce: *const fn (?*anyopaque, *Graph, Value) Error!?Value };
pub const Reviver = struct { name: []const u8, context: ?*anyopaque = null, revive: *const fn (?*anyopaque, *Graph, Value) Error!Value };
pub const stringify = @import("encode.zig").stringify;
pub const parse = @import("decode.zig").parse;
pub const ParseResult = struct {
    graph: Graph,
    value: Value,
    pub fn deinit(self: *ParseResult) void {
        self.graph.deinit();
        self.* = undefined;
    }
};
/// Traversal limit is a resource bound, including reentrant custom callbacks.
pub const max_depth = 256;
