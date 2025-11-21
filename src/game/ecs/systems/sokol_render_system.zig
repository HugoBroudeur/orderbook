const std = @import("std");
const logger = @import("../logger.zig");

// const zecs = @import("zecs");
const f = @import("zflecs");
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

pub fn render(self: *SokolRenderSystem, world: *f.world_t, pass_action: *sg.PassAction) void {
    _ = &world;
    _ = &self;
    _ = &pass_action;
}

pub fn setup(self: *SokolRenderSystem, world: *f.world_t) void {
    // _ = world;
    _ = &self;

    _ = f.ADD_SYSTEM(world, "begin_sokol_pass", RenderingPipeline.BeginSokolPass, begin_render_pass);
    _ = f.ADD_SYSTEM(world, "render_sokol_pass", RenderingPipeline.RenderSokolPass, render_pass);
    _ = f.ADD_SYSTEM(world, "end_sokol_pass", RenderingPipeline.EndSokolPass, end_render_pass);
    // _ = f.ADD_SYSTEM(w, "market-trade-view", f.OnStore, renderMarketView);
    // _ = f.ADD_SYSTEM(w, "render_ui", f.OnStore, renderUi);

    // const env_info = f.singleton_ensure(world, data.SingletonMarketData);
}

fn begin_render_pass(it: *f.iter_t) void {
    logger.ecs().info("[SokolRenderSystem.begin_render_pass]", .{});
    const pass_action = f.singleton_ensure(it.world, sg.PassAction);
    sg.beginPass(.{ .action = pass_action.*, .swapchain = sglue.swapchain() });
}

fn render_pass(it: *f.iter_t) void {
    logger.ecs().info("[SokolRenderSystem.render_pass]", .{});
    _ = &it;
    sg.endPass();
}

fn end_render_pass(it: *f.iter_t) void {
    logger.ecs().info("[SokolRenderSystem.end_render_pass]", .{});
    _ = &it;
    sg.commit();
}
