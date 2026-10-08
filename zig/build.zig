const std = @import("std");

pub fn build(b: *std.Build) void {
    addPackage(b, ".");
}

// Both the repository archive and the nested checkout export the same module.
pub fn addPackage(b: *std.Build, source_dir: []const u8) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib = b.addModule("devalue", .{ .root_source_file = b.path(b.pathJoin(&.{ source_dir, "src/root.zig" })), .target = target, .optimize = optimize });
    const fixtures = b.addOptions();
    fixtures.addOption([]const u8, "golden_path", b.option([]const u8, "golden", "Shared upstream fixture path") orelse "../v5/testdata/golden.json");
    const interop_dir = b.option([]const u8, "interop-dir", "Directory containing native Go exchange documents") orelse "";
    fixtures.addOption([]const u8, "interop_dir", interop_dir);
    const tests_mod = b.createModule(.{ .root_source_file = b.path(b.pathJoin(&.{ source_dir, "tests/tests.zig" })), .target = target, .optimize = optimize });
    tests_mod.addImport("devalue", lib);
    tests_mod.addOptions("fixtures", fixtures);
    const tests = b.addTest(.{ .root_module = tests_mod });
    const run = b.addRunArtifact(tests);
    // Fixtures and package pins are read at runtime, outside the build cache.
    run.has_side_effects = true;
    run.setCwd(b.path(source_dir));
    b.step("test", "Run native codec and parity tests").dependOn(&run.step);
    const interop_step = b.step("interop", "Exchange binary documents with Go v5 and v6");
    if (interop_dir.len == 0) {
        interop_step.dependOn(&b.addFail("interop requires -Dinterop-dir; use just test-interop").step);
    } else {
        const interop_tests = b.addTest(.{ .root_module = tests_mod, .filters = &.{"Go Zig binary exchange"} });
        const interop_run = b.addRunArtifact(interop_tests);
        interop_run.has_side_effects = true;
        interop_run.setCwd(b.path(source_dir));
        interop_step.dependOn(&interop_run.step);
    }
    b.step("fmt", "Check Zig formatting").dependOn(&b.addFmt(.{ .paths = b.pathList(&.{source_dir}), .check = true }).step);
    const bench_mod = b.createModule(.{ .root_source_file = b.path(b.pathJoin(&.{ source_dir, "bench.zig" })), .target = target, .optimize = optimize });
    bench_mod.addImport("devalue", lib);
    const bench = b.addExecutable(.{ .name = "devalue-bench", .root_module = bench_mod });
    const bench_run = b.addRunArtifact(bench);
    bench_run.addPassthruArgs();
    b.step("bench", "Benchmark the flat codec").dependOn(&bench_run.step);
}
