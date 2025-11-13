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
    cname: []const u8 = "",
    root_path: []const u8,
    d: *std.Build.Dependency,
    is_link: bool = false,
    use_emscripten: bool = false,
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
        // .name = "orderbook",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "networking", .module = mod_networking },
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
            // .{ .name = "shader", .module = try createShaderModule(b, dep_sokol) },
        },
    });

    // b.installArtifact(exe);

    var deps = [_]Dep{
        .{ .d = dep_sokol, .name = "sokol", .root_path = "sokol", .use_emscripten = true },
        .{ .d = dep_cimgui, .name = "cimgui", .root_path = "cimgui" },
        .{ .d = dep_zecs, .name = "zecs", .root_path = "zig-ecs" },
        // .{ .d = dep_zecs, .name = "zflecs", .cname = "flecs", .root_path = "root", .is_link = true },
    };

    // special case handling for native vs web build
    const opts = Options{ .mod = mod, .dep_sokol = dep_sokol };
    if (target.result.cpu.arch.isWasm()) {
        try buildWeb(b, opts, &deps);
    } else {
        try buildNative(b, opts, &deps);
    }

    // const run_step = b.step("run", "Run the app");
    //
    // const run_cmd = b.addRunArtifact(exe);
    // run_step.dependOn(&run_cmd.step);
    //
    // run_step.dependOn(gen_proto);
    //
    // run_cmd.step.dependOn(b.getInstallStep());
    //
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }
    //
    // const mod_tests = b.addTest(.{
    //     .root_module = mod_networking,
    // });
    //
    // // A run step that will run the test executable.
    // const run_mod_tests = b.addRunArtifact(mod_tests);
    //
    // const exe_tests = b.addTest(.{
    //     .root_module = exe.root_module,
    // });
    //
    // const run_exe_tests = b.addRunArtifact(exe_tests);
    //
    // const test_step = b.step("test", "Run tests");
    // test_step.dependOn(&run_mod_tests.step);
    // test_step.dependOn(&run_exe_tests.step);
}

// fn generateProtobuf(b: *std.Build, proto_dep: *std.Build.Dependency, target: std.Build.ResolvedTarget) void {
//     const gen_proto = b.step("gen-proto", "generate zig files from protocol buffer definitions");
//
//     const protoc_step = protobuf.RunProtocStep.create(proto_dep.*.builder, target, .{
//         .destination_directory = b.path("src/proto"),
//         .source_files = &.{main_proto_entry},
//         .include_directories = &.{},
//     });
//
//     std.log.info("Hello from build", .{});
//     gen_proto.dependOn(&protoc_step.step);
// }

fn buildNative(b: *std.Build, opts: Options, deps: []Dep) !void {
    const exe = b.addExecutable(.{
        .name = "Price of Power",
        .root_module = opts.mod,
    });

    for (deps) |dep| {
        exe.root_module.addImport(dep.name, dep.d.module(dep.root_path));
        if (dep.is_link) {
            exe.linkLibrary(dep.d.artifact(dep.cname));
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
        lib.root_module.addImport(dep.name, dep.d.module(dep.root_path));
        if (dep.is_link) {
            lib.linkLibrary(dep.d.artifact(dep.name));
        }
        if (dep.use_emscripten) {
            const emsdk = dep.d.builder.dependency("emsdk", .{});
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
