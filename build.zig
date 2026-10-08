const package = @import("zig/build.zig");

pub fn build(b: *@import("std").Build) void {
    package.addPackage(b, "zig");
}
