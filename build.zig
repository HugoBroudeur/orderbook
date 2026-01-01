const std = @import("std");
const builtin = @import("builtin");
const protobuf = @import("protobuf");
const blib = @import("./build_lib.zig");

const protobuf_files = &.{ "proto", "proto/all.proto", "proto/orderbook/v1/orderbook.proto" };

// Shaders
// const shaders = .{
//     // "src/shaders/2d.vert.zig",
//     // "src/shaders/quad.frag.zig",
//     "src/shaders/triangle.frag.zig",
//     "src/shaders/triangle.vert.zig",
// };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get executable name from current directory name
    const allocator = b.allocator;
    const abs_path = b.build_root.handle.realpathAlloc(allocator, ".") catch unreachable;
    defer allocator.free(abs_path);
    const exe_name = "Price is Power";

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const compile_shader = b.addExecutable(.{
        .name = "compile_shader",
        .root_module = b.createModule(.{
            .optimize = optimize,
            .target = target,
            .root_source_file = b.path("tools/compile_shader.zig"),
        }),
    });

    // Register external module from "./build.zig.zon" file.
    blib.addExternalModule(b, main_mod);

    // Additionnal External Dependencies
    const dep_sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });
    const dep_sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,

        // Lib options.
        // .callbacks = false,
        .ext_image = true,
        // .ext_net = false,
        .ext_ttf = true,
        // .log_message_stack_size = 1024,
        // .main = false,
        // .renderer_debug_text_stack_size = 1024,

        // Options passed directly to https://github.com/castholm/SDL (SDL3 C Bindings):
        // .c_sdl_preferred_linkage = .static,
        // .c_sdl_strip = false,
        // .c_sdl_sanitize_c = .off,
        // .c_sdl_lto = .none,
        // .c_sdl_emscripten_pthreads = false,
        // .c_sdl_install_build_config_h = false,

        // Options if `ext_image` is enabled:
        .image_enable_bmp = true,
        // .image_enable_gif = true,
        .image_enable_jpg = true,
        // .image_enable_lbm = true,
        // .image_enable_pcx = true,
        .image_enable_png = true,
        // .image_enable_pnm = true,
        // .image_enable_qoi = true,
        // .image_enable_svg = true,
        // .image_enable_tga = true,
        // .image_enable_xcf = true,
        // .image_enable_xpm = true,
        // .image_enable_xv = true,
    });
    const dep_zcs = b.dependency("zcs", .{
        .target = target,
        .optimize = optimize,
    });
    const dep_tracy = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
    });
    const dep_zclay = b.dependency("zclay", .{
        .target = target,
        .optimize = optimize,
    });
    const dep_zmath = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    });

    // Generate Zig code from .proto
    // const gen_proto = b.step("gen-proto", "generate zig files from protocol buffer definitions");
    // const protoc_step = protobuf.RunProtocStep.create(dep_protobuf.*.builder, target, .{
    //     .destination_directory = b.path("src/proto"),
    //     .source_files = protobuf_files,
    //     .include_directories = &.{""},
    // });
    // gen_proto.dependOn(&protoc_step.step);

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = main_mod,
        .use_llvm = true,
    });

    exe.root_module.addImport("sdl3", dep_sdl3.module("sdl3"));
    exe.root_module.addImport("sqlite", dep_sqlite.module("sqlite"));
    exe.root_module.addImport("zcs", dep_zcs.module("zcs"));
    exe.root_module.addImport("tracy", dep_tracy.module("tracy"));
    exe.root_module.addImport("zclay", dep_zclay.module("zclay"));
    exe.root_module.addImport("zmath", dep_zmath.module("root"));

    // Load Icon
    // exe.root_module.addWin32ResourceFile(.{ .file = b.path("src/res/res.rc") });

    // std.Build: Deprecate Step.Compile APIs that mutate the root module #22587
    // See. https://github.com/ziglang/zig/pull/22587
    //----------------------------------
    const sdlPath = "lib/libc/SDL/SDL3-3.2.28/x86_64-w64-mingw32";

    //-------------------
    // For application
    //-------------------
    //------
    // Libs
    //------
    // exe.root_module.linkSystemLibrary("glfw3", .{});
    if (builtin.target.os.tag == .windows) {
        exe.root_module.linkSystemLibrary("gdi32", .{});
        exe.root_module.linkSystemLibrary("imm32", .{});
        exe.root_module.linkSystemLibrary("advapi32", .{});
        exe.root_module.linkSystemLibrary("comdlg32", .{});
        exe.root_module.linkSystemLibrary("dinput8", .{});
        exe.root_module.linkSystemLibrary("dxerr8", .{});
        exe.root_module.linkSystemLibrary("dxguid", .{});
        exe.root_module.linkSystemLibrary("gdi32", .{});
        exe.root_module.linkSystemLibrary("hid", .{});
        exe.root_module.linkSystemLibrary("kernel32", .{});
        exe.root_module.linkSystemLibrary("ole32", .{});
        exe.root_module.linkSystemLibrary("oleaut32", .{});
        exe.root_module.linkSystemLibrary("setupapi", .{});
        exe.root_module.linkSystemLibrary("shell32", .{});
        exe.root_module.linkSystemLibrary("user32", .{});
        exe.root_module.linkSystemLibrary("uuid", .{});
        exe.root_module.linkSystemLibrary("version", .{});
        exe.root_module.linkSystemLibrary("winmm", .{});
        exe.root_module.linkSystemLibrary("winspool", .{});
        exe.root_module.linkSystemLibrary("ws2_32", .{});
        exe.root_module.linkSystemLibrary("opengl32", .{});
        exe.root_module.linkSystemLibrary("shell32", .{});
        exe.root_module.linkSystemLibrary("user32", .{});
        // Static link
        exe.addObjectFile(b.path(b.pathJoin(&.{ sdlPath, "lib", "libSDL3.dll.a" })));
    } else if (builtin.target.os.tag == .linux) {
        exe.root_module.linkSystemLibrary("GL", .{});
        exe.root_module.linkSystemLibrary("X11", .{});
        exe.root_module.linkSystemLibrary("SDL3", .{});
        // exe.root_module.linkSystemLibrary("SDL3_ttf", .{});
        // exe.root_module.linkSystemLibrary("sqlite3", .{});
    }
    // sdl3
    //exe.addLibraryPath(b.path(b.pathJoin(&.{sdlPath, "lib-mingw-64"})));
    //exe.linkSystemLibrary("SD32");      // For static link
    // Dynamic link
    //exe.addObjectFile(b.path(b.pathJoin(&.{sdlPath, "lib","libSDL3dll.a"})));
    //exe.linkSystemLibrary("SDL3dll"); // For dynamic link

    // SDL3_ttf
    // exe.root_module.linkLibrary(dep_sdl_ttf.artifact("SDL3_ttf"));

    // root_module
    exe.root_module.link_libc = true;
    exe.root_module.link_libcpp = true;
    exe.subsystem = .Windows; // Hide console window

    b.installArtifact(exe);

    const install_resources = b.addInstallDirectory(.{
        .source_dir = b.path("assets"), // base: assets folder
        .install_dir = .bin, // bin folder
        .install_subdir = "assets", // destination: bin/resources/
    });
    const db_resources = b.addInstallDirectory(.{
        .source_dir = b.path("db"), // base: db folder
        .install_dir = .bin, // bin folder
        .install_subdir = "db", // destination: bin/db/
    });
    exe.step.dependOn(&install_resources.step);
    exe.step.dependOn(&db_resources.step);

    const resBin = [_][]const u8{
        "imgui.ini",
    };

    inline for (resBin) |file| {
        const res = b.addInstallFile(b.path(file), "bin/" ++ file);
        b.getInstallStep().dependOn(&res.step);
    }

    // SHADERS
    // Compile shaders.
    const run_compile_shader = b.addRunArtifact(compile_shader);
    b.getInstallStep().dependOn(&run_compile_shader.step);

    // var shader_dir = try std.fs.cwd().openDir("src/shaders", .{ .iterate = true });
    // defer shader_dir.close();
    // var shader_dir_walker = try shader_dir.walk(b.allocator);
    // defer shader_dir_walker.deinit();
    // while (try shader_dir_walker.next()) |shader| {
    //     if (shader.kind != .file or !(std.mem.endsWith(u8, shader.basename, ".slang")))
    //         // if (shader.kind != .file or !(std.mem.endsWith(u8, shader.basename, ".vert.zig") or std.mem.endsWith(u8, shader.basename, ".frag.zig")))
    //         continue;
    //     // const spv_name = try std.mem.replaceOwned(u8, b.allocator, shader.basename, ".zig", ".spv");
    //     const spv_name = try std.mem.replaceOwned(u8, b.allocator, shader.basename, ".slang", ".spv");
    //     defer b.allocator.free(spv_name);
    //     const shader_path = try std.fmt.allocPrint(b.allocator, "src/shaders/{s}", .{shader.path});
    //     defer b.allocator.free(shader_path);
    //     // compileShader(b, exe.root_module, shader_path, spv_name);
    //
    //     exe.root_module.addAnonymousImport(spv_name, .{ .root_source_file = b.path(shader_path) });
    // }
    // END SHADERS

    // const fonticon_dir = "../../src/libc/fonticon/fa6/";
    // const res_fonticon = [_][]const u8{ "fa-solid-900.ttf", "LICENSE.txt" };
    // inline for (res_fonticon) |file| {
    //     const res = b.addInstallFile(b.path(fonticon_dir ++ file), "bin/resources/fonticon/fa6/" ++ file);
    //     b.getInstallStep().dependOn(&res.step);
    // }

    // save [Executable name].ini
    // const sExeIni = b.fmt("{s}.ini", .{exe_name});
    // const resExeIni = b.addInstallFile(b.path(sExeIni), b.pathJoin(&.{ "bin", sExeIni }));
    // b.getInstallStep().dependOn(&resExeIni.step);

    if (true) { // Enable if use SDL3.dll with dynamic linking.
        const resSdlDll = b.pathJoin(&.{ sdlPath, "bin", "SDL3.dll" });
        const resSdl = b.addInstallFile(b.path(resSdlDll), "bin/SDL3.dll");
        b.getInstallStep().dependOn(&resSdl.step);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn compileShader(
    b: *std.Build,
    module: *std.Build.Module,
    path: []const u8,
    out_name: []const u8,
) void {
    const vulkan12_target = b.resolveTargetQuery(.{
        .cpu_arch = .spirv64,
        .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
        .cpu_features_add = std.Target.spirv.featureSet(&.{.int64}),
        .os_tag = .vulkan,
        .ofmt = .spirv,
    });

    const shader = b.addObject(.{
        .name = out_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .optimize = .ReleaseFast,
            .target = vulkan12_target,
        }),
        .use_llvm = false,
        .use_lld = false,
    });
    module.addAnonymousImport(out_name, .{
        .root_source_file = shader.getEmittedBin(),
    });
}

fn getFileName(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    const stem = std.fs.path.stem(basename);
    return stem;
}
