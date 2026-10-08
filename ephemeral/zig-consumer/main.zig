const std = @import("std");
const d = @import("devalue");
pub fn main(init: std.process.Init) !void {
    var g = d.Graph.init(init.gpa);
    defer g.deinit();
    const root = try g.object(false);
    const child = try g.array(3);
    try g.arrayPut(child, 0, try g.string("Hello <Zig> 😀"));
    try g.arrayPut(child, 2, .undefined);
    try g.put(root, "child", child);
    try g.put(root, "alias", child);
    try g.put(root, "self", root);
    const bytes = try d.stringify(init.gpa, &g, root, &.{});
    defer init.gpa.free(bytes);
    var result = try d.parse(init.gpa, bytes, &.{});
    defer result.deinit();
    const a = (try result.graph.get(result.value, "child")).?;
    if (!d.equal(a, (try result.graph.get(result.value, "alias")).?) or !d.equal(result.value, (try result.graph.get(result.value, "self")).?)) return error.IdentityMismatch;
    if (try result.graph.arrayGet(a, 1) != null or (try result.graph.arrayGet(a, 2)).? != .undefined) return error.HoleMismatch;
    const output = try d.stringify(init.gpa, &result.graph, result.value, &.{});
    defer init.gpa.free(output);
    if (!std.mem.eql(u8, bytes, output)) return error.ByteMismatch;
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
