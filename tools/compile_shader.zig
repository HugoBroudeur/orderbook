const std = @import("std");
const builtin = @import("builtin");

const SHADER_FOLDER = "src/shaders";
const MAX_OUTPUT_SIZE = 100 * 1024 * 1024;

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

const ShaderFileType = enum {
    spirv,
    slang,
    fn toExtention(self: ShaderFileType) []const u8 {
        return switch (self) {
            .spirv => ".spv",
            .slang => ".slang",
        };
    }
};

const FileInfo = struct {
    last_update_time_ms: i128,
    name: []const u8,

    pub fn stem(self: FileInfo) []const u8 {
        return std.fs.path.stem(self.name);
    }
};

const ShaderFiles = struct {
    slang: FileInfo,
    spirv: FileInfo,

    pub fn shouldRecompile(self: ShaderFiles) bool {
        return self.slang.last_update_time_ms > self.spirv.last_update_time_ms;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allo = gpa.allocator();

    var files = try std.ArrayList(ShaderFiles).initCapacity(allo, 1);
    defer files.deinit(allo);

    var compiler = try Compiler.init(allo);
    try compiler.loadFiles(SHADER_FOLDER);

    var mutex = std.Thread.Mutex{};
    try compiler.compile(&mutex);
}

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    shader_files: std.ArrayList(ShaderFiles),
    pub fn init(allocator: std.mem.Allocator) !Compiler {
        return .{ .allocator = allocator, .shader_files = try .initCapacity(allocator, 1) };
    }
    pub fn deinit(self: *Compiler) void {
        self.shader_files.deinit(self.allocator);
    }

    pub fn compile(self: *Compiler, lock: *std.Thread.Mutex) !void {
        for (self.shader_files.items) |shader_file| {
            if (shader_file.shouldRecompile()) {
                const result = try self.runCmd(
                    lock,
                    shader_file.slang.name,
                );
                const file = std.fs.path.stem(shader_file.slang.name);

                if (result.code > 0) {
                    std.log.err("Slang command exited with code {}", .{result.code});

                    const cmd_args = try self.getCmd(shader_file.slang.name);
                    defer self.allocator.free(cmd_args);

                    const joined = try std.mem.join(self.allocator, " ", cmd_args);
                    defer self.allocator.free(joined);

                    std.log.err("{s}", .{joined});

                    // std.log.err("{s}", .{try getCmd(args.allocator, filename)});
                    std.log.err("{s}", .{result.stderr});
                } else {
                    const output = std.fmt.allocPrint(self.allocator, "{s}/{s}.spv", .{
                        SHADER_FOLDER,
                        file,
                    }) catch unreachable;
                    std.log.info("[CompileShader] Compile Shader {s}", .{output});
                }
            }
        }
    }

    fn getCmd(
        self: *Compiler,
        filename: []const u8,
    ) ![]const []const u8 {
        const input = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{
            SHADER_FOLDER,
            filename,
        }) catch unreachable;
        const output = std.fmt.allocPrint(self.allocator, "{s}/{s}.spv", .{
            SHADER_FOLDER,
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

        const cmd_args = try self.allocator.alloc([]const u8, args.len);
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
        self: *Compiler,
        mutex: *std.Thread.Mutex,
        filename: []const u8,
    ) !CmdResult {
        mutex.lock();
        defer mutex.unlock();

        // std.debug.print("Generating sokol zig shader for: {s}", .{input});
        const cmd_args = try self.getCmd(filename);
        var cmd = std.process.Child.init(
            cmd_args,
            self.allocator,
        );

        cmd.stdout_behavior = .Pipe;
        cmd.stderr_behavior = .Pipe;

        var stdout_buffer: std.ArrayList(u8) = .empty;
        defer stdout_buffer.deinit(self.allocator);

        var stderr_buffer: std.ArrayList(u8) = .empty;
        defer stderr_buffer.deinit(self.allocator);

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
            .stdout = try stdout_buffer.toOwnedSlice(self.allocator),
            .stderr = try stderr_buffer.toOwnedSlice(self.allocator),
        };
    }

    pub fn getFilesByExtention(a: std.mem.Allocator, dir_path: []const u8, shader_type: ShaderFileType) ![]const FileInfo {
        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();

        var files = try std.ArrayList(FileInfo).initCapacity(a, 1);
        defer files.deinit(a);

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const extension = std.fs.path.extension(entry.name);
            if (entry.kind == .file and std.mem.eql(u8, extension, shader_type.toExtention())) {
                const stat = try dir.statFile(entry.name);
                const owned_name = try a.dupe(u8, entry.name);
                const file_info: FileInfo = .{ .name = owned_name, .last_update_time_ms = stat.mtime };

                try files.append(a, file_info);
            }
        }

        return files.toOwnedSlice(a);
    }

    pub fn loadFiles(self: *Compiler, dir_path: []const u8) !void {
        const slang_files = try getFilesByExtention(self.allocator, dir_path, .slang);
        defer self.allocator.free(slang_files);

        const spirv_files = try getFilesByExtention(self.allocator, dir_path, .spirv);
        defer self.allocator.free(spirv_files);

        for (slang_files) |slang| {
            // Find the matching .spirv by stem
            const spirv: FileInfo = blk: {
                for (spirv_files) |spirv| {
                    if (std.mem.eql(u8, std.fs.path.stem(slang.name), std.fs.path.stem(spirv.name))) {
                        break :blk spirv;
                    }
                }
                // No matching .spirv found — treat as missing/never compiled
                break :blk .{
                    .name = slang.name,
                    .last_update_time_ms = 0,
                };
            };

            try self.shader_files.append(self.allocator, .{
                .slang = slang,
                .spirv = spirv,
            });
        }
    }

    fn fatal(comptime format: []const u8, args: anytype) noreturn {
        std.debug.print(format, args);
        std.process.exit(1);
    }
};
