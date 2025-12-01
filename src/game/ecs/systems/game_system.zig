const std = @import("std");
const System = @import("system.zig");
const ecs = @import("../ecs.zig");

const GameSystem = @This();

var allocator: std.mem.Allocator = undefined;
var is_initialised: bool = false;

pub fn init(
    // alloc: std.mem.Allocator
) GameSystem {
    // allocator = alloc;
    is_initialised = true;
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
    _ = &world;

    // _ = ecs.zflecs.ADD_SYSTEM(world, "system_unlock_resource", ecs.zflecs.OnUpdate, system_unlock_resource);
}

pub fn update(self: *GameSystem, world: *ecs.zflecs.world_t) void {
    _ = &self;
    _ = &world;
}

// pub fn system_unlock_asset(
//     ctx: struct { cb: *ecs.CmdBuf, es: *ecs.Entities },
//     ev: *const ecs.components.Event.UnlockAssetEvent,
//     entity: ecs.Entity,
// ) void {
//     ecs.logger.print_info("[GameSystem.system_unlock_asset]", .{});
//
//     var iter_mt = ctx.es.iterator(struct { mt: *ecs.components.MarketTrading, locked: *ecs.components.Locked, e: ecs.Entity });
//     while (iter_mt.next(ctx.es)) |view| {
//         if (ev.asset.isEqualTo(view.mt.asset)) {
//             _ = view.e.add(ctx.cb, ecs.components.Unlocked, .{});
//             _ = view.e.remove(ctx.cb, ecs.components.Locked);
//             break;
//         }
//     }
//
//     var iter_res = ctx.es.iterator(struct { res: *ecs.components.Resource, locked: *ecs.components.Locked, e: ecs.Entity });
//     while (iter_res.next(ctx.es)) |view| {
//         if (ev.asset.isResource(view.res.type)) {
//             _ = view.e.add(ctx.cb, ecs.components.Unlocked, .{});
//             _ = view.e.remove(ctx.cb, ecs.components.Locked);
//             break;
//         }
//     }
//     // ecs.create_single_component_entity(ctx.cb, ecs.components.Resource, .{ .asset = ev.asset, .qty_owned = 0 });
//
//     entity.destroy(ctx.cb);
// }

// zflecs implementation
// fn system_unlock_resource(it: *ecs.zflecs.iter_t, events: []ecs.components.Event.UnlockResourceEvent) void {
//     ecs.logger.print_info("[GameSystem.system_unlock_resource]", .{});
//     const unlock_state = ecs.zflecs.singleton_ensure(it.world, ecs.components.UnlockState);
//
//     for (events) |ev| {
//         if (!unlock_state.is_resource_unlocked(ev.asset)) {
//             unlock_state.unlock_resource(ev.asset);
//             const entity = ecs.zflecs.new_id(it.world);
//             _ = ecs.zflecs.set(it.world, entity, ecs.components.Resource, .{ .asset = ev.asset, .qty_owned = 0 });
//
//             // const book = ecs.components.OrderBook.init(allocator, 1) catch |err| {
//             //     ecs.logger.err("[ERROR][GameSystem.system_unlock_resource] Can't allocate OrderBook: {})", .{err});
//             //     ecs.throw_error(it.world, ecs.EcsError.AllocationError);
//             //     return;
//             // };
//             //
//             // const e = ecs.zflecs.new_id(it.world);
//             // _ = ecs.zflecs.set(it.world, e, ecs.components.MarketTrading, .{ .book = book, .asset = ev.asset });
//         }
//
//         ecs.zflecs.delete(it.world, ev.id);
//     }
// }
