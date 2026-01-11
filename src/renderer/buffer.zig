// The Buffers are for the SDL implementation
const std = @import("std");
const assert = std.debug.assert;
const sdl = @import("sdl3");
const PipelineManager = @import("../game/pipeline_manager.zig");

const GPU = @import("gpu.zig");
const CopyPass = @import("pass.zig").CopyPass;
const RenderPass = @import("pass.zig").RenderPass;
const Shader = @import("shader.zig");
const Texture = @import("texture.zig");
const Platform = @import("../platforms/platform.zig");

pub const VERTEX_BUFFER_SIZE = 64 * 1024; //64k vertices
pub const INDEX_BUFFER_SIZE = 64 * 1024; //64k indices

pub const IndexBufferType = enum { u16, u32 };

pub const BufferType = enum {
    vertex,
    index,
    indirect,
    graphics_storage_read,
    compute_storage_read,
    compute_storage_write,
};

pub const BufferError = error{
    Overflow,
};

// Not in use, to be worked on
pub const IVertexBuffer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        // const Self = @This();
        // getSdlPtr: *const fn (*anyopaque) sdl.gpu.Buffer,
        // create: *const fn (gpu: *GPU) anyerror!Self,
        destroy: *const fn (*anyopaque) void,
        bind: *const fn (*anyopaque, render_pass: RenderPass) void,
        getDataLength: *const fn (*anyopaque) u32,
        // upload: *const fn (*anyopaque, sdl.gpu.CopyPass, TransferBuffer) void,
    };

    // pub fn create(self: IVertexBuffer, gpu: *GPU) IVertexBuffer {
    //     return self.vtable.create(gpu);
    // }
    pub fn destroy(self: IVertexBuffer) void {
        return self.vtable.destroy(self.ptr);
    }
    pub fn bind(self: IVertexBuffer, render_pass: RenderPass) void {
        return self.vtable.bind(self.ptr, render_pass);
    }
    pub fn getDataLength(self: IVertexBuffer) u32 {
        return self.vtable.getDataLength(self.ptr);
    }
    // pub fn upload(self: IVertexBuffer, copy_pass: sdl.gpu.CopyPass, tb: TransferBuffer) void {
    //     return self.vtable.upload(self.ptr, copy_pass, tb);
    // }

    pub fn inferface(ptr: anytype) IVertexBuffer {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            // fn create(comptime T: type, comptime size: u32, gpu: *GPU) !Buffer(graphic_api).IVertexBuffer.VTable {
            //     // const self: T = @ptrCast(@alignCast(impl));
            //     return ptr_info.pointer.child.create(gpu);
            // }
            fn destroy(impl: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.destroy(self);
            }
            fn bind(impl: *anyopaque, render_pass: RenderPass) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.bind(self, render_pass);
            }
            fn getDataLength(impl: *anyopaque) u32 {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.getDataLength(self);
            }
            // fn upload(impl: *anyopaque, copy_pass: sdl.gpu.CopyPass, tb: TransferBuffer) void {
            //     const self: T = @ptrCast(@alignCast(impl));
            //     return ptr_info.pointer.child.upload(self, copy_pass, tb);
            // }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                // .create = Impl.create,
                .destroy = Impl.destroy,
                .bind = Impl.bind,
                .getDataLength = Impl.getDataLength,
                // .upload = Impl.upload,
            },
        };
    }
};

pub const BufferElement = struct {
    name: []const u8,
    data_type: Shader.ShaderDataType,
    size: u32,
    offset: u32 = 0,

    pub fn new(data_type: Shader.ShaderDataType, name: []const u8) BufferElement {
        return .{
            .name = name,
            .data_type = data_type,
            .size = data_type.size(),
        };
    }

    pub fn getElementCount(self: *BufferElement) u32 {
        return self.data_type.count();
    }
};

pub const IBufferLayout = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        getElements: *const fn (*anyopaque) []BufferElement,
        getStride: *const fn (*anyopaque) u32,
    };

    pub fn getElements(self: IBufferLayout) []BufferElement {
        return self.vtable.getElements(self.ptr);
    }

    pub fn getStride(self: IBufferLayout) u32 {
        return self.vtable.getStride(self.ptr);
    }

    pub fn interface(ptr: anytype) IBufferLayout {
        const T = @TypeOf(ptr);

        const Impl = struct {
            fn getElements(impl: *anyopaque) []BufferElement {
                return TPtr(T, impl).getElements();
            }
            fn getStride(impl: *anyopaque) u32 {
                return TPtr(T, impl).getStride();
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .getElements = Impl.getElements,
                .getStride = Impl.getStride,
            },
        };
    }

    fn TPtr(T: type, opaque_ptr: *anyopaque) T {
        return @as(T, @ptrCast(@alignCast(opaque_ptr)));
    }
};

/// BufferLayout never allocate more space than the provided length size
/// You must ensure the buffer is not overflowing
pub fn BufferLayout(comptime len: usize) type {
    return struct {
        const Self = @This();
        elements: [len]BufferElement,

        stride: u32 = 0,

        pub fn init(elements: [len]BufferElement) Self {
            var bf: Self = .{
                .elements = elements,
            };

            bf.calculateOffsetAndStride();
            return bf;
        }

        pub fn getElements(self: *Self) []BufferElement {
            return &self.elements;
        }

        pub fn getStride(self: *Self) u32 {
            return self.stride;
        }

        fn calculateOffsetAndStride(self: *Self) void {
            var offset: u32 = 0;
            self.stride = 0;

            for (&self.elements) |*element| {
                element.offset = offset;
                offset += element.size;
                self.stride += element.size;
            }
        }

        pub fn interface(self: *Self) IBufferLayout {
            return IBufferLayout.interface(self);
        }
    };
}

// pub const VertexBuffer = struct {
//     const Self = @This();
//
//     ptr: sdl.gpu.Buffer = undefined,
//     gpu: *GPU,
//
//     layout: BufferLayout,
//
//     pub fn create(comptime,gpu: *GPU) !Self {
//         const buffer_usage_flag: sdl.gpu.BufferUsageFlags = .{ .vertex = true };
//
//         const ptr = try gpu.device.createBuffer(.{ .usage = buffer_usage_flag, .size = VERTEX_BUFFER_SIZE });
//
//         return .{
//             .vertices = @splat(undefined),
//             .gpu = gpu,
//             .ptr = ptr,
//             .cur_pos = 0,
//         };
//     }
//
//     pub fn getDataLength(self: *Self) u32 {
//         return @sizeOf(Vertex) * self.cur_pos;
//     }
//
//     // pub fn append(self: *Self, vertices: []Vertex) !void {
//     //
//     //
//     // }
// };

pub const VertexBuffer = struct {
    const Self = @This();

    gpu: *GPU,
    // layout: BufferLayout,
    ptr: sdl.gpu.Buffer = undefined,
    size_bytes: u32,

    pub fn create(gpu: *GPU, max_vertices: u32, stride: u32) !Self {
        const buffer_usage_flag: sdl.gpu.BufferUsageFlags = .{ .vertex = true };

        const size_bytes = stride * max_vertices;

        std.log.debug("[VertexBuffer.create] Size {} bytes.", .{size_bytes});

        const ptr = try gpu.device.createBuffer(.{ .usage = buffer_usage_flag, .size = size_bytes });

        return .{
            .gpu = gpu,
            .ptr = ptr,
            // .layout = layout,
            .size_bytes = size_bytes,
        };
    }

    pub fn destroy(self: *Self) void {
        self.gpu.device.releaseBuffer(self.ptr);
        self.ptr = undefined;
    }

    pub fn bind(self: *Self, render_pass: RenderPass) void {
        render_pass.ptr.?.bindVertexBuffers(0, &.{.{ .buffer = self.ptr, .offset = 0 }});
    }

    pub fn upload(self: *Self, copy_pass: CopyPass, tb: TransferBuffer(.upload), offset: u32) void {
        std.log.debug("[VertexBuffer.upload] Uploading {} bytes at offset {}, using Buffer of {} bytes", .{ self.size_bytes, offset, tb.size });
        assert(self.size_bytes + offset <= tb.size);

        copy_pass.ptr.?.uploadToBuffer(.{ .transfer_buffer = tb.ptr, .offset = offset }, .{
            .buffer = self.ptr,
            .offset = 0,
            .size = self.size_bytes,
        }, false);
    }

    // pub fn interface(self: *Self) IVertexBuffer {
    //     return IVertexBuffer.inferface(self);
    // }

    // pub fn append(self: *Self, vertices: []Vertex) !void {
    //
    //
    // }
};

pub fn IndexBuffer(comptime index_type: IndexBufferType) type {
    const IndexType = switch (index_type) {
        .u16 => u16,
        .u32 => u32,
    };

    return struct {
        const Self = @This();

        gpu: *GPU,
        // indices: [INDEX_BUFFER_SIZE]IndexType,
        // cur_pos: u32 = 0,
        ptr: sdl.gpu.Buffer = undefined,
        size_bytes: u32,

        pub fn create(gpu: *GPU, max_indices: u32) !Self {
            const buffer_usage_flag: sdl.gpu.BufferUsageFlags = .{ .index = true };

            const size_bytes = @sizeOf(IndexType) * max_indices;
            const ptr = try gpu.device.createBuffer(.{ .usage = buffer_usage_flag, .size = size_bytes });

            return .{
                .gpu = gpu,
                .ptr = ptr,
                .size_bytes = size_bytes,
            };
        }

        pub fn destroy(self: *Self) void {
            self.gpu.device.releaseBuffer(self.ptr);
            self.ptr = undefined;
        }

        pub fn bind(self: *Self, render_pass: RenderPass) void {
            const index_element_size: sdl.gpu.IndexElementSize = switch (IndexType) {
                u32 => .indices_32bit,
                u16 => .indices_16bit,
                else => .indices_16bit,
            };
            render_pass.ptr.?.bindIndexBuffer(.{ .buffer = self.ptr, .offset = 0 }, index_element_size);
        }

        pub fn upload(self: *Self, copy_pass: CopyPass, tb: TransferBuffer(.upload), offset: u32) void {
            std.log.debug("[IndexType.upload] Uploading {} bytes at offset {}, using TransferBuffer of {} bytes", .{ self.size_bytes, offset, tb.size });

            assert(self.size_bytes + offset <= tb.size);

            copy_pass.ptr.?.uploadToBuffer(.{ .transfer_buffer = tb.ptr, .offset = offset }, .{
                .buffer = self.ptr,
                .offset = 0,
                .size = self.size_bytes,
            }, false);
        }
    };
}

pub const TransferBufferType = enum { upload, download };
pub fn TransferBuffer(comptime usage: TransferBufferType) type {
    const TranserBufferUsage: sdl.gpu.TransferBufferUsage = switch (usage) {
        .upload => .upload,
        .download => .download,
    };

    return struct {
        const Self = @This();

        ptr: sdl.gpu.TransferBuffer,
        gpu: *GPU,
        usage: TransferBufferType = usage,
        size: u32,
        has_data_mapped: bool = false,

        pub fn create(gpu: *GPU, size: u32) !Self {
            std.log.debug("[TransferBuffer.create] Size {}", .{size});

            const ptr = try gpu.device.createTransferBuffer(.{
                .usage = TranserBufferUsage,
                .size = size,
            });

            return .{
                .gpu = gpu,
                .size = size,
                .ptr = ptr,
            };
        }

        pub fn destroy(self: *Self) void {
            self.gpu.device.releaseTransferBuffer(self.ptr);
            self.ptr = undefined;
        }

        pub fn upload(self: *Self, copy_pass: CopyPass, offset: u32, buffer: sdl.gpu.Buffer) void {
            std.log.debug("[TransferBuffer.upload] Uploading {} bytes at offset {}, using Buffer of {} bytes", .{ self.size_bytes, offset, self.size });

            copy_pass.ptr.?.uploadToBuffer(.{ .transfer_buffer = self.ptr, .offset = 0 }, .{
                .buffer = buffer,
                .offset = offset,
                .size = self.size_bytes,
            }, false);
        }

        pub fn transferToGpu(self: *Self, gpu: *GPU, cycle: bool, data: []const u8) !void {
            std.log.debug("[TransferBuffer.transferToGpu] Data in bytes: {}", .{data.len});
            var ptr = try gpu.device.mapTransferBuffer(self.ptr, cycle);
            defer gpu.device.unmapTransferBuffer(self.ptr);

            std.mem.copyForwards(u8, ptr[0..data.len], data);
        }

        // // pub fn uploadVertexBuffer(self: *Self, comptime Vertex: type, comptime size: u32, buffer: VertexBuffer(Vertex, size)) void {
        // pub fn uploadVertexBuffer(self: *Self, copy_pass: *CopyPass, buffer: IVertexBuffer) void {
        //     // pub fn uploadVertexBuffer(self: *Self, copy_pass: *CopyPass, comptime Vertex: type, buffer: *VertexBuffer(Vertex)) void {
        //     std.debug.assert(copy_pass.hasStarted());
        //     // const T = @TypeOf(vertex_buffer);
        //     // const type_info = @typeInfo(T);
        //     // const sdl_buffer: sdl.gpu.Buffer = undefined;
        //     //
        //     // // Validate it's a VertexBuffer
        //     // comptime {
        //     //     if (!@hasField(T, "ptr")) {
        //     //         @compileError("processVertexBuffer requires a VertexBuffer type");
        //     //     }
        //     //     // if (type_info != .Pointer) {
        //     //     //     @compileError("Expected pointer to VertexBuffer");
        //     //     // }
        //     //
        //     //     // Check if it has the expected fields
        //     //     // if (!@hasField(type_info.Pointer.child, "vertices")) {
        //     //     //     @compileError("Type must have 'vertices' field");
        //     //     // }
        //     //
        //     //     sdl_buffer = @ptrCast(vertex_buffer.ptr);
        //     // }
        //
        //     {
        //         {
        //             copy_pass.ptr.?.uploadToBuffer(.{ .transfer_buffer = self.ptr, .offset = 0 }, .{
        //                 .buffer = buffer.,
        //                 .offset = 0,
        //                 .size = buffer.getDataLength(),
        //             }, false);
        //         }
        //         // {
        //         //     const ibo = self.buffers.get(.solid_index);
        //         //     copy_pass.uploadToBuffer(.{ .transfer_buffer = tbo, .offset = pipeline.vertex_size }, .{
        //         //         .buffer = ibo,
        //         //         .offset = 0,
        //         //         // TODO: Vertex Buffer should have more info
        //         //         .size = pipeline.index_size * 2,
        //         //     }, false);
        //         // }
        //     }
        //     // {
        //     //     const tbo = self.transfer_buffers.get(.atlas_texture_data);
        //     //     const texture = self.textures.get(.atlas);
        //     //     const img = self.images.get(.atlas);
        //     //     copy_pass.uploadToTexture(.{ .transfer_buffer = tbo, .offset = 0 }, .{
        //     //         .texture = texture,
        //     //         .width = @intCast(img.getWidth()),
        //     //         .height = @intCast(img.getHeight()),
        //     //         .depth = 1,
        //     //     }, false);
        //     // }
        // }

        pub fn uploadIndexBuffer() void {}

        pub fn uploadTexture(self: *Self, copy_pass: CopyPass, texture: Texture) void {
            copy_pass.ptr.?.uploadToTexture(.{ .transfer_buffer = self.ptr, .offset = 0 }, .{
                .texture = texture.ptr,
                .width = texture.width,
                .height = texture.heigth,
                .depth = 1,
            }, false);
        }

        fn mapToGpu(self: *Self, cycle: bool) ![*]u8 {
            return self.gpu.device.mapTransferBuffer(self.ptr, cycle);
        }

        fn unmapToGpu(self: *Self) void {
            self.gpu.device.unmapTransferBuffer(self.ptr);
        }
    };
}

pub const BufferOrchestratorType = enum { vertices, texture };
pub const VertexBufferConfig = struct { layout: BufferLayout, max_vertices: u32 };
pub const IndexBufferConfig = struct { max_indices: u32 };
pub const BuffersConfig = struct {
    vertex_buffer: VertexBufferConfig,
    index_buffer: IndexBufferConfig,
};
// TODO
pub fn BufferOrchestrator(usage: TransferBufferType, comptime index_type: IndexBufferType) type {
    return struct {
        const Self = @This();
        vertex_buffer: VertexBuffer,
        index_buffer: IndexBuffer(index_type),
        transfer_buffer: TransferBuffer(usage),

        pub fn create(gpu: *GPU, config: BuffersConfig) !Self {
            const vertex_buffer = try VertexBuffer.create(gpu, config.vertex_buffer.layout, config.vertex_buffer.max_vertices);
            const index_buffer = try IndexBuffer(index_type).create(gpu, config.index_buffer.max_indices);
            const transfer_buffer = try TransferBuffer(usage).create(gpu, vertex_buffer.size_bytes + index_buffer.size_bytes);

            return .{
                .vertex_buffer = vertex_buffer,
                .index_buffer = index_buffer,
                .transfer_buffer = transfer_buffer,
            };
        }

        pub fn destroy(self: *Self) void {
            self.vertex_buffer.destroy();
            self.index_buffer.destroy();
            self.transfer_buffer.destroy();
        }

        // pub fn setData(self: *Self, data: []const u8) void {
        //
        // }

        // pub fn
    };
}
