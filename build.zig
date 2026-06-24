const std = @import("std");

pub fn build(b: *std.Build) void {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });

    const exe = b.addExecutable(.{ .name = "libsslsk", .root_module = mod, .use_llvm = true });
    b.installArtifact(exe);

    const check = b.step("check", "Allow zls to use build on save diagnostics by default");
    check.dependOn(&exe.step);
}
