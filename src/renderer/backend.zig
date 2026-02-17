const std = @import("std");
const builtin = @import("builtin");

const Shared = struct {
    const Camera = @import("camera.zig");
    const Command = @import("command.zig");
    const Data = @import("data.zig");
    const Stats = @import("stats.zig");
};

pub const Vulkan = Api(.vulkan, @import("vulkan/impl.zig"));
pub const Sdl = Api(.sdl, @import("sdl/impl.zig"));

pub const Backend = enum {
    vulkan,
    sdl,

    /// Returns a recommend default backend from inspecting the system.
    pub fn default() Backend {
        return switch (builtin.os.tag) {
            .linux => .vulkan,
            .ios, .macos => .sdl,
            .freebsd => .vulkan,
            .wasi => .vulkan,
            .windows => .vulkan,
            else => {
                @compileLog(builtin.os);
                @compileError("no default backend for this target");
            },
        };
    }

    /// Candidate backends for this platform in priority order.
    pub fn candidates() []const Backend {
        return switch (builtin.os.tag) {
            .linux => &.{ .vulkan, .sdl },
            .ios, .macos => &.{.sdl},
            .freebsd => &.{ .vulkan, .sdl },
            .wasi => &.{.vulkan},
            .windows => &.{ .vulkan, .sdl },
            else => {
                @compileLog(builtin.os);
                @compileError("no candidate backends for this target");
            },
        };
    }

    /// Returns the Api for the given backend type.
    pub fn Api(comptime self: Backend) type {
        return switch (self) {
            .sdl => Sdl,
            .vulkan => Vulkan,
        };
    }
};

/// Creates the Graphics API based on a backend type.
///
/// For the default backend type for the system (i.e. Vulkan on Linux),
/// this is the main API for interacting with. It is forwarded into the renderer/api.zig
/// the "gfx" package so I use types such as `gfx.Pipeline`, `gfx.Buffer`,
/// etc.
pub fn Api(comptime be: Backend, comptime T: type) type {
    return struct {
        comptime {
            // This ensures that all the public decls from the API are forwarded
            // from the main struct.
            const main = @This();
            const default = Backend.default().Api();
            for (@typeInfo(default).@"struct".decls) |decl| {
                const Decl = @TypeOf(@field(default, decl.name));
                if (Decl == void) continue;
                if (!@hasDecl(main, decl.name)) {
                    @compileError("Backend API [" ++ @tagName(default.backend) ++ "] missing decl: " ++ decl.name);
                }
            }
        }

        const Self = @This();

        /// The backend that this is. This is supplied at comptime so
        /// it is up to the caller to say the right thing. This lets custom
        /// implementations also "quack" like an implementation.
        pub const backend = be;

        pub const Camera = Shared.Camera;
        pub const Command = Shared.Command;
        pub const Data = Shared.Data;
        pub const Stats = Shared.Stats;

        pub const Batcher = T.Batcher;
        pub const Buffer = T.Buffer;
        pub const GPU = T.GPU;
        pub const Pipeline = T.Pipeline;
        pub const RenderPass = T.RenderPass;
        pub const Renderer2D = T.Renderer2D;
        pub const Sampler = T.Sampler;
        pub const Texture = if (be == .vulkan) T.Image else T.Texture;

        /// A way to access the raw type.
        pub const Impl = T;

        test {
            @import("std").testing.refAllDecls(@This());
        }
    };
}
