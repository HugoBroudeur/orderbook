const std = @import("std");
const log = std.log.scoped(.scene_manager);
const serde = @import("serde");
const Uuid = @import("uuid");
const Scene = @import("scene.zig");
const World = @import("../../ecs/world.zig");

pub const SCENE_FILE_EXTENSION = ".dlscene";

const SceneManager = @This();

allocator: std.mem.Allocator = undefined,
io: std.Io = undefined,

scenes: std.hash_map.AutoHashMap(Uuid.Uuid, Scene) = undefined,
runtime_scenes: std.hash_map.AutoHashMap(Uuid.Uuid, Scene) = undefined,
active_scenes: *std.hash_map.AutoHashMap(Uuid.Uuid, Scene) = undefined,

loaded_scene_guid: Uuid.Uuid = 0,

world: *World = undefined,

pub fn init(self: *SceneManager, allocator: std.mem.Allocator, io: std.Io, world: *World) void {
    self.* = .{
        .allocator = allocator,
        .io = io,
        .scenes = .init(allocator),
        .runtime_scenes = .init(allocator),
        .world = world,
    };

    self.active_scenes = &self.scenes;
}

pub fn deinit(self: *SceneManager) void {
    self.scenes.deinit();
    self.runtime_scenes.deinit();
}

pub fn createScene(self: *SceneManager, name: []const u8) !Uuid.Uuid {
    const scene: Scene = .{
        .name = name,
        .guid = Uuid.v4.new(self.io),
    };

    _ = try self.active_scenes.fetchPut(scene.guid, scene);
    log.info("Created new scene [{s} | GUID:{}]", .{ scene.name, scene.guid });

    return scene.guid;
}

pub fn setLoadedScene(self: *SceneManager, guid: Uuid.Uuid) bool {
    const scene = self.active_scenes.get(guid);
    if (scene == null) {
        log.err("Cannot find scene [GUID:{}]", .{guid});
        return false;
    }

    self.loaded_scene_guid = guid;
    log.info("Set current scene [{s} | GUID:{}]", .{ scene.?.name, guid });
    return true;
}

pub fn saveScenes(self: *SceneManager, project_path: []const u8) !void {
    log.debug("Saving at {s}", .{project_path});
    const dir = try std.Io.Dir.cwd().openDir(self.io, project_path, .{ .iterate = true });

    // Delete orphan scenes
    var it = dir.iterate();
    while (try it.next(self.io)) |entry| {
        if (.file != entry.kind) {
            continue;
        }
        if (null == std.mem.find(u8, entry.name, SCENE_FILE_EXTENSION)) {
            continue;
        }

        if (extractGuidFromSceneName(entry.name)) |guid| {
            if (null != self.active_scenes.get(guid)) {
                continue;
            }

            // The file is not part of the active scene, delete it
            try dir.deleteFile(self.io, entry.name);
        }
    }

    var scenes_it = self.scenes.iterator();
    while (scenes_it.next()) |entry| {
        const content = SceneSerializer.serialize(self.allocator, self.world, entry.value_ptr.*) catch |err| {
            log.err("Fail to serialize scene [{s} | GUID:{}]. Reason {}. Skipping saving this scene", .{ entry.value_ptr.name, entry.key_ptr, err });
            continue;
        };

        dir.writeFile(self.io, .{ .data = content, .sub_path = self.getSceneName(entry.key_ptr.*), .flags = .{} }) catch |err| {
            log.err("Fail to save scene [{s} | GUID:{}]. Reason {}. Skipping saving this scene", .{ entry.value_ptr.name, entry.key_ptr, err });

            continue;
        };
    }
}
pub fn loadScenes(self: *SceneManager, project_path: []const u8) !void {
    _ = self;
    _ = project_path;
}

fn getSceneName(self: *SceneManager, guid: Uuid.Uuid) []const u8 {
    return std.fmt.allocPrint(self.allocator, "{}{s}", .{ guid, SCENE_FILE_EXTENSION }) catch "out_of_memory" ++ SCENE_FILE_EXTENSION;
}

fn extractGuidFromSceneName(scene_name: []const u8) ?Uuid.Uuid {
    if (!std.mem.endsWith(u8, scene_name, SCENE_FILE_EXTENSION)) return null;
    const stem = std.fs.path.stem(scene_name);
    return std.fmt.parseInt(Uuid.Uuid, stem, 10) catch null;
}

const EntityData = struct {
    entity_guid: ?World.Components.ID = null,
    entity_tag: ?World.Components.Tag = null,
    transforms: struct {
        translation: ?World.Components.Translation = null,
        rotation: ?World.Components.Rotation = null,
        scale: ?World.Components.Scale = null,
    } = .{},
};

const SceneData = struct {
    scene_guid: Uuid.Uuid,
    scene_name: []const u8,
    entities: []EntityData,
};
const SceneSerializer = struct {
    pub fn serialize(allocator: std.mem.Allocator, world: *World, scene: Scene) ![]const u8 {
        var scene_data: SceneData = undefined;

        scene_data.scene_guid = scene.guid;
        scene_data.scene_name = scene.name;

        var entities: std.ArrayList(EntityData) = .empty;
        defer entities.deinit(allocator);

        const query_all = try World.Ecs.Query(struct { entity: World.Ecs.Entity }).fromWorld(world.app);

        var it = query_all.iter();
        while (it.next()) |entry| {
            var entity_data: EntityData = .{};
            if (world.app.components.getSingle(entry.entity, World.Components.ID)) |guid| {
                entity_data.entity_guid = guid.*;
            }
            if (world.app.components.getSingle(entry.entity, World.Components.Translation)) |translation| {
                entity_data.transforms.translation = translation.*;
            }
            log.info("{}", .{entity_data});

            try entities.append(allocator, entity_data);
        }

        scene_data.entities = entities.items;

        return try serde.zon.toSlice(allocator, scene_data);
    }

    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) []const u8 {
        _ = allocator; // autofix
        _ = data; // autofix
        // return try serde.zon.toSlice(allocator, scene);
    }
};
