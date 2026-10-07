const std = @import("std");

pub fn build(b: *std.Build) void {
    const fixtures = b.addOptions();
    fixtures.addOption([]const u8, "golden_path", b.option([]const u8, "golden", "Runtime corpus path") orelse "../../v5/testdata/golden.json");
    const root = b.createModule(.{
        .root_source_file = b.path("tests.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = .debug,
    });
    root.addOptions("fixtures", fixtures);
    const tests = b.addTest(.{ .root_module = root });
    const run = b.addRunArtifact(tests);
    run.setCwd(b.path("."));
    b.step("test", "Validate runtime fixture access and JSON string policy").dependOn(&run.step);
}
