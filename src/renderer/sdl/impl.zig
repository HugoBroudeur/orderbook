// This is the implementation for SDL3

pub const Backend = @import("../backend.zig").Backend;

pub const Asset = @import("asset.zig");
pub const Batcher = @import("batcher.zig");
pub const Buffer = @import("buffer.zig");
pub const CopyPass = @import("pass.zig").CopyPass;
pub const GPU = @import("gpu.zig");
pub const Pipeline = @import("pipeline.zig");
pub const RenderPass = @import("pass.zig").RenderPass;
pub const Renderer2D = @import("renderer_2d.zig");
pub const Sampler = @import("sampler.zig");
pub const Texture = @import("texture.zig");

pub const backend: Backend = .sdl;
