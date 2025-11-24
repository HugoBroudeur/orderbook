const std = @import("std");

// const zecs = @import("zecs");
const ecs = @import("../ecs.zig");
const RenderSystem = @import("render_system.zig");
const RenderingPipeline = @import("../rendering_pipeline.zig");

const sokol = @import("sokol");
const sg = sokol.gfx;
const sglue = sokol.glue;

const SokolRenderSystem = @This();

pub fn init() SokolRenderSystem {
    return .{};
}
pub fn deinit(self: *SokolRenderSystem) void {
    _ = self;
}

pub fn system(self: *SokolRenderSystem) RenderSystem {
    return RenderSystem.init(self);
}

pub fn render(self: *SokolRenderSystem, world: *ecs.zflecs.world_t, pass_action: *sg.PassAction) void {
    _ = &world;
    _ = &self;
    _ = &pass_action;
}

pub fn setup(self: *SokolRenderSystem) void {
    _ = &self;

    // _ = ecs.zflecs.ADD_SYSTEM(world, "begin_sokol_pass", RenderingPipeline.BeginSokolPass, begin_render_pass);
    // _ = ecs.zflecs.ADD_SYSTEM(world, "render_sokol_pass", RenderingPipeline.RenderSokolPass, render_pass);
    // _ = ecs.zflecs.ADD_SYSTEM(world, "end_sokol_pass", RenderingPipeline.EndSokolPass, end_render_pass);
    // _ = ecs.zflecs.ADD_SYSTEM(w, "market-trade-view", ecs.zflecs.OnStore, renderMarketView);
    // _ = ecs.zflecs.ADD_SYSTEM(w, "render_ui", ecs.zflecs.OnStore, renderUi);

    // ecs.register_system(world: *world_t, name: [*:0]const u8, callback: *const fn (*iter_t) void, update_ctx: anytype, terms: []const term_t)

    // const env_info = ecs.zflecs.singleton_ensure(world, data.SingletonMarketData);
}

pub fn begin_render_pass(ctx: struct { cb: *ecs.CmdBuf }, pass_action: *sg.PassAction) void {
    ecs.logger.info("[SokolRenderSystem.begin_render_pass]", .{});

    _ = ctx;

    sg.beginPass(.{ .action = pass_action.*, .swapchain = sglue.swapchain() });
}

pub fn render_pass() void {
    ecs.logger.info("[SokolRenderSystem.render_pass]", .{});
    sg.endPass();
}

pub fn end_render_pass() void {
    ecs.logger.info("[SokolRenderSystem.end_render_pass]", .{});
    sg.commit();
}
