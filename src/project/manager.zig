const std = @import("std");
const log = std.log.scoped(.project_manager);

const zgui = @import("zgui");
const Config = @import("../config.zig");
const SceneManager = @import("../scene_management/manager.zig");
const AssetManager = @import("../resource_management/manager.zig");
const RenderSettings = @import("../engine/settings.zig");
const Engine = @import("../engine/vulkan/engine.zig");
const Uuid = @import("uuid");
const serde = @import("serde");

pub const PROJECT_FILE_EXTENSION = ".dlproj";
pub const PROJECT_FILENAME = "main";

const Manager = @This();

allocator: std.mem.Allocator,
io: std.Io,
config: Config,

project_name: []const u8 = "",
project_folder: []const u8 = "",
project_file: ProjectFile = .{},
loaded: bool = false,

scene_manager: *SceneManager,
asset_manager: *AssetManager,

pub const ProjectFile = struct {
    boot_scene_guid: Uuid.Uuid = 0,
    render_settings: RenderSettings = .{},

    pub fn init(boot_scene_guid: Uuid) ProjectFile {
        return .{ .boot_scene_guid = boot_scene_guid };
    }

    pub fn save(self: *const ProjectFile, allocator: std.mem.Allocator, io: std.Io, project_filepath: []const u8) !void {
        const file_content = try serde.zon.toSlice(allocator, self);
        defer allocator.free(file_content);

        const cwd = std.Io.Dir.cwd();
        try cwd.createDirPath(io, project_filepath);

        const file_name = try computeProjectFilePath(allocator, project_filepath);
        defer allocator.free(file_name);

        try std.Io.Dir.writeFile(.cwd(), io, .{ .data = file_content, .sub_path = file_name, .flags = .{ .resolve_beneath = true } });
    }

    pub fn load(allocator: std.mem.Allocator, io: std.Io, project_filepath: []const u8) !ProjectFile {
        const file_name = try computeProjectFilePath(allocator, project_filepath);
        defer allocator.free(file_name);

        const cwd = std.Io.Dir.cwd();
        const content = try cwd.readFileAlloc(io, file_name, allocator, .unlimited);
        defer allocator.free(content);

        return try serde.zon.fromSlice(ProjectFile, allocator, content);
    }

    fn computeProjectFilePath(allocator: std.mem.Allocator, project_filepath: []const u8) ![]const u8 {
        return try std.mem.concat(allocator, u8, &.{
            project_filepath,
            "/",
            PROJECT_FILENAME,
            PROJECT_FILE_EXTENSION,
        });
    }
};

// ============================================================================
// PROJECT MANAGER
// ============================================================================

pub fn init(allocator: std.mem.Allocator, io: std.Io, config: Config, scene_manager: *SceneManager, asset_manager: *AssetManager) Manager {
    return .{
        .allocator = allocator,
        .io = io,
        .config = config,
        .scene_manager = scene_manager,
        .asset_manager = asset_manager,
    };
}

pub fn deinit(self: *Manager) void {
    _ = self;
}

pub fn new(self: *Manager, name: []const u8) !void {
    const project_path = try self.computeProjectPath(name);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(self.io, project_path);

    const project_file = ProjectFile.init(Uuid.v4.new(self.io));
    try project_file.save(self.allocator, self.io, project_path);

    try self.open(project_path);
}

// TODO, remove dependency with Engine
pub fn open(self: *Manager, name: []const u8) !void {
    const project_path = try self.computeProjectPath(name);

    const project_file = ProjectFile.load(self.allocator, self.io, project_path) catch |err| {
        log.err("Fail to open project {s}. Reason: {}", .{ name, err });
        return;
    };

    log.info(
        \\
        \\ Open project 
        \\ Name         {s}
        \\ Path:        {s}
        \\ ID:          {}
        \\
    , .{ name, project_path, project_file.boot_scene_guid });

    self.project_name = name;
    self.project_file = project_file;
    self.project_folder = project_path;

    try self.asset_manager.loadAssetPool(self.project_folder);
    try self.scene_manager.loadScenes(self.project_folder);

    self.loaded = true;
}

pub fn save(self: *Manager) !void {
    if (!self.loaded) {
        log.err("No project opened", .{});
    }

    const project_path = try self.computeProjectPath(self.project_name);
    try self.project_file.save(self.allocator, self.io, project_path);

    try self.scene_manager.saveScenes(self.project_folder);
    try self.asset_manager.saveAssetPool(self.project_folder);

    log.info(
        \\
        \\ Save project 
        \\ Name         {s}
        \\ Path:        {s}
        \\ ID:          {}
        \\
    , .{ self.project_name, self.project_folder, self.project_file.boot_scene_guid });
}

pub fn close(self: *Manager) void {
    self.loaded = false;

    // TODO
}

fn computeProjectPath(self: *const Manager, project_name: []const u8) ![]const u8 {
    const base_project_path = try self.allocator.alloc(u8, std.mem.replacementSize(u8, self.config.base_project_path, "$HOME", self.config.home_path));
    defer self.allocator.free(base_project_path);
    _ = std.mem.replace(u8, self.config.base_project_path, "$HOME", self.config.home_path, base_project_path);

    return try std.mem.concat(self.allocator, u8, &.{
        base_project_path,
        project_name,
    });
}

// -- Queries -----------------------------------------------------------------

pub fn projectIsOpen(self: *const Manager) bool {
    return self.project_folder.len > 0;
}

pub fn getProjectName(self: *const Manager) []const u8 {
    return std.fs.path.basename(self.project_folder);
}

pub fn getProjectFolder(self: *const Manager) []const u8 {
    return self.project_folder;
}

pub fn getSceneManager(self: *const Manager) *SceneManager {
    return self.scene_manager;
}

pub fn getAssetManager(self: *const Manager) *AssetManager {
    return self.asset_manager;
}

// -- Boot scene --------------------------------------------------------------

pub fn setBootSceneGuid(self: *Manager, guid: Uuid) void {
    self.project_file.boot_scene_guid = guid;
}

pub fn getBootSceneGuid(self: *const Manager) Uuid {
    return self.project_file.boot_scene_guid;
}

pub fn isBootScene(self: *const Manager, guid: Uuid) bool {
    return self.project_file.boot_scene_guid == guid;
}
