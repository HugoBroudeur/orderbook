// This is an SDL implementation

const std = @import("std");
const sdl = @import("sdl3");
const assert = std.debug.assert;

const Logger = @import("../../core/log.zig").MaxLogs(50);
const GPU = @import("gpu.zig");
const Pipeline = @import("pipeline.zig");
const Sampler = @import("sampler.zig");
const Texture = @import("texture.zig");
const TransferBuffer = @import("buffer.zig").Buffer(.sdl).TransferBuffer(.upload);

pub const RenderPass = struct {
    gpu: *GPU,

    ptr: ?sdl.gpu.RenderPass,
    // cmd_buf: sdl.gpu.CommandBuffer = undefined,

    pub fn init(gpu: *GPU) RenderPass {
        return .{
            .gpu = gpu,
            .ptr = null,
        };
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

    pub fn bindPipeline(self: *RenderPass, pipeline: *Pipeline) void {
        assert(self.hasStarted());
        self.ptr.?.bindGraphicsPipeline(pipeline.ptr);
    }

    pub fn bindTexture(self: *RenderPass, texture: *Texture, sampler: *Sampler) void {
        assert(self.hasStarted());
        self.ptr.?.bindFragmentSamplers(0, &.{.{ .texture = texture.ptr, .sampler = sampler.ptr }});
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

    pub fn hasStarted(self: *RenderPass) bool {
        return self.ptr != null;
    }
};

pub const CopyPass = struct {
    gpu: *GPU,

    ptr: ?sdl.gpu.CopyPass,
    cmd_buf: sdl.gpu.CommandBuffer = undefined,

    pub fn init(gpu: *GPU) CopyPass {
        return .{
            .gpu = gpu,
            .ptr = null,
        };
    }

    pub fn start(self: *CopyPass) void {
        Logger.debug("[CopyPass.start]", .{});
        assert(!self.hasStarted());

        self.cmd_buf = self.gpu.device.acquireCommandBuffer() catch {
            Logger.err("[CopyPass.start] Acquire Command Buffer error: {?s}", .{sdl.errors.get()});
            return;
        };

        self.ptr = self.cmd_buf.beginCopyPass();
    }

    pub fn end(self: *CopyPass) void {
        Logger.debug("[CopyPass.end]", .{});
        assert(self.hasStarted());

        self.ptr.?.end();

        self.cmd_buf.submit() catch {
            Logger.err("[CopyPass.end] Submit Command Buffer error: {?s}", .{sdl.errors.get()});
        };

        self.ptr = null;
    }

    // pub fn uploadTransferBuffer(self: *CopyPass, transfer_buffer: TransferBuffer) void {
    //     std.debug.assert(self.hasStarted());
    //     {
    //         self.ptr.uploadToBuffer(.{ .transfer_buffer = transfer_buffer.ptr, .offset = 0 }, .{
    //             .buffer = transfer_buffer.buffer.ptr,
    //             .offset = 0,
    //             .size = buffer.getDataLength(),
    //         }, false);
    //     }
    // }

    pub fn hasStarted(self: *CopyPass) bool {
        return self.ptr != null;
    }
};
