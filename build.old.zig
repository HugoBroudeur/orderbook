const std = @import("std");
const protobuf = @import("protobuf");
const sokol = @import("sokol");

const protobuf_files = &.{ "proto", "proto/all.proto", "proto/orderbook/v1/orderbook.proto" };

const Options = struct {
    mod: *std.Build.Module,
    dep_sokol: *std.Build.Dependency,
};

const Dep = struct {
    name: []const u8,
    root_path: []const u8,
    module: *std.Build.Module,
    use_emscripten: bool = false,
    artifact: ?*std.Build.Step.Compile = null,
    builder: ?*std.Build = null,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod_networking = b.addModule("networking", .{
        .root_source_file = b.path("src/networking/mod.zig"),
        .target = target,
    });

    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });

    const tracy = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
    });

    // const dvui_dep = b.dependency("dvui", .{
    //     .target = target,
    //     .optimize = optimize,
    //     .backend = .sdl3,
    // });

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
    });

    const dep_zecs = b.dependency("zecs", .{
        .target = target,
        .optimize = optimize,
    });

    const dep_cimgui = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });

    const zflecs = b.dependency("zflecs", .{
        .target = target,
        .optimize = optimize,
    });

    const zcs = b.dependency("zcs", .{
        .target = target,
        .optimize = optimize,
    });

    const sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });

    const implot_module = buildImplot(b, target, optimize);

    // inject the cimgui header search path into the sokol C library compile step
    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path("src")); // Normal

    // Generate Zig code from .proto
    const gen_proto = b.step("gen-proto", "generate zig files from protocol buffer definitions");
    const protoc_step = protobuf.RunProtocStep.create(protobuf_dep.*.builder, target, .{
        .destination_directory = b.path("src/proto"),
        .source_files = protobuf_files,
        .include_directories = &.{""},
    });
    gen_proto.dependOn(&protoc_step.step);

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // .link_libc = true,
        // .link_libcpp = true,
        .imports = &.{
            .{ .name = "networking", .module = mod_networking },
            // .{ .name = "ecs", .module = mod_ecs },
            .{ .name = "protobuf", .module = protobuf_dep.module("protobuf") },
            // .{ .name = "dvui", .module = dvui_dep.module("dvui_sdl3") },
            // .{ .name = "sdl-backend", .module = dvui_dep.module("sdl3") },
            .{
                .name = "sokol",
                .module = dep_sokol.module("sokol"),
            },
            .{
                .name = "zecs",
                .module = dep_zecs.module("zig-ecs"),
            },
            .{
                .name = "cimgui",
                .module = dep_cimgui.module("cimgui"),
            },
            .{ .name = "implot", .module = implot_module },
            .{
                .name = "tracy",
                .module = tracy.module("tracy"),
            },
            // .{ .name = "shader", .module = try createShaderModule(b, dep_sokol) },
            .{
                .name = "zflecs",
                .module = zflecs.module("root"),
            },
            .{
                .name = "zcs",
                .module = zcs.module("zcs"),
            },
            .{
                .name = "sqlite",
                .module = sqlite.module("sqlite"),
            },
        },
    });

    if (!target.result.cpu.arch.isWasm()) {
        const exe = b.addExecutable(.{
            .name = "Price of Power",
            .root_module = mod,
        });
        b.installArtifact(exe);

        // const lib = b.addLibrary(.{
        //     .linkage = .static,
        //     .name = "implot",
        //     .root_module = mod,
        // });
        // b.installArtifact(lib);

        b.step("run", "Run Price of Power example").dependOn(&b.addRunArtifact(exe).step);

        const install_resources = b.addInstallDirectory(.{
            .source_dir = b.path("db"),
            .install_dir = .bin,
            .install_subdir = "db",
        });
        exe.step.dependOn(&install_resources.step);
    }

    // var deps = [_]Dep{
    //     .{ .module = dep_sokol.module("sokol"), .name = "sokol", .root_path = "sokol", .use_emscripten = true, .builder = dep_sokol.builder },
    //     .{ .module = dep_cimgui.module("cimgui"), .name = "cimgui", .root_path = "cimgui" },
    //     // .{ .d = dep_zecs, .name = "zecs", .root_path = "zig-ecs" },
    //     .{ .module = tracy.module("tracy"), .name = "tracy", .root_path = "tracy" },
    //     .{ .module = zflecs.module("root"), .name = "zflecs", .root_path = "root", .artifact = zflecs.artifact("flecs") },
    //     .{ .module = zcs.module("zcs"), .name = "zcs", .root_path = "zcs" },
    //     .{ .module = sqlite.module("sqlite"), .name = "sqlite", .root_path = "sqlite" },
    // };

    // special case handling for native vs web build
    // const opts = Options{ .mod = mod, .dep_sokol = dep_sokol };
    if (target.result.cpu.arch.isWasm()) {
        // try buildWeb(b, opts, deps);
        try buildWeb(b, mod);
    } else {
        // try buildNative(b, opts, &deps);
        // try buildNative(b, mod);
    }
}

fn buildNative(
    b: *std.Build,
    mod: *std.Build.Module,
) !void {
    const exe = b.addExecutable(.{
        .name = "Price of Power",
        .root_module = mod,
    });
    // exe.root_module.addImport("skgui", mod);
    b.installArtifact(exe);
    b.step("run", "Run Price of Power example").dependOn(&b.addRunArtifact(exe).step);
}

// fn buildWeb(b: *std.Build, opts: Options, deps: []Dep) !void {
fn buildWeb(b: *std.Build, mod: *std.Build.Module) !void {
    const lib = b.addLibrary(.{
        .name = "Price of Power",
        .root_module = mod,
    });

    lib.root_module.addImport("mod", mod);
    // for (deps) |dep| {
    //     lib.root_module.addImport(dep.name, dep.module);
    //     if (dep.artifact != null) {
    //         lib.root_module.linkLibrary(dep.artifact.?);
    //     }
    //     if (dep.use_emscripten) {
    //         const emsdk = dep.builder.?.dependency("emsdk", .{});
    //         const link_step = try sokol.emLinkStep(b, .{
    //             .lib_main = lib,
    //             .target = opts.mod.resolved_target.?,
    //             .optimize = opts.mod.optimize.?,
    //             .emsdk = emsdk,
    //             .use_webgl2 = true,
    //             .use_emmalloc = true,
    //             .use_filesystem = false,
    //             .shell_file_path = opts.dep_sokol.path("src/sokol/web/shell.html"),
    //         });
    //         b.getInstallStep().dependOn(&link_step.step);
    //         const run = sokol.emRunStep(b, .{ .name = "Price of Power", .emsdk = emsdk });
    //         run.step.dependOn(&link_step.step);
    //         b.step("run", "Run Price of Power").dependOn(&run.step);
    //     }
    // }
}

fn buildImgui(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const mod_name = "cimgui";

    // -------
    // module
    // -------
    const step = b.addTranslateC(.{
        .root_source_file = b.path("lib/libzig/implot/impl_implot.h"),
        .target = target,
        .optimize = optimize,
    });

    // step.addIncludePath(b.path("./lib/libzig"));
    step.addIncludePath(b.path("./lib/libzig/implot"));
    step.addIncludePath(b.path("./lib/libc/dcimgui"));
    step.addIncludePath(b.path("./lib/libc/imgui"));
    step.addIncludePath(b.path("./lib/libc/cimplot"));
    step.defineCMacro("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    //
    const mod = step.addModule(mod_name);
    mod.addImport(mod_name, mod);
    mod.addIncludePath(b.path("./lib/libc/dcimgui/imgui"));
    mod.addIncludePath(b.path("./lib/libc/dcimgui"));
    mod.addIncludePath(b.path("./lib/libc/imgui"));
    mod.addIncludePath(b.path("./lib/libc/cimplot"));
    mod.addIncludePath(b.path("./lib/libc/cimplot/implot"));
    mod.addIncludePath(b.path("./lib/libzig/implot"));
    // macro
    mod.addCMacro("ImDrawIdx", "unsigned int");
    //mod.addCMacro("IMGUI_DISABLE_OBSOLETE_FUNCTIONS", "1");

    mod.addCSourceFiles(.{
        .files = &.{
            "lib/libc/cimplot/cimplot.cpp",
            "lib/libc/cimplot/implot/implot.cpp",
            "lib/libc/cimplot/implot/implot_demo.cpp",
            "lib/libc/cimplot/implot/implot_items.cpp",
        },
    });

    // const lib = b.addLibrary(.{
    //     .linkage = .static,
    //     .name = "implot",
    //     .root_module = mod,
    // });
    // b.installArtifact(lib);
    //std.debug.print("{s} module\n",.{mod_name});
    return mod;




    // -------
    // module
    // -------
    const step = b.addTranslateC(.{
        .root_source_file = b.path("lib/libc/cimgui/cimgui.h"),
        .target = target,
        .optimize = optimize,
    });

    step.defineCMacro("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    const mod = step.addModule(mod_name);
    mod.addImport(mod_name, mod);
    mod.addIncludePath(b.path("../../libc/cimgui/imgui"));
    mod.addIncludePath(b.path("../../libc/cimgui/imgui/backends"));
    mod.addIncludePath(b.path("../../libc/cimgui"));
    mod.addIncludePath(b.path("../utils"));
    // macro
    mod.addCMacro("IMGUI_ENABLE_WIN32_DEFAULT_IME_FUNCTIONS", "");
    mod.addCMacro("ImDrawIdx", "unsigned int");
    //mod.addCMacro("IMGUI_DISABLE_OBSOLETE_FUNCTIONS", "1");
    switch (builtin.target.os.tag) {
        .windows => mod.addCMacro("IMGUI_IMPL_API", "extern \"C\" __declspec(dllexport)"),
        .linux => mod.addCMacro("IMGUI_IMPL_API", "extern \"C\"  "),
        else => {},
    }
    mod.addCSourceFiles(.{
        .files = &.{
            // ImGui
            "../../libc/cimgui/imgui/imgui.cpp",
            "../../libc/cimgui/imgui/imgui_tables.cpp",
            "../../libc/cimgui/imgui/imgui_demo.cpp",
            "../../libc/cimgui/imgui/imgui_widgets.cpp",
            "../../libc/cimgui/imgui/imgui_draw.cpp",
            // CImGui
            "../../libc/cimgui/cimgui.cpp",
            "../../libc/cimgui/cimgui_impl.cpp",
            // ImGui GLFW and OpenGL interface
            //"../utils/themeGold.cpp",
        },
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = mod_name,
        .root_module = mod,
    });
    b.installArtifact(lib);
    //std.debug.print("{s} module\n",.{mod_name});
























}

fn buildImplot(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const mod_name = "implot";

    // -------
    // module
    // -------
    const step = b.addTranslateC(.{
        .root_source_file = b.path("lib/libzig/implot/impl_implot.h"),
        .target = target,
        .optimize = optimize,
    });

    // step.addIncludePath(b.path("./lib/libzig"));
    step.addIncludePath(b.path("./lib/libzig/implot"));
    step.addIncludePath(b.path("./lib/libc/dcimgui"));
    step.addIncludePath(b.path("./lib/libc/imgui"));
    step.addIncludePath(b.path("./lib/libc/cimplot"));
    step.defineCMacro("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    //
    const mod = step.addModule(mod_name);
    mod.addImport(mod_name, mod);
    mod.addIncludePath(b.path("./lib/libc/dcimgui/imgui"));
    mod.addIncludePath(b.path("./lib/libc/dcimgui"));
    mod.addIncludePath(b.path("./lib/libc/imgui"));
    mod.addIncludePath(b.path("./lib/libc/cimplot"));
    mod.addIncludePath(b.path("./lib/libc/cimplot/implot"));
    mod.addIncludePath(b.path("./lib/libzig/implot"));
    // macro
    mod.addCMacro("ImDrawIdx", "unsigned int");
    //mod.addCMacro("IMGUI_DISABLE_OBSOLETE_FUNCTIONS", "1");

    mod.addCSourceFiles(.{
        .files = &.{
            "lib/libc/cimplot/cimplot.cpp",
            "lib/libc/cimplot/implot/implot.cpp",
            "lib/libc/cimplot/implot/implot_demo.cpp",
            "lib/libc/cimplot/implot/implot_items.cpp",
        },
    });

    // const lib = b.addLibrary(.{
    //     .linkage = .static,
    //     .name = "implot",
    //     .root_module = mod,
    // });
    // b.installArtifact(lib);
    //std.debug.print("{s} module\n",.{mod_name});
    return mod;
}
