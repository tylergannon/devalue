const std = @import("std");
const d = @import("devalue");
const Counting = struct {
    backing: std.mem.Allocator,
    allocations: usize = 0,
    bytes: usize = 0,
    fn allocator(self: *Counting) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn cast(ctx: *anyopaque) *Counting {
        return @ptrCast(@alignCast(ctx));
    }
    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const s = cast(ctx);
        const p = s.backing.vtable.alloc(s.backing.ptr, len, alignment, ra) orelse return null;
        s.allocations += 1;
        s.bytes += len;
        return p;
    }
    fn resize(ctx: *anyopaque, mem: []u8, alignment: std.mem.Alignment, n: usize, ra: usize) bool {
        const s = cast(ctx);
        const ok = s.backing.rawResize(mem, alignment, n, ra);
        if (ok and n > mem.len) s.bytes += n - mem.len;
        return ok;
    }
    fn remap(ctx: *anyopaque, mem: []u8, alignment: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        const s = cast(ctx);
        const p = s.backing.rawRemap(mem, alignment, n, ra) orelse return null;
        if (n > mem.len) s.bytes += n - mem.len;
        return p;
    }
    fn free(ctx: *anyopaque, mem: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const s = cast(ctx);
        s.backing.rawFree(mem, alignment, ra);
    }
};
fn workload(g: *d.Graph, name: []const u8) !d.Value {
    if (std.mem.eql(u8, name, "query")) {
        const obj = try g.object(false);
        try g.put(obj, "id", .{ .number = 42 });
        try g.put(obj, "search", try g.string("Zig"));
        try g.put(obj, "active", .{ .boolean = true });
        return obj;
    }
    if (std.mem.eql(u8, name, "records")) {
        const arr = try g.array(1000);
        for (0..1000) |i| {
            const obj = try g.object(false);
            try g.put(obj, "id", .{ .number = @floatFromInt(i) });
            try g.put(obj, "name", try g.string("record"));
            try g.put(obj, "active", .{ .boolean = i % 2 == 0 });
            try g.arrayPut(arr, @intCast(i), obj);
        }
        return arr;
    }
    if (std.mem.eql(u8, name, "aliases")) {
        const arr = try g.array(1000);
        const shared = try g.object(false);
        try g.put(shared, "text", try g.string("repeated"));
        for (0..1000) |i| try g.arrayPut(arr, @intCast(i), shared);
        return arr;
    }
    if (std.mem.eql(u8, name, "escapes")) {
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(g.allocator());
        for (0..1000) |_| try bytes.appendSlice(g.allocator(), "<\"\\\n\u{2028}😀");
        return g.string(bytes.items);
    }
    const arr = try g.array(1000000);
    try g.arrayPut(arr, 0, .{ .number = 1 });
    try g.arrayPut(arr, 500000, .{ .string = "x" });
    try g.arrayPut(arr, 999999, .null);
    return arr;
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const dump = args.len > 1 and std.mem.eql(u8, args[1], "dump");
    for ([_][]const u8{ "query", "records", "aliases", "escapes", "sparse" }) |name| {
        var g = d.Graph.init(init.gpa);
        defer g.deinit();
        const value = try workload(&g, name);
        const wire = try d.stringify(init.gpa, &g, value, &.{});
        defer init.gpa.free(wire);
        var parsed = try d.parse(init.gpa, wire, &.{});
        defer parsed.deinit();
        const reencoded = try d.stringify(init.gpa, &parsed.graph, parsed.value, &.{});
        defer init.gpa.free(reencoded);
        if (!std.mem.eql(u8, wire, reencoded)) return error.ParityFailure;
        if (dump) {
            try std.Io.File.stdout().writeStreamingAll(init.io, wire);
            try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
            continue;
        }
        const iterations: usize = if (std.mem.eql(u8, name, "records")) 500 else if (std.mem.eql(u8, name, "escapes")) 1000 else if (std.mem.eql(u8, name, "aliases")) 5000 else 100000;
        for ([_]bool{ false, true }) |decode| {
            for (0..5) |trial| {
                var counter = Counting{ .backing = init.gpa };
                const alloc = counter.allocator();
                const start = std.Io.Clock.awake.now(init.io);
                for (0..iterations) |_| {
                    if (decode) {
                        var r = try d.parse(alloc, wire, &.{});
                        r.deinit();
                    } else {
                        const out = try d.stringify(alloc, &g, value, &.{});
                        std.mem.doNotOptimizeAway(out.ptr);
                        alloc.free(out);
                    }
                }
                const ns = start.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds();
                const row = try init.gpa.print("zig,{s},{s},{d},{d},{d},{d},{d},{d}\n", .{ name, if (decode) "decode" else "encode", trial, wire.len, iterations, @divTrunc(ns, iterations), counter.allocations / iterations, counter.bytes / iterations });
                defer init.gpa.free(row);
                try std.Io.File.stdout().writeStreamingAll(init.io, row);
            }
        }
    }
}
