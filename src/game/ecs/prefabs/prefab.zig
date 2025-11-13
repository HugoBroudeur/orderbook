const std = @import("std");
const data = @import("../data.zig");
// const ecs = @import("ecs");
const ecs = @import("zflecs");
const vec = @import("../../math/vec.zig");

pub fn create_scenario(world: *ecs.world_t, id: u8) void {
    // const entity = r.create();

    // const t = component.Tile{ .coord = .{ .x = 0, .y = 0 }, .overlay = .{ .type = component.OverlayType.corridor } };
    const t = data.Tile{ .coord = .{ .x = 0, .y = 0 }, .overlay = "corridor" };
    const mt = data.MapTile{ .name = "A1", .tiles = &.{t} };
    const mto = data.MapTileOffset{ .offset = .{ .x = 0, .y = 0 }, .map_tile = mt };
    const m = data.Map{ .map_tiles_offset = &.{mto} };
    const s = data.Scenario{ .id = id, .name = "Test scenario 1", .map = m };
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
    world: *ecs.world_t,
    coord: data.Coordinate,
    // ot: component.OverlayType,
) void {
    const h = data.Shape{
        .hexagon = .{},
    };

    const tile = ecs.new_entity(world, "Tile");
    _ = ecs.set(world, tile, data.Tile, data.Tile{ .coord = .{ .x = 0, .y = 0 }, .overlay = "corridor" });
    _ = ecs.set(world, tile, data.Shape, h);
    _ = ecs.set(world, tile, data.GameObject, .{});
    const tile2 = ecs.new_entity(world, "Tile2");
    _ = ecs.set(world, tile2, data.Tile, data.Tile{ .coord = .{ .x = 1, .y = 1 }, .overlay = "corridor" });
    _ = ecs.set(world, tile2, data.Shape, h);
    _ = ecs.set(world, tile2, data.GameObject, .{ .pos = .{ .x = 1, .y = 0.5, .z = 0 } });
    const tile3 = ecs.new_entity(world, "Tile3");
    _ = ecs.set(world, tile3, data.Tile, data.Tile{ .coord = .{ .x = 2, .y = 2 }, .overlay = "corridor" });
    _ = ecs.set(world, tile3, data.Shape, h);
    _ = ecs.set(world, tile3, data.GameObject, .{ .pos = .{ .x = -0.5, .y = -0.5, .z = 0 } });
    // const e = r.create();
    // const t = component.Tile{ .coord = coord, .overlay = "corridor" };

    _ = &coord;
    // r.add(e, coord);
    // r.add(e, component.Coordinate{ .x = 1, .y = 1 });
}

// pub fn create_map_tile(r: *ecs.Registry, name: []const u8) void {
// const e = r.create();
//
// // r.add(e, )
//
// }
