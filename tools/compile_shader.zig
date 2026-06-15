const std = @import("std");
const log = std.log.scoped(.compile_shader);
const builtin = @import("builtin");

const SHADER_FOLDER = "assets/shaders";
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
    last_update_time_ms: std.Io.Timestamp,
    name: []const u8,

    pub fn stem(self: FileInfo) []const u8 {
        return std.fs.path.stem(self.name);
    }
};

const ShaderFiles = struct {
    slang: FileInfo,
    spirv: FileInfo,

    pub fn shouldRecompile(self: ShaderFiles) bool {
        return self.slang.last_update_time_ms.toNanoseconds() > self.spirv.last_update_time_ms.toNanoseconds();
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var files = try std.ArrayList(ShaderFiles).initCapacity(allocator, 1);
    defer files.deinit(allocator);

    var compiler = try Compiler.init(allocator, io);
    try compiler.loadFiles(SHADER_FOLDER);

    try compiler.compile();
}

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    shader_files: std.ArrayList(ShaderFiles),
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Compiler {
        return .{
            .allocator = allocator,
            .shader_files = try .initCapacity(allocator, 1),
            .io = io,
        };
    }
    pub fn deinit(self: *Compiler) void {
        self.shader_files.deinit(self.allocator);
    }

    pub fn compile(self: *Compiler) !void {
        var mutex: std.Io.Mutex = .init;
        for (self.shader_files.items) |shader_file| {
            if (shader_file.shouldRecompile()) {
                const result = try self.runCmd(
                    &mutex,
                    shader_file.slang.name,
                );
                const file = std.fs.path.stem(shader_file.slang.name);

                if (result.code > 0) {
                    log.err("Slang command exited with code {}", .{result.code});

                    const cmd_args = try self.getCmd(shader_file.slang.name);
                    defer self.allocator.free(cmd_args);

                    const joined = try std.mem.join(self.allocator, " ", cmd_args);
                    defer self.allocator.free(joined);

                    log.err("{s}", .{joined});

                    // log.err("{s}", .{try getCmd(args.allocator, filename)});
                    log.err("{s}", .{result.stderr});
                    return error.CompileShaderError;
                } else {
                    const output = std.fmt.allocPrint(self.allocator, "{s}/{s}.spv", .{
                        SHADER_FOLDER,
                        file,
                    }) catch unreachable;
                    log.info("[CompileShader] Compile Shader {s}", .{output});
                    log.info("{s}", .{result.stdout});
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
    }

    pub fn runCmd(
        self: *Compiler,
        mutex: *std.Io.Mutex,
        filename: []const u8,
    ) !CmdResult {
        try mutex.lock(self.io);
        defer mutex.unlock(self.io);

        const cmd_args = try self.getCmd(filename);

        var cmd = try std.process.spawn(self.io, .{ .argv = cmd_args, .stdin = .pipe, .stdout = .pipe, .stderr = .pipe });

        var stdout_buffer: std.ArrayList(u8) = .empty;
        defer stdout_buffer.deinit(self.allocator);

        var stderr_buffer: std.ArrayList(u8) = .empty;
        defer stderr_buffer.deinit(self.allocator);

        const term = try cmd.wait(self.io);
        const code = if (term == .exited) term.exited else 1;

        return .{
            .code = code,
            .term = term,
            .stdout = try stdout_buffer.toOwnedSlice(self.allocator),
            .stderr = try stderr_buffer.toOwnedSlice(self.allocator),
        };
    }

    pub fn getFilesByExtention(self: *Compiler, dir_path: []const u8, shader_type: ShaderFileType) ![]const FileInfo {
        const cwd = std.Io.Dir.cwd();
        var dir = try cwd.openDir(self.io, dir_path, .{ .iterate = true });
        defer dir.close(self.io);

        var files = try std.ArrayList(FileInfo).initCapacity(self.allocator, 1);
        defer files.deinit(self.allocator);

        var iterator = dir.iterate();
        while (try iterator.next(self.io)) |entry| {
            const extension = std.fs.path.extension(entry.name);
            if (entry.kind == .file and std.mem.eql(u8, extension, shader_type.toExtention())) {
                const stat = try dir.statFile(self.io, entry.name, .{});
                const owned_name = try self.allocator.dupe(u8, entry.name);
                const file_info: FileInfo = .{ .name = owned_name, .last_update_time_ms = stat.mtime };

                try files.append(self.allocator, file_info);
            }
        }

        return files.toOwnedSlice(self.allocator);
    }

    pub fn loadFiles(self: *Compiler, dir_path: []const u8) !void {
        const slang_files = try self.getFilesByExtention(dir_path, .slang);
        defer self.allocator.free(slang_files);

        const spirv_files = try self.getFilesByExtention(dir_path, .spirv);
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
                    .last_update_time_ms = .fromNanoseconds(0),
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
