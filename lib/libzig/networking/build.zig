const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const allocator = b.allocator;
    const current_dir_abs = b.build_root.handle.realpathAlloc(allocator, ".") catch unreachable;
    defer allocator.free(current_dir_abs);
    const mod_name = std.fs.path.basename(current_dir_abs);

    // -------
    // module
    // -------
    const mod = b.addModule(mod_name, .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // _ = mod;

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = mod_name,
        .root_module = mod,
    });
    b.installArtifact(lib);
    //    std.debug.print("{s} module\n",.{mod_name});
}
