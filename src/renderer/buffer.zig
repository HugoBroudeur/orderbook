// The Buffers are for the SDL implementation
const std = @import("std");
const sdl = @import("sdl3");
const PipelineManager = @import("../game/pipeline_manager.zig");
const GPU = @import("gpu.zig");

pub const VERTEX_BUFFER_SIZE = 64 * 1024; //64k vertices
pub const INDEX_BUFFER_SIZE = 64 * 1024; //64k indices

pub const VertexBufferType = enum { d2, d3 };
pub const VertexBuffer = union(VertexBufferType) {
    d2: VertexBufferImpl(PipelineManager.D2Vertex, VERTEX_BUFFER_SIZE),
    d3: VertexBufferImpl(PipelineManager.PositionTextureVertex, VERTEX_BUFFER_SIZE),

    pub fn init(buffer_type: VertexBufferType, gpu: *GPU) VertexBuffer {
        return switch (buffer_type) {
            .d2 => VertexBuffer{ .d2 = .init(gpu) },
            .d3 => VertexBuffer{ .d3 = .init(gpu) },
        };
    }
    pub fn deinit(self: *VertexBuffer) void {
        switch (self.*) {
            inline else => |*buffer| {
                buffer.deinit();
            },
            // .d2 => |*buffer| {
            //     buffer.deinit();
            // },
            // .d3 => |*buffer| {
            //     buffer.deinit();
            // },
        }
    }
    pub fn create(self: *VertexBuffer) !void {
        switch (self.*) {
            inline else => |*buffer| {
                try buffer.create();
            },
            // .d2, .d3 => |*buffer| {
            //     try buffer.create();
            // },
        }
    }
    pub fn destroy(self: *VertexBuffer) void {
        switch (self.*) {
            inline else => |*buffer| {
                buffer.destroy();
            },
        }
    }
    pub fn bind(self: *VertexBuffer, render_pass: sdl.gpu.RenderPass) void {
        switch (self.*) {
            inline else => |*buffer| {
                buffer.bind(render_pass);
            },
        }
    }
    pub fn upload(self: *VertexBuffer, copy_pass: sdl.gpu.CopyPass, tb: TransferBuffer) void {
        switch (self.*) {
            inline else => |*buffer| {
                buffer.upload(copy_pass, tb);
            },
        }
    }
};
pub const IndexBufferType = enum { u16 };
pub const IndexBuffer = union(IndexBufferType) {
    u16: IndexBufferImpl(u16, INDEX_BUFFER_SIZE),

    pub fn init(buffer_type: IndexBufferType, gpu: *GPU) IndexBuffer {
        return switch (buffer_type) {
            .u16 => IndexBuffer{ .u16 = .init(gpu) },
        };
    }
    pub fn deinit(self: *IndexBuffer) void {
        switch (self.*) {
            .u16 => |*buffer| {
                buffer.deinit();
            },
        }
    }
    pub fn create(self: *IndexBuffer) !void {
        switch (self.*) {
            .u16 => |*buffer| {
                try buffer.create();
            },
        }
    }

    pub fn destroy(self: *IndexBuffer) void {
        switch (self.*) {
            .u16 => |*buffer| {
                buffer.destroy();
            },
        }
    }
    pub fn bind(self: *IndexBuffer, render_pass: sdl.gpu.RenderPass) void {
        switch (self.*) {
            .u16 => |*buffer| {
                buffer.bind(render_pass);
            },
        }
    }

    pub fn upload(self: *IndexBuffer, copy_pass: sdl.gpu.CopyPass, tb: TransferBuffer) void {
        switch (self.*) {
            .u16 => |*buffer| {
                buffer.upload(copy_pass, tb);
            },
        }
    }
};

pub const BufferType = enum {
    vertex,
    index,
    indirect,
    graphics_storage_read,
    compute_storage_read,
    compute_storage_write,
};

pub fn VertexBufferImpl(comptime T: type, comptime size: u32) type {
    return Buffer(T, .vertex, size);
}
pub fn IndexBufferImpl(comptime T: type, comptime size: u32) type {
    return Buffer(T, .index, size);
}
fn Buffer(comptime T: type, comptime buffer_type: BufferType, comptime size: u32) type {
    return struct {
        const Self = @This();

        gpu: *GPU,
        indices: [size]T,
        current_index: u32 = 0,
        ptr: sdl.gpu.Buffer = undefined,
        is_in_gpu: bool = false,

        pub fn init(gpu: *GPU) Self {
            if (buffer_type == .index and !(T == u32 or T == u16)) {
                std.log.err("[IndexBuffer] Attempting to create an Index buffer with type {s}. Index buffer only support type u32 or u16", .{@typeName(T)});
                unreachable;
            }

            return .{
                .indices = @splat(undefined),
                .gpu = gpu,
            };
        }

        pub fn deinit(self: *Self) void {
            self.destroy();
        }

        pub fn create(self: *Self) !void {
            const buffer_usage_flag: sdl.gpu.BufferUsageFlags = switch (buffer_type) {
                .vertex => .{ .vertex = true },
                .index => .{ .index = true },
                else => unreachable, // TODO, implement others
            };

            self.ptr = try self.gpu.device.createBuffer(.{ .usage = buffer_usage_flag, .size = size });
            self.is_in_gpu = true;
        }

        pub fn destroy(self: *Self) void {
            if (self.is_in_gpu) {
                self.gpu.device.releaseBuffer(self.ptr);
                self.is_in_gpu = false;
                self.ptr = undefined;
            }
        }

        pub fn bind(self: *Self, render_pass: sdl.gpu.RenderPass) void {
            switch (buffer_type) {
                .vertex => {
                    render_pass.bindVertexBuffers(0, &.{.{ .buffer = self.ptr, .offset = 0 }});
                },
                .index => {
                    switch (T) {
                        u32 => {
                            render_pass.bindIndexBuffer(.{ .buffer = self.ptr, .offset = 0 }, .indices_32bit);
                        },
                        u16 => {
                            render_pass.bindIndexBuffer(.{ .buffer = self.ptr, .offset = 0 }, .indices_16bit);
                        },
                        else => unreachable,
                    }
                },
                else => unreachable, // TODO, implement others

            }
        }

        pub fn upload(self: *Self, copy_pass: sdl.gpu.CopyPass, tb: TransferBuffer) void {
            copy_pass.uploadToBuffer(.{ .transfer_buffer = tb.ptr, .offset = 0 }, .{
                .buffer = self.ptr,
                .offset = 0,
                .size = @sizeOf(T) * self.current_index,
            }, false);
        }
    };
}
pub const TransferBuffer = struct {
    ptr: sdl.gpu.TransferBuffer = undefined,
    gpu: *GPU,
    usage: sdl.gpu.TransferBufferUsage,
    size: u32,
    has_data_mapped: bool = false,
    is_in_gpu: bool = false,

    pub fn init(gpu: *GPU, usage: sdl.gpu.TransferBufferUsage, size: u32) TransferBuffer {
        return .{
            .gpu = gpu,
            .usage = usage,
            .size = size,
        };
    }

    pub fn deinit(self: *TransferBuffer) void {
        self.destroy();
    }

    pub fn create(self: *TransferBuffer) !void {
        self.ptr = try self.gpu.device.createTransferBuffer(.{
            .usage = self.usage,
            .size = self.size,
        });

        self.is_in_gpu = true;
    }

    pub fn destroy(self: *TransferBuffer) void {
        if (self.is_in_gpu) {
            self.gpu.device.releaseTransferBuffer(self.ptr);
            self.is_in_gpu = false;
            self.ptr = undefined;
        }
    }

    pub fn hasDataMapped(self: *TransferBuffer) bool {
        return self.data.len > 0;
    }

    pub fn mapToGpu(self: *TransferBuffer, cycle: bool) ![*]u8 {
        self.has_data_mapped = true;
        return self.gpu.device.mapTransferBuffer(self.ptr, cycle);
    }

    pub fn unmapToGpu(self: *TransferBuffer) void {
        defer self.gpu.device.unmapTransferBuffer(self.ptr);
    }

    // Must be called at the end of the copy pass
    pub fn endCopyPass(self: *TransferBuffer) void {
        self.has_data_mapped = false;
    }
};
