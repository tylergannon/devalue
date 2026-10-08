from pathlib import Path
p=Path('zig/src/root.zig');s=p.read_text()
s=s.replace('pub const Property = struct { key: []const u8, value: Value };','pub const Property = struct { key: []const u8, value: Value, order: usize = 0 };')
s=s.replace('pub const Object = struct { null_proto: bool, properties: std.ArrayList(Property) = .empty };','''pub const Object = struct { null_proto: bool, properties: std.ArrayList(Property) = .empty, lookup: std.StringHashMapUnmanaged(usize) = .empty, next_order: usize = 0, ordered: bool = true };''')
s=s.replace('pub const Array = struct { length: u32, elements: std.ArrayList(Element) = .empty };','''pub const Array = struct { length: u32, elements: std.ArrayList(Element) = .empty, lookup: std.AutoHashMapUnmanaged(u32,usize) = .empty, ordered: bool = true };''')
s=s.replace('pub const Node = union(enum) {','''pub const Map = struct { entries: std.ArrayList(Entry) = .empty, lookup: std.HashMapUnmanaged(Value,usize,ValueContext,80) = .empty };
pub const Set = struct { values: std.ArrayList(Value) = .empty, lookup: std.HashMapUnmanaged(Value,void,ValueContext,80) = .empty };
pub const ByteKey = struct { ptr: usize, len: usize };
const ByteInfo = struct { hash: u64, bigint: bool };
pub fn byteKey(bytes: []const u8) ByteKey { return .{ .ptr = @intFromPtr(bytes.ptr), .len = bytes.len }; }
pub const ValueContext = struct {
    graph: *const Graph,
    pub fn hash(self: @This(), v: Value) u64 {
        const tag: u64 = @backingInt(std.meta.activeTag(v));
        const h: u64 = switch(v) {
            .null, .undefined => 0, .boolean => |b| @intFromBool(b),
            .number => |f| if (f == 0) 0 else if (std.math.isNan(f)) 0x7ff8000000000000 else @bitCast(f),
            .ref => |r| @backingInt(r),
            .string, .bigint => |bytes| if (self.graph.bytes.get(byteKey(bytes))) |info| info.hash else std.hash.Wyhash.hash(0,bytes),
        };
        return std.hash.Wyhash.hash(tag,std.mem.asBytes(&h));
    }
    pub fn eql(_: @This(), a: Value, b: Value) bool { return equal(a,b); }
};
fn propertyLess(_: void, a: Property, b: Property) bool {
    const ai = arrayIndex(a.key); const bi = arrayIndex(b.key);
    if (ai) |i| return if (bi) |j| i < j else true;
    if (bi != null) return false;
    return a.order < b.order;
}
fn elementLess(_: void, a: Element, b: Element) bool { return a.index < b.index; }
pub const Node = union(enum) {''')
s=s.replace('map: std.ArrayList(Entry),','map: Map,').replace('set: std.ArrayList(Value),','set: Set,')
s=s.replace('nodes: std.ArrayList(Node) = .empty,','nodes: std.ArrayList(Node) = .empty,\n    bytes: std.AutoHashMapUnmanaged(ByteKey,ByteInfo) = .empty,')
s=s.replace('return .{ .string = try self.allocator().dupe(u8, bytes) };','''const copy = try self.allocator().dupe(u8,bytes);
        try self.bytes.put(self.allocator(),byteKey(copy),.{ .hash=std.hash.Wyhash.hash(0,copy), .bigint=false });
        return .{ .string = copy };''')
s=s.replace('return .{ .bigint = try self.allocator().dupe(u8, digits) };','''const copy = try self.allocator().dupe(u8,digits);
        try self.bytes.put(self.allocator(),byteKey(copy),.{ .hash=std.hash.Wyhash.hash(0,copy), .bigint=true });
        return .{ .bigint = copy };''')
s=s.replace('.{ .map = .empty }','.{ .map = .{} }').replace('.{ .set = .empty }','.{ .set = .{} }')
s=s.replace('if (!std.unicode.utf8ValidateSlice(s)) return error.UnsupportedString;','if (!self.bytes.contains(byteKey(s)) and !std.unicode.utf8ValidateSlice(s)) return error.UnsupportedString;')
s=s.replace('if (!canonicalBigInt(s)) return error.UnsupportedValue;','if (!(if (self.bytes.get(byteKey(s))) |info| info.bigint else false) and !canonicalBigInt(s)) return error.UnsupportedValue;')
start=s.index('    pub fn node(');end=s.index('    fn nodePtr',start)
s=s[:start]+'''    fn rawNode(self: *const Graph, value: Value) Error!Node {
        if (value != .ref) return error.InvalidType;
        try self.validate(value);
        return self.nodes.items[@backingInt(value.ref)];
    }
    pub fn node(self: *Graph, value: Value) Error!Node {
        const n = try self.nodePtr(value);
        switch(n.*) {
            .object => |*obj| if (!obj.ordered) {
                std.mem.sort(Property,obj.properties.items,{},propertyLess);
                for (obj.properties.items,0..) |prop,i| obj.lookup.getPtr(prop.key).?.* = i;
                obj.ordered = true;
            },
            .array => |*arr| if (!arr.ordered) {
                std.mem.sort(Element,arr.elements.items,{},elementLess);
                for (arr.elements.items,0..) |element,i| arr.lookup.getPtr(element.index).?.* = i;
                arr.ordered = true;
            },
            else => {},
        }
        return n.*;
    }
'''+s[end:]
start=s.index('        for (n.object.properties.items) |*p|');end=s.index('\n    pub fn arrayGet',start)
s=s[:start]+'''        if (n.object.lookup.get(key)) |i| { n.object.properties.items[i].value = value; return; }
        const a = self.allocator();
        try n.object.properties.ensureUnusedCapacity(a,1);
        try n.object.lookup.ensureUnusedCapacity(a,1);
        const copy = try a.dupe(u8,key);
        if (n.object.next_order == std.math.maxInt(usize)) return error.UnsupportedValue;
        const i = n.object.properties.items.len;
        n.object.properties.appendAssumeCapacity(.{ .key=copy,.value=value,.order=n.object.next_order });
        n.object.next_order += 1;
        n.object.lookup.putAssumeCapacity(copy,i);
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
        if (n.array.lookup.get(index)) |i| { n.array.elements.items[i].value=value; return; }
        const a=self.allocator();
        try n.array.elements.ensureUnusedCapacity(a,1);
        try n.array.lookup.ensureUnusedCapacity(a,1);
        const i=n.array.elements.items.len;
        if (i>0 and n.array.elements.items[i-1].index>index) n.array.ordered=false;
        n.array.elements.appendAssumeCapacity(.{.index=index,.value=value});
        n.array.lookup.putAssumeCapacity(index,i);
    }
    /// null means a hole; .undefined means an explicitly populated undefined.'''+s[end:]
start=s.index('        const n = try self.node(target);',s.index('pub fn arrayGet'));end=s.index('\n};\n',start)
s=s[:start]+'''        const n = try self.rawNode(target);
        if (n != .array or index >= n.array.length) return error.InvalidType;
        return if (n.array.lookup.get(index)) |i| n.array.elements.items[i].value else null;
    }
    pub fn mapPut(self: *Graph, target: Value, key: Value, value: Value) Error!void {
        try self.validate(key); try self.validate(value);
        const n = try self.nodePtr(target);
        if (n.* != .map) return error.InvalidType;
        const ctx=ValueContext{.graph=self};
        if (n.map.lookup.getContext(key,ctx)) |i| { n.map.entries.items[i].value=value; return; }
        const a=self.allocator();
        try n.map.entries.ensureUnusedCapacity(a,1);
        try n.map.lookup.ensureUnusedCapacityContext(a,1,ctx);
        const i=n.map.entries.items.len;
        n.map.entries.appendAssumeCapacity(.{.key=normalizeZero(key),.value=value});
        n.map.lookup.putAssumeCapacityContext(normalizeZero(key),i,ctx);
    }
    pub fn setAdd(self: *Graph, target: Value, value: Value) Error!void {
        try self.validate(value);
        const n = try self.nodePtr(target);
        if (n.* != .set) return error.InvalidType;
        const ctx=ValueContext{.graph=self};
        if (n.set.lookup.containsContext(value,ctx)) return;
        const a=self.allocator();
        try n.set.values.ensureUnusedCapacity(a,1);
        try n.set.lookup.ensureUnusedCapacityContext(a,1,ctx);
        n.set.values.appendAssumeCapacity(normalizeZero(value));
        n.set.lookup.putAssumeCapacityContext(normalizeZero(value),{},ctx);
    }'''+s[end:]
s=s.replace('std.mem.eql(u8, v, b.string)','bytesEqual(v, b.string)').replace('std.mem.eql(u8, v, b.bigint)','bytesEqual(v, b.bigint)')
s=s.replace('pub fn equal(', 'fn bytesEqual(a: []const u8, b: []const u8) bool { return a.len == b.len and (a.ptr == b.ptr or std.mem.eql(u8,a,b)); }\npub fn equal(')
p.write_text(s)
p=Path('zig/src/encode.zig');s=p.read_text();start=s.index('const Context = struct');end=s.index('pub fn truthy',start);s=s[:start]+'const Context = d.ValueContext;\n'+s[end:];s=s.replace('self.indices.get(v)','self.indices.getContext(v,.{.graph=self.graph})').replace('self.indices.put(self.a, v, index)','self.indices.putContext(self.a, v, index,.{.graph=self.graph})');s=s.replace('map.items','map.entries.items').replace('set.items','set.values.items');p.write_text(s)
for p in Path('zig/tests').glob('*.zig'):
 s=p.read_text().replace('.map.items','.map.entries.items').replace('.set.items','.set.values.items');p.write_text(s)
