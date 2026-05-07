const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const mod = b.addModule("zig_static_heap", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .Debug,
    });

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    const check_step = b.step("check", "Check compilation");
    check_step.dependOn(test_step);
}
