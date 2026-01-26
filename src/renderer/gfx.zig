const Interfaces = @import("interfaces.zig");

pub const BackendType = enum {
    vulkan,
    sdl,
};

// pub const Api = struct {
//     asset: Interfaces.Asset,
//     batcher: Interfaces.Batcher,
//     buffer: Interfaces.Buffer,
//     copy_pass: Interfaces.Copypass,
//     gpu: Interfaces.GPU,
//     pipeline: Interfaces.Asset,
//     render_pass: Interfaces.RenderPass,
//     renderer_2d: Interfaces.Renderer2D,
//     sampler: Interfaces.Sampler,
//     texture: Interfaces.Texture,
// };
//
// pub fn Backend(comptime T: BackendType) Api {
//     return switch (T) {
//         .sdl => .{
//             .asset = @import("sdl/asset.zig").interface(),
//             .batcher = @import("sdl/batcher.zig").interface(),
//             .buffer = @import("sdl/buffer.zig").interface(),
//             .copy_pass = @import("sdl/pass.zig").CopyPass.interface(),
//             .gpu = @import("sdl/gpu.zig").interface(),
//             .pipeline = @import("sdl/pipeline.zig").interface(),
//             .render_pass = @import("sdl/pass.zig").RenderPass.interface(),
//             .renderer_2d = @import("sdl/renderer_2d.zig").interface(),
//             .sampler = @import("sdl/sampler.zig").interface(),
//             .texture = @import("sdl/texture.zig").interface(),
//         },
//         .vulkan => .{
//             .asset = @import("vulkan/asset.zig").interface(),
//             .batcher = @import("vulkan/batcher.zig").interface(),
//             .buffer = @import("vulkan/buffer.zig").interface(),
//             .copy_pass = @import("vulkan/pass.zig").CopyPass.interface(),
//             .gpu = @import("vulkan/gpu.zig").interface(),
//             .pipeline = @import("vulkan/pipeline.zig").interface(),
//             .render_pass = @import("vulkan/pass.zig").RenderPass.interface(),
//             .renderer_2d = @import("vulkan/renderer_2d.zig").interface(),
//             .sampler = @import("vulkan/sampler.zig").interface(),
//             .texture = @import("vulkan/texture.zig").interface(),
//         },
//     };
// }
