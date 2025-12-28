const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const allocator = b.allocator;
    const current_dir_abs = b.build_root.handle.realpathAlloc(allocator, ".") catch unreachable;
    defer allocator.free(current_dir_abs);
    const mod_name = std.fs.path.basename(current_dir_abs);

    // Extensions
    const ttf_path = "../../libc/SDL/SDL3_ttf-3.2.2";

    // -------
    // module
    // -------
    const step = b.addTranslateC(.{
        .root_source_file = b.path(b.pathJoin(&.{ ttf_path, "include/SDL3_ttf/SDL_ttf.h" })),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    step.defineCMacro("SDL_ENABLE_OLD_NAMES", "");
    step.defineCMacro("SDLTTF_VENDORED", "");

    // step.addIncludePath(b.path(b.pathJoin(&.{ sdl_path, "include/SDL3" })));
    // step.addIncludePath(b.path(b.pathJoin(&.{ sdl_path, "include" })));
    step.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "include/SDL3_ttf" })));
    step.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "include" })));
    step.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "src" })));
    const mod = step.addModule(mod_name);
    mod.addImport(mod_name, mod);

    // mod.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "include/SDL3_ttf" })));
    // mod.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "include" })));
    // mod.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "src" })));
    //
    // mod.addCSourceFiles(.{
    //     .files = &.{
    //         // // SDL_ttf Extension
    //         "../../libc/SDL/SDL3_ttf-3.2.2/src/SDL_gpu_textengine.c",
    //         "../../libc/SDL/SDL3_ttf-3.2.2/src/SDL_hashtable.c",
    //         "../../libc/SDL/SDL3_ttf-3.2.2/src/SDL_renderer_textengine.c",
    //         "../../libc/SDL/SDL3_ttf-3.2.2/src/SDL_surface_textengine.c",
    //         "../../libc/SDL/SDL3_ttf-3.2.2/src/SDL_ttf.c",
    //     },
    // });

    mod.linkSystemLibrary("SDL3_ttf", .{});

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = mod_name,
        .root_module = mod,
    });
    b.installArtifact(lib);
    //    std.debug.print("{s} module\n",.{mod_name});
}
