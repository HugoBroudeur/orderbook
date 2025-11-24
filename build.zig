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
        },
    });

    var deps = [_]Dep{
        .{ .module = dep_sokol.module("sokol"), .name = "sokol", .root_path = "sokol", .use_emscripten = true, .builder = dep_sokol.builder },
        .{ .module = dep_cimgui.module("cimgui"), .name = "cimgui", .root_path = "cimgui" },
        // .{ .d = dep_zecs, .name = "zecs", .root_path = "zig-ecs" },
        .{ .module = tracy.module("tracy"), .name = "tracy", .root_path = "tracy" },
        .{ .module = zflecs.module("root"), .name = "zflecs", .root_path = "root", .artifact = zflecs.artifact("flecs") },
        .{ .module = zcs.module("zcs"), .name = "zcs", .root_path = "zcs" },
    };

    // special case handling for native vs web build
    const opts = Options{ .mod = mod, .dep_sokol = dep_sokol };
    if (target.result.cpu.arch.isWasm()) {
        try buildWeb(b, opts, &deps);
    } else {
        try buildNative(b, opts, &deps);
    }
}

fn buildNative(b: *std.Build, opts: Options, deps: []Dep) !void {
    const exe = b.addExecutable(.{
        .name = "Price of Power",
        .root_module = opts.mod,
    });

    const mod_ecs = b.createModule(.{
        .root_source_file = b.path("src/game/ecs/ecs.zig"),
    });

    for (deps) |dep| {
        mod_ecs.addImport(dep.name, dep.module);
    }

    exe.root_module.addImport("ecs", mod_ecs);

    for (deps) |dep| {
        exe.root_module.addImport(dep.name, dep.module);
        if (dep.artifact != null) {
            exe.root_module.linkLibrary(dep.artifact.?);
        }
    }

    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    b.step("run", "Run Price of Power").dependOn(&run.step);
}

fn buildWeb(b: *std.Build, opts: Options, deps: []Dep) !void {
    const lib = b.addLibrary(.{
        .name = "Price of Power",
        .root_module = opts.mod,
    });

    for (deps) |dep| {
        lib.root_module.addImport(dep.name, dep.module);
        if (dep.artifact != null) {
            lib.root_module.linkLibrary(dep.artifact.?);
        }
        if (dep.use_emscripten) {
            const emsdk = dep.builder.?.dependency("emsdk", .{});
            const link_step = try sokol.emLinkStep(b, .{
                .lib_main = lib,
                .target = opts.mod.resolved_target.?,
                .optimize = opts.mod.optimize.?,
                .emsdk = emsdk,
                .use_webgl2 = true,
                .use_emmalloc = true,
                .use_filesystem = false,
                .shell_file_path = opts.dep_sokol.path("src/sokol/web/shell.html"),
            });
            b.getInstallStep().dependOn(&link_step.step);
            const run = sokol.emRunStep(b, .{ .name = "Price of Power", .emsdk = emsdk });
            run.step.dependOn(&link_step.step);
            b.step("run", "Run Price of Power").dependOn(&run.step);
        }
    }
}
