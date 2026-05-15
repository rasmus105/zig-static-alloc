const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zig_static_heap", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_tests = b.addTest(.{
        .root_module = mod,
        .filters = b.option([]const []const u8, "test-filter", "Filter tests") orelse &.{},
    });
    mod_tests.root_module.addAnonymousImport("fuzz_corpus", .{
        .root_source_file = b.path("test/corpus/root.zig"),
    });

    b.installArtifact(mod_tests);
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    const check_step = b.step("check", "Check compilation");
    check_step.dependOn(test_step);
}
