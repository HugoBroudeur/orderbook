const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const allocator = b.allocator;
    const current_dir_abs = b.build_root.handle.realpathAlloc(allocator, ".") catch unreachable;
    defer allocator.free(current_dir_abs);
    const mod_name = std.fs.path.basename(current_dir_abs);

    const sdl_path = "../../libc/SDL/SDL3-3.2.28/x86_64-w64-mingw32";

    // -------
    // module
    // -------
    const step = b.addTranslateC(.{
        .root_source_file = b.path(b.pathJoin(&.{ sdl_path, "include/SDL3/SDL.h" })),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // -------
    // Extention
    // -------
    const ttf_path = "../../libc/SDL/SDL3_ttf-3.2.2";
    const ttf_step = b.addTranslateC(.{
        .root_source_file = b.path(b.pathJoin(&.{ ttf_path, "include/SDL3_ttf/SDL_ttf.h" })),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // //
    ttf_step.defineCMacro("SDL_ENABLE_OLD_NAMES", "");
    ttf_step.defineCMacro("SDLTTF_VENDORED", "");
    // //
    // // // step.addIncludePath(b.path(b.pathJoin(&.{ sdl_path, "include/SDL3" })));
    // // // step.addIncludePath(b.path(b.pathJoin(&.{ sdl_path, "include" })));
    ttf_step.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "include/SDL3_ttf" })));
    ttf_step.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "include" })));
    ttf_step.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "src" })));

    const ttf_mod = ttf_step.addModule("sdl_ttf");
    ttf_mod.addCMacro("TTF_USE_HARFBUZZ", "1");
    // // mod.addImport(mod_name, mod);

    step.defineCMacro("SDL_ENABLE_OLD_NAMES", "");
    // step.defineCMacro("SDLTTF_VENDORED", "");

    step.addIncludePath(b.path(b.pathJoin(&.{ sdl_path, "include/SDL3" })));
    step.addIncludePath(b.path(b.pathJoin(&.{ sdl_path, "include" })));
    // step.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "include/SDL3_ttf" })));
    // step.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "include" })));

    const mod = step.addModule(mod_name);
    mod.addImport(mod_name, mod);
    // mod.addImport("sdl_ttf", ttf_mod);

    // mod.addCSourceFiles(.{ .root = b.path(b.pathJoin(&.{ ttf_path, "src" })), .files = &.{
    //     "SDL_gpu_textengine.c",
    //     "SDL_hashtable.c",
    //     "SDL_renderer_textengine.c",
    //     "SDL_surface_textengine.c",
    //     "SDL_ttf.c",
    // } });

    // mod.linkSystemLibrary("SDL3_ttf", .{});

    // Add harfbuzz dep
    const harfbuzz_dep = b.dependency("harfbuzz", .{
        .target = target,
        .optimize = optimize,
    });
    mod.linkLibrary(harfbuzz_dep.artifact("harfbuzz"));
    mod.addCMacro("TTF_USE_HARFBUZZ", "1");

    // Add freetype dep
    const freetype_dep = b.dependency("freetype", .{
        .target = target,
        .optimize = optimize,
    });
    mod.linkLibrary(freetype_dep.artifact("freetype"));

    // Add SDL3_ttf
    const dep_sdl_ttf = b.dependency("SDL_ttf", .{
        .target = target,
        .optimize = optimize,
    });
    // mod.addObject(dep_sdl_ttf.artifact("SDL3_ttf"));
    mod.linkLibrary(dep_sdl_ttf.artifact("SDL3_ttf"));
    mod.addIncludePath(b.path("SDL3_ttf"));

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = mod_name,
        .root_module = mod,
    });
    lib.addIncludePath(b.path("SDL3_ttf"));

    // lib.linkLibrary(dep_sdl_ttf.artifact("SDL3_ttf"));

    {
        const SDL_ttf = b.addLibrary(.{
            .name = "SDL3_ttf",
            .linkage = .static,
            .root_module = ttf_mod,
        });
        {
            SDL_ttf.addCSourceFiles(.{ .root = b.path(b.pathJoin(&.{ ttf_path, "src" })), .files = &.{
                "SDL_gpu_textengine.c",
                "SDL_hashtable.c",
                "SDL_renderer_textengine.c",
                "SDL_surface_textengine.c",
                "SDL_ttf.c",
            } });
            SDL_ttf.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "include" })));
            // SDL_ttf.addIncludePath(b.path(b.pathJoin(&.{ ttf_path, "include/SDL3_ttf" })));
            SDL_ttf.installHeadersDirectory(b.path(b.pathJoin(&.{ ttf_path, "include/SDL3_ttf" })), "SDL3_ttf", .{});

            SDL_ttf.linkLibrary(freetype_dep.artifact("freetype"));
            SDL_ttf.linkLibrary(harfbuzz_dep.artifact("harfbuzz"));
            // SDL_ttf.linkLibrary(lib);
            lib.linkLibrary(SDL_ttf);

            // if (target.result.os.tag == .macos) {
            //     const sdk = std.zig.system.darwin.getSdk(b.allocator, b.graph.host.result) orelse
            //         @panic("macOS SDK is missing");
            //     SDL_ttf.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "/usr/include" }) });
            //     SDL_ttf.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "/System/Library/Frameworks" }) });
            //     SDL_ttf.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "/usr/lib" }) });
            // }

            SDL_ttf.addIncludePath(b.path(b.pathJoin(&.{ sdl_path, "include" })));

            b.installArtifact(SDL_ttf);
        }
    }

    // mod.addImport("sdl_ttf", ttf_mod);

    // lib.addObject(dep_sdl_ttf.artifact("SDL3_ttf"));
    // lib.linkLibrary(dep_sdl_ttf.artifact("SDL3_ttf"));

    // lib.installHeadersDirectory(b.path(b.pathJoin(&.{ ttf_path, "include" })), "", .{});

    b.installArtifact(lib);
    //    std.debug.print("{s} module\n",.{mod_name});
}
