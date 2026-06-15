const std = @import("std");
const zm = @import("zmath");

const MaterialInstance = @import("materials.zig").MaterialInstance;
const Buffer = @import("../vulkan/buffer.zig");

pub const RenderObject = struct {
    index_count: u32,
    first_index: u32,
    index_buffer: Buffer,

    vertex_buffer: Buffer,
    vertex_buffer_offset: u64 = 0,

    material: *MaterialInstance,

    transform: zm.Mat,
};
