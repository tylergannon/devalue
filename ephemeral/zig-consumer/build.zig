const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const dependency = b.dependency("devalue", .{ .target = target, .optimize = .debug });
    const root = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = .debug });
    root.addImport("devalue", dependency.module("devalue"));
    const exe = b.addExecutable(.{ .name = "public-consumer", .root_module = root });
    b.step("run", "Use devalue as a path dependency").dependOn(&b.addRunArtifact(exe).step);
}
