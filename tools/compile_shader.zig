const std = @import("std");
const builtin = @import("builtin");

const shader_folder = "src/shaders";
const max_output_size = 100 * 1024 * 1024;

const GenerateShaderArgs = struct {
    l: *std.Thread.Mutex,
    allocator: std.mem.Allocator,
};
const GenerateShaderCmdArgs = struct {
    l: *std.Thread.Mutex,
    allocator: std.mem.Allocator,
    filename: []const u8,
};

const CmdResult = struct {
    code: u8,
    term: std.process.Child.Term,
    stdout: []const u8,
    stderr: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allo = gpa.allocator();

    var mutex = std.Thread.Mutex{};
    try compileSlangShaders(.{
        .allocator = allo,
        .l = &mutex,
    });
}

pub fn compileSlangShaders(args: GenerateShaderArgs) !void {
    const files = try getFilesByExtention(args.allocator, shader_folder, ".slang");
    for (files) |filename| {
        const result = try runCmd(
            args.l,
            args.allocator,
            filename,
        );
        const file = std.fs.path.stem(filename);

        if (result.code > 0) {
            std.log.err("Slang command exited with code {}", .{result.code});

            const cmd_args = try getCmd(args.allocator, filename);
            defer args.allocator.free(cmd_args);

            const joined = try std.mem.join(args.allocator, " ", cmd_args);
            defer args.allocator.free(joined);

            std.log.err("{s}", .{joined});

            // std.log.err("{s}", .{try getCmd(args.allocator, filename)});
            std.log.err("{s}", .{result.stderr});
        } else {
            const output = std.fmt.allocPrint(args.allocator, "{s}/{s}.spv", .{
                shader_folder,
                file,
            }) catch unreachable;
            std.log.info("[CompileShader] Compile Shader {s}", .{output});
        }
    }
}

fn getCmd(
    allocator: std.mem.Allocator,
    filename: []const u8,
) ![]const []const u8 {
    const input = std.fmt.allocPrint(allocator, "{s}/{s}", .{
        shader_folder,
        filename,
    }) catch unreachable;
    const output = std.fmt.allocPrint(allocator, "{s}/{s}.spv", .{
        shader_folder,
        std.fs.path.stem(filename),
    }) catch unreachable;

    const args = [_][]const u8{
        "slangc",
        "-target",
        "spirv",
        "-fvk-use-entrypoint-name",
        "-capability",
        "GL_EXT_buffer_reference",
        "-capability",
        "SPV_EXT_physical_storage_buffer",
        "-o",
        output,
        input,
    };

    const cmd_args = try allocator.alloc([]const u8, args.len);
    for (args, 0..) |arg, i| {
        cmd_args[i] = arg;
    }

    return cmd_args;

    // std.debug.print("Generating sokol zig shader for: {s}", .{input});
    // return .{
    //     "slangc",
    //     "-target",
    //     "spirv",
    //     "-fvk-use-entrypoint-name",
    //     "-capacity",
    //     "GL_EXT_buffer_reference",
    //     "-o",
    //     output,
    //     input,
    // };
}

pub fn runCmd(
    mutex: *std.Thread.Mutex,
    allocator: std.mem.Allocator,
    filename: []const u8,
) !CmdResult {
    mutex.lock();
    defer mutex.unlock();

    // std.debug.print("Generating sokol zig shader for: {s}", .{input});
    const cmd_args = try getCmd(allocator, filename);
    var cmd = std.process.Child.init(
        cmd_args,
        allocator,
    );

    cmd.stdout_behavior = .Pipe;
    cmd.stderr_behavior = .Pipe;

    var stdout_buffer: std.ArrayList(u8) = .empty;
    defer stdout_buffer.deinit(allocator);

    var stderr_buffer: std.ArrayList(u8) = .empty;
    defer stderr_buffer.deinit(allocator);

    try cmd.spawn();
    // try cmd.collectOutput(allocator, &stdout_buffer, &stderr_buffer, max_output_size);
    // cmd.spawn() catch |err| {
    //     std.log.err("The following command failed:\n", .{});
    //     std.log.err("{any}\n", .{err});
    //     return err;
    // };

    // var out_buf: [1024]u8 = @splat(0);
    // var err_buf: [1024]u8 = @splat(0);
    // // const stdout_bytes = try cmd.stdout.?.reader(&out_buf).readAllAlloc(args.allocator, max_output_size);
    // var out_reader = cmd.stdout.?.reader(&out_buf).interface;
    // const stdout_bytes = try out_reader.readAlloc(allocator, max_output_size);
    // errdefer allocator.free(stdout_bytes);
    // // const stderr_bytes = try cmd.stderr.?.reader(&err_buf).readAllAlloc(args.allocator, max_output_size);
    // var err_reader = cmd.stderr.?.reader(&err_buf).interface;
    // const stderr_bytes = try err_reader.readAlloc(allocator, max_output_size);
    // errdefer allocator.free(stderr_bytes);
    //

    const term = try cmd.wait();
    const code = if (term == .Exited) term.Exited else 1;

    // const spirval_cmd = [_][]const u8{
    //     "spirv-val",
    //     output,
    // };
    //
    // {
    //     var cmd_val = std.process.Child.init(
    //         &spirval_cmd,
    //         allocator,
    //     );
    //     try cmd_val.spawn();
    //     _ = try cmd_val.wait();
    // }

    return .{
        .code = code,
        .term = term,
        .stdout = try stdout_buffer.toOwnedSlice(allocator),
        .stderr = try stderr_buffer.toOwnedSlice(allocator),
    };
}

pub fn getFilesByExtention(a: std.mem.Allocator, dir_path: []const u8, ext_pattern: []const u8) ![]const []const u8 {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var files = try std.ArrayList([]const u8).initCapacity(a, 1);
    errdefer files.deinit(a);

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        const extension = std.fs.path.extension(entry.name);
        if (entry.kind == .file and std.mem.eql(u8, extension, ext_pattern)) {
            try files.append(a, try a.dupe(u8, entry.name));
        }
    }

    return files.toOwnedSlice(a);
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
