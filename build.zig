const package = @import("zig/build.zig");

pub fn build(b: *@import("std").Build) void {
    package.addPackage(b, "zig");
    b.top_level_steps.get("fmt").?.step.dependOn(&b.addFmt(.{ .paths = b.pathList(&.{ "build.zig", "build.zig.zon" }), .check = true }).step);
}
