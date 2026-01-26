// This is an SDL implementation

const std = @import("std");
const sdl = @import("sdl3");
const vk = @import("vulkan");
const assert = std.debug.assert;

const GraphicsContext = @import("../../core/graphics_context.zig");
const Logger = @import("../../core/log.zig").MaxLogs(50);
const Pipeline = @import("pipeline.zig");
const Sampler = @import("sampler.zig");
const Swapchain = @import("swapchain.zig").Swapchain;
const Image = @import("image.zig");
const TransferBuffer = @import("buffer.zig").Buffer(.sdl).TransferBuffer(.upload);

const RenderPass = @This();

pub const RenderPassDesc = struct {
    load_op: vk.AttachmentLoadOp = .clear,
    store_op: vk.AttachmentStoreOp = .store,
};

vk_render_pass: vk.RenderPass,

pub fn create(ctx: *GraphicsContext, swapchain: Swapchain, desc: RenderPassDesc) !RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .format = swapchain.surface_format.format,
        .samples = .{ .@"1_bit" = true },
        .load_op = desc.load_op,
        .store_op = desc.store_op,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = if (desc.load_op == .clear) .undefined else .color_attachment_optimal,
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment_ref),
    };

    const vk_render_pass = try ctx.device.createRenderPass(&.{
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_attachment),
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
    }, null);

    return .{
        .vk_render_pass = vk_render_pass,
    };
}

pub fn destroy(self: *RenderPass, ctx: *GraphicsContext) void {
    ctx.device.destroyRenderPass(self.vk_render_pass, null);
}

pub fn start(self: *RenderPass, color_target_infos: []const sdl.gpu.ColorTargetInfo, depth_stencil_target_info: ?sdl.gpu.DepthStencilTargetInfo) void {
    assert(!self.hasStarted());

    // self.cmd_buf = self.gpu.device.acquireCommandBuffer() catch {
    //     std.log.err("[RenderPass.start] Acquire Command Buffer error: {?s}", .{sdl.errors.get()});
    //     return;
    // };

    self.ptr = self.gpu.command_buffer.beginRenderPass(color_target_infos, depth_stencil_target_info);
    // self.ptr = self.cmd_buf.beginRenderPass(color_target_infos, depth_stencil_target_info);
}

pub fn end(self: *RenderPass) void {
    assert(self.hasStarted());

    self.ptr.?.end();

    // self.cmd_buf.submit() catch {
    //     std.log.err("[RenderPass.end] Submit Command Buffer error: {?s}", .{sdl.errors.get()});
    // };

    self.ptr = null;
}

pub fn drawPrimitives(
    self: *RenderPass,
    num_indices: u32,
    num_instances: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
) void {
    assert(self.hasStarted());
    self.ptr.?.drawIndexedPrimitives(num_indices, num_instances, first_index, vertex_offset, first_instance);
}
