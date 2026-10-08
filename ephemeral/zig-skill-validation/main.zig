const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2 or !std.mem.eql(u8, args[1], "probe")) return error.MissingProbeArgument;
    const greeting = try init.gpa.print("Zig {s} entrypoint and arguments OK\n", .{@import("builtin").zig_version_string});
    defer init.gpa.free(greeting);
    try std.Io.File.stdout().writeStreamingAll(init.io, greeting);
}
