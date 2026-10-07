const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.step("test", "Validate skill APIs").dependOn(&b.addRunArtifact(tests).step);

    const exe = b.addExecutable(.{
        .name = "skill-entrypoint",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step("run", "Validate entrypoint and passthrough arguments").dependOn(&run.step);
    const fmt = b.addFmt(.{ .paths = b.pathList(&.{ "build.zig", "tests.zig", "main.zig" }), .check = true });
    b.step("fmt", "Check validation source formatting").dependOn(&fmt.step);
}
