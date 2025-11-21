const std = @import("std");
const ecs = @import("ecs");
const vec = @import("../math/vec.zig");

pub fn create_scenario(world: *ecs.zflecs.world_t, id: u8) void {
    // const entity = r.create();

    // const t = component.Tile{ .coord = .{ .x = 0, .y = 0 }, .overlay = .{ .type = component.OverlayType.corridor } };
    const t = ecs.components.Tile{ .coord = .{ .x = 0, .y = 0 }, .overlay = "corridor" };
    const mt = ecs.components.MapTile{ .name = "A1", .tiles = &.{t} };
    const mto = ecs.components.MapTileOffset{ .offset = .{ .x = 0, .y = 0 }, .map_tile = mt };
    const m = ecs.components.Map{ .map_tiles_offset = &.{mto} };
    const s = ecs.components.Scenario{ .id = id, .name = "Test scenario 1", .map = m };
    _ = &s;
    _ = &world;
    // _ = &entity;
    // r.add(entity, s);
}

//
// How to make a scenario?
//
// scenario 1:
// ecs.add(e, tile)
//
//
//
pub fn create_tile(
    world: *ecs.zflecs.world_t,
    coord: ecs.components.Coordinate,
    // ot: component.OverlayType,
) void {
    const h = ecs.components.Shape{
        .hexagon = .{},
    };

    const tile = ecs.zflecs.new_entity(world, "Tile");
    _ = ecs.zflecs.set(world, tile, ecs.components.Tile, ecs.components.Tile{ .coord = .{ .x = 0, .y = 0 }, .overlay = "corridor" });
    _ = ecs.zflecs.set(world, tile, ecs.components.Shape, h);
    _ = ecs.zflecs.set(world, tile, ecs.components.GameObject, .{});
    const tile2 = ecs.zflecs.new_entity(world, "Tile2");
    _ = ecs.zflecs.set(world, tile2, ecs.components.Tile, ecs.components.Tile{ .coord = .{ .x = 1, .y = 1 }, .overlay = "corridor" });
    _ = ecs.zflecs.set(world, tile2, ecs.components.Shape, h);
    _ = ecs.zflecs.set(world, tile2, ecs.components.GameObject, .{ .pos = .{ .x = 1, .y = 0.5, .z = 0 } });
    const tile3 = ecs.zflecs.new_entity(world, "Tile3");
    _ = ecs.zflecs.set(world, tile3, ecs.components.Tile, ecs.components.Tile{ .coord = .{ .x = 2, .y = 2 }, .overlay = "corridor" });
    _ = ecs.zflecs.set(world, tile3, ecs.components.Shape, h);
    _ = ecs.zflecs.set(world, tile3, ecs.components.GameObject, .{ .pos = .{ .x = -0.5, .y = -0.5, .z = 0 } });
    // const e = r.create();
    // const t = component.Tile{ .coord = coord, .overlay = "corridor" };

    _ = &coord;
    // r.add(e, coord);
    // r.add(e, component.Coordinate{ .x = 1, .y = 1 });
}

// pub fn create_map_tile(r: *ecs.zflecs.Registry, name: []const u8) void {
// const e = r.create();
//
// // r.add(e, )
//
// }
