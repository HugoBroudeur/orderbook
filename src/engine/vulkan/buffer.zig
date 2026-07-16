// The Buffers are for the Vulkan implementation
const std = @import("std");
const log = std.log.scoped(.buffer);
const assert = std.debug.assert;
const vk = @import("vulkan");

const Config = @import("../../config.zig");
const CommandPool = @import("command_pool.zig").CommandPool;
const GraphicsContext = @import("../../core/graphics_context.zig");
const Engine = @import("engine.zig");
const Shader = @import("shader.zig");

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

/// BufferLayout never allocate more space than the provided length size
pub const BufferLayout = struct {
    const Self = @This();
    elements: []BufferElement,

    stride: u32 = 0,

    pub fn init(elements: []BufferElement) Self {
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

        for (self.elements) |*element| {
            element.offset = offset;
            offset += element.size;
            self.stride += element.size;
        }
    }
};

const Buffer = @This();

engine: *Engine,

vk_buffer: vk.Buffer,
size: u32,
sharing_mode: vk.SharingMode,
memory: vk.DeviceMemory,
usage: vk.BufferUsageFlags,
properties: vk.MemoryPropertyFlags,
address: ?vk.DeviceAddress,

pub fn create(engine: *Engine, size: u32, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags) !Buffer {
    if (Config.log.buffer) {
        log.info("[Buffer.create] {} bytes", .{size});
    }

    const sharing_mode: vk.SharingMode = .exclusive;

    const bci: vk.BufferCreateInfo = .{
        .size = size,
        .usage = usage,
        .sharing_mode = sharing_mode,
    };
    const vk_buffer = try engine.ctx.device.createBuffer(&bci, null);

    const memory_requirements = engine.ctx.device.getBufferMemoryRequirements(vk_buffer);

    const alloc_info = try engine.ctx.createMemoryAllocateInfo(memory_requirements, properties, usage.shader_device_address_bit == true);
    const memory = try engine.ctx.device.allocateMemory(&alloc_info, null);

    try engine.ctx.device.bindBufferMemory(vk_buffer, memory, 0);

    var address: ?vk.DeviceAddress = null;
    if (usage.shader_device_address_bit == true) {
        // Disable that for now as I'm getting Vulkan errors
        const bdai: vk.BufferDeviceAddressInfo = .{ .buffer = vk_buffer };
        address = engine.ctx.device.getBufferDeviceAddress(&bdai);
        if (Config.log.buffer) {
            log.info("Create buffer size {} with address bit {?}", .{ size, address });
        }
    }

    return .{
        .engine = engine,
        .vk_buffer = vk_buffer,
        .size = size,
        .usage = usage,
        .sharing_mode = sharing_mode,
        .memory = memory,
        .properties = properties,
        .address = address,
    };
}

pub fn destroy(self: *Buffer) void {
    self.engine.ctx.device.freeMemory(self.memory, null);
    self.engine.ctx.device.destroyBuffer(self.vk_buffer, null);
}

pub fn copyInto(self: *Buffer, data: []const u8, offset: u64) !void {
    assert(self.size >= data.len + offset);
    assert(self.hasBindedMemory());

    var map: [*]u8 = @ptrCast(try self.engine.ctx.device.mapMemory(self.memory, offset, data.len, .{}));
    defer self.engine.ctx.device.unmapMemory(self.memory);

    std.mem.copyForwards(u8, map[0..data.len], data);
}

pub fn transfer(self: *Buffer, cmd_pool: *const CommandPool, dst: *Buffer, src_offset: u64, dst_offset: u64) !void {
    assert(dst.size - dst_offset >= self.size - src_offset);
    assert(self.hasBindedMemory() and dst.hasBindedMemory());
    assert(dst.usage.transfer_dst_bit == true);

    const alloc_info = vk.CommandBufferAllocateInfo{
        .level = .primary,
        .command_pool = cmd_pool.vk_cmd_pool,
        .command_buffer_count = 1,
    };

    var command_buffer: vk.CommandBuffer = undefined;
    try self.engine.ctx.device.allocateCommandBuffers(&alloc_info, @ptrCast(&command_buffer));
    defer self.engine.ctx.device.freeCommandBuffers(cmd_pool.vk_cmd_pool, &.{command_buffer});

    const begin_info = vk.CommandBufferBeginInfo{
        .flags = .{ .one_time_submit_bit = true },
        .p_inheritance_info = null,
    };

    { // Issue commands
        try self.engine.ctx.device.beginCommandBuffer(command_buffer, &begin_info);

        const copy_region = [_]vk.BufferCopy{.{
            .src_offset = src_offset,
            .dst_offset = dst_offset,
            .size = self.size,
        }};
        self.engine.ctx.device.cmdCopyBuffer(command_buffer, self.vk_buffer, dst.vk_buffer, &copy_region);

        try self.engine.ctx.device.endCommandBuffer(command_buffer);
    }

    const submit_infos = [_]vk.SubmitInfo{.{
        .wait_semaphore_count = 0,
        .p_wait_semaphores = undefined,
        .p_wait_dst_stage_mask = undefined,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&command_buffer),
        .signal_semaphore_count = 0,
        .p_signal_semaphores = undefined,
    }};

    try self.engine.ctx.device.queueSubmit(self.engine.ctx.graphics_queue.handle, &submit_infos, .null_handle);
    try self.engine.ctx.device.queueWaitIdle(self.engine.ctx.graphics_queue.handle);
}

pub fn resize(self: *Buffer, cmd_pool: *const CommandPool, size: u32) !void {
    assert(size > self.size);

    if (Config.log.buffer) {
        log.info("[Buffer.resize] {} -> {} bytes", .{ self.size, size });
    }

    var new_buffer = try Buffer.create(self.engine, size, self.usage, self.properties);
    errdefer new_buffer.destroy();

    try self.transfer(cmd_pool, &new_buffer, 0, 0);

    self.destroy();
    self.* = new_buffer;
}

// Fast Transfer creates a staging buffer and destroy it immediatly after
// Not recommended to use in loops
pub fn fastTransfer(self: *Buffer, cmd_pool: *const CommandPool, data: []const u8) !void {
    assert(data.len <= std.math.maxInt(u32));
    var staging_buffer = try Buffer.create(
        self.engine,
        @intCast(data.len),
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );
    defer staging_buffer.destroy();

    try staging_buffer.copyInto(data, 0);
    try staging_buffer.transfer(cmd_pool, self, 0, 0);
}

// Fast Transfer creates a staging buffer and destroy it immediatly after
// Not recommended to use in loops
pub fn fastTransferOffset(self: *Buffer, cmd_pool: *const CommandPool, data: []const u8, src_offset: u64, dst_offset: u64) !void {
    assert(data.len <= std.math.maxInt(u32));
    var staging_buffer = try Buffer.create(
        self.engine,
        @intCast(data.len),
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );
    defer staging_buffer.destroy();

    try staging_buffer.copyInto(data, src_offset);
    try staging_buffer.transfer(cmd_pool, self, src_offset, dst_offset);
}

fn hasBindedMemory(self: *Buffer) bool {
    return @intFromEnum(self.memory) > 0;
}
