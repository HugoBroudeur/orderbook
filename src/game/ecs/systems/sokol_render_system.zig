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

pub fn render(self: *SokolRenderSystem, pass_action: *sg.PassAction) void {
    _ = &self;
    _ = &pass_action;
}

pub fn setup(self: *SokolRenderSystem) void {
    _ = &self;
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
