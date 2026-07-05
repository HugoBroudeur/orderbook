const std = @import("std");
const log = std.log.scoped(.scene_manager);
const Serde = @import("serde");
const Uuid = @import("uuid");
const Scene = @import("scene.zig");
const World = @import("../../ecs/world.zig");

pub const SCENE_FILE_EXTENSION = ".dlscene";

const SceneManager = @This();

allocator: std.mem.Allocator = undefined,
io: std.Io = undefined,

scenes: std.hash_map.AutoHashMap(Uuid.Uuid, Scene),
runtime_scenes: std.hash_map.AutoHashMap(Uuid.Uuid, Scene),
active_scenes: *std.hash_map.AutoHashMap(Uuid.Uuid, Scene),

current_scene_guid: Uuid.Uuid = 0,

world: *World,

buffer_parsed_scenes: std.hash_map.AutoHashMap(Uuid.Uuid, SceneData),

pub fn init(self: *SceneManager, allocator: std.mem.Allocator, io: std.Io, world: *World) void {
    self.* = .{
        .allocator = allocator,
        .io = io,
        .scenes = .init(allocator),
        .runtime_scenes = .init(allocator),
        .active_scenes = undefined,
        .world = world,
        .buffer_parsed_scenes = .init(allocator),
    };

    self.active_scenes = &self.scenes;
}

pub fn deinit(self: *SceneManager) void {
    self.scenes.deinit();
    self.runtime_scenes.deinit();
    self.buffer_parsed_scenes.deinit();
}

pub fn createScene(self: *SceneManager, name: []const u8) !Uuid.Uuid {
    const scene: Scene = .{
        .name = name,
        .guid = Uuid.v4.new(self.io),
        .reg = self.world,
    };

    _ = try self.active_scenes.fetchPut(scene.guid, scene);
    if (self.current_scene_guid == 0) _ = self.setLoadedScene(scene.guid);
    log.info("Created new scene [{s} | GUID:{}]", .{ scene.name, scene.guid });

    return scene.guid;
}

pub fn setLoadedScene(self: *SceneManager, guid: Uuid.Uuid) bool {
    const scene = self.active_scenes.get(guid) orelse {
        log.err("Cannot find scene [GUID:{}]", .{guid});
        return false;
    };
    self.current_scene_guid = guid;

    const state = self.world.app.getResource(World.Ecs.State(World.Gamestate)) catch |err| {
        log.err("Set loaded scene [GUID:{}]. Get ECS Resource World.Gamestate error: {}", .{ guid, err });
        return false;
    };
    state.set(.loading);

    log.info("Set current scene [{s} | GUID:{}]", .{ scene.name, guid });

    self.emitEcsEvent(World.Components.PendingSceneEvent, (.{ .scene_guid = guid, .manager = self })) catch |err| {
        log.err("Set loaded scene [GUID:{}]. Send ECS Event World.Components.PendingSceneEvent error: {}", .{ guid, err });
        return false;
    };

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
    const dir = try std.Io.Dir.cwd().openDir(self.io, project_path, .{ .iterate = true });
    var it = dir.iterate();
    while (try it.next(self.io)) |entry| {
        if (entry.kind != .file) continue;
        if (extractGuidFromSceneName(entry.name) == null) continue;

        const content = try dir.readFileAlloc(self.io, entry.name, self.allocator, .unlimited);
        defer self.allocator.free(content);

        // TODO: put it on the heap and copy it in the buffer, might stack overload otherwise if scene_data > 8Mb
        const scene_data = try SceneSerializer.deserialize(self.allocator, content);
        try self.buffer_parsed_scenes.put(scene_data.scene_guid, scene_data);

        const scene: Scene = .{
            .guid = scene_data.scene_guid,
            .name = scene_data.scene_name,
            .reg = self.world,
        };
        _ = try self.scenes.fetchPut(scene.guid, scene);
        if (self.current_scene_guid == 0) _ = self.setLoadedScene(scene.guid);
        log.info("Loaded scene [{s} | GUID:{}]", .{ scene.name, scene.guid });
    }
}

fn getSceneName(self: *SceneManager, guid: Uuid.Uuid) []const u8 {
    return std.fmt.allocPrint(self.allocator, "{}{s}", .{ guid, SCENE_FILE_EXTENSION }) catch "out_of_memory" ++ SCENE_FILE_EXTENSION;
}

pub fn getCurrentScene(self: *SceneManager) ?*Scene {
    return self.active_scenes.getPtr(self.current_scene_guid);
}

pub fn getCurrentSceneData(self: *SceneManager) ?*SceneData {
    return self.buffer_parsed_scenes.getPtr(self.current_scene_guid);
}

fn extractGuidFromSceneName(scene_name: []const u8) ?Uuid.Uuid {
    if (!std.mem.endsWith(u8, scene_name, SCENE_FILE_EXTENSION)) return null;
    const stem = std.fs.path.stem(scene_name);
    return std.fmt.parseInt(Uuid.Uuid, stem, 10) catch null;
}

const EntityData = struct {
    entity_guid: Uuid.Uuid,
    entity_tag: ?World.Components.Tag = null,
    transform: ?World.Components.Transform = null,
    camera: ?World.Components.Camera = null,
    camera_active: ?World.Components.CameraActive = null,

    pub const serde = .{
        .skip = .{
            .transform = Serde.SkipMode.null,
            .entity_tag = Serde.SkipMode.null,
            .entity_guid = Serde.SkipMode.null,
            .camera = Serde.SkipMode.null,
            .camera_active = Serde.SkipMode.null,
        },
    };
};

fn emitEcsEvent(self: *SceneManager, comptime Event: type, value: Event) !void {
    const writer = try World.Ecs.EventWriter(Event).fromWorld(self.world.app);
    try writer.send(value);
}

pub const SceneData = struct {
    scene_guid: Uuid.Uuid = 0,
    scene_name: []const u8 = "Untitled Scene",
    lights: ?World.Components.Lights = null,
    entities: []EntityData = &.{},
};
const SceneSerializer = struct {
    pub fn serialize(allocator: std.mem.Allocator, world: *World, scene: Scene) ![]const u8 {
        var scene_data: SceneData = undefined;

        scene_data.scene_guid = scene.guid;
        scene_data.scene_name = scene.name;

        { // Global lights
            const lights = try world.app.getResource(World.Components.Lights);
            scene_data.lights = lights.*;
        }

        var entities: std.ArrayList(EntityData) = .empty;
        defer entities.deinit(allocator);

        { // Entities

            const query_all = try World.Ecs.Query(struct { entity: World.Ecs.Entity, guid: *const World.Components.ID }).fromWorld(world.app);

            var it = query_all.iter();
            while (it.next()) |entry| {
                var entity_data: EntityData = .{
                    .entity_guid = entry.guid.guid,
                };

                if (world.app.components.getSingle(entry.entity, World.Components.Tag)) |tag| {
                    entity_data.entity_tag = tag.*;
                }
                if (world.app.components.getSingle(entry.entity, World.Components.Transform)) |transform| {
                    entity_data.transform = transform.*;
                }
                if (world.app.components.getSingle(entry.entity, World.Components.Camera)) |camera| {
                    entity_data.camera = camera.*;
                }
                if (world.app.components.getSingle(entry.entity, World.Components.CameraActive)) |camera_active| {
                    entity_data.camera_active = camera_active.*;
                }

                try entities.append(allocator, entity_data);
            }

            scene_data.entities = entities.items;
        }

        return try Serde.zon.toSlice(allocator, scene_data);
    }

    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !SceneData {
        return Serde.zon.fromSlice(SceneData, allocator, data) catch |err| {
            log.err("Scene parse failed: {}", .{err});
            return err;
        };
    }
};
