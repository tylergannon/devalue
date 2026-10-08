const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const dep = b.dependency("devalue", .{ .target = target, .optimize = .debug });
    const root = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = .debug });
    root.addImport("devalue", dep.module("devalue"));
    const exe = b.addExecutable(.{ .name = "binary-consumer", .root_module = root });
    b.step("run", "Exercise binary public API").dependOn(&b.addRunArtifact(exe).step);
}
