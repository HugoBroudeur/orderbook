const std = @import("std");
const System = @import("system.zig");
const ecs = @import("../ecs.zig");

const GameSystem = @This();

pub fn init() GameSystem {
    return .{};
}

pub fn system(self: *GameSystem) System {
    return System.init(self);
}

pub fn deinit(self: *GameSystem) void {
    _ = self;
}

pub fn setup(self: *GameSystem, world: *ecs.zflecs.world_t) void {
    _ = &self;
    // _ = &world;

    _ = ecs.zflecs.ADD_SYSTEM(world, "system_unlock_resource", ecs.zflecs.OnUpdate, system_unlock_resource);
}

pub fn update(self: *GameSystem, world: *ecs.zflecs.world_t) void {
    _ = &self;
    _ = &world;
}

fn system_unlock_resource(it: *ecs.zflecs.iter_t, events: []ecs.components.Event.UnlockResourceEvent) void {
    ecs.logger.print_info("[GameSystem.system_unlock_resource]", .{});
    const unlock_state = ecs.zflecs.singleton_ensure(it.world, ecs.components.UnlockState);

    for (events) |ev| {
        if (!unlock_state.is_resource_unlocked(ev.asset)) {
            unlock_state.unlock_resource(ev.asset);
            const entity = ecs.zflecs.new_id(it.world);
            _ = ecs.zflecs.set(it.world, entity, ecs.components.Resource, .{ .asset = ev.asset, .qty_owned = 0 });
        }

        ecs.zflecs.delete(it.world, ev.id);
    }
}
