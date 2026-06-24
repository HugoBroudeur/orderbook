const std = @import("std");
const zm = @import("zmath");

const MaterialInstance = @import("materials.zig").MaterialInstance;
const Buffer = @import("../vulkan/buffer.zig");

pub const Bounds = struct {
    origin: [3]f32 = .{ 0, 0, 0 },
    sphere_radius: f32 = 0,
    extents: [3]f32 = .{ 0, 0, 0 },
};

pub const RenderObject = struct {
    index_count: u32,
    first_index: u32,
    index_buffer: Buffer,

    vertex_buffer: Buffer,
    vertex_buffer_offset: u64 = 0,

    material: *MaterialInstance,

    transform: zm.Mat,
    bounds: Bounds = .{},

    pub fn isVisible(self: *const RenderObject, viewproj: zm.Mat) bool {
        // Build model-view-projection:
        // mul(A,B) applies A first then B, so this is: model → view → proj.
        const matrix = zm.mul(self.transform, viewproj);

        var clip_min = zm.f32x4(1.5, 1.5, 1.5, 0.0);
        var clip_max = zm.f32x4(-1.5, -1.5, -1.5, 0.0);

        // 8 corners of a unit cube scaled and offset by the AABB.
        const corners = [8][3]f32{
            .{ 1, 1, 1 },  .{ 1, 1, -1 },  .{ 1, -1, 1 },  .{ 1, -1, -1 },
            .{ -1, 1, 1 }, .{ -1, 1, -1 }, .{ -1, -1, 1 }, .{ -1, -1, -1 },
        };

        for (corners) |s| {
            const wx = self.bounds.origin[0] + s[0] * self.bounds.extents[0];
            const wy = self.bounds.origin[1] + s[1] * self.bounds.extents[1];
            const wz = self.bounds.origin[2] + s[2] * self.bounds.extents[2];

            // Row-vector * matrix = clip-space position.
            const clip = zm.mul(zm.f32x4(wx, wy, wz, 1.0), matrix);
            const w = clip[3];
            // Perspective divide into NDC.
            const ndc = zm.f32x4(clip[0] / w, clip[1] / w, clip[2] / w, 0.0);

            clip_min = @min(clip_min, ndc);
            clip_max = @max(clip_max, ndc);
        }

        // Vulkan NDC: x ∈ [-1,1], y ∈ [-1,1], z ∈ [0,1]
        if (clip_min[2] > 1.0 or clip_max[2] < 0.0 or
            clip_min[0] > 1.0 or clip_max[0] < -1.0 or
            clip_min[1] > 1.0 or clip_max[1] < -1.0)
        {
            return false;
        }
        return true;
    }
};
