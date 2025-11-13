const std = @import("std");
const uuid = @import("../math/uuid.zig");
const vec = @import("../math/vec.zig");
const hex = @import("../math/hex.zig");
const color = @import("../math/color.zig");
// const log = @import("../debug/log.zig").ecs;
const shape = @import("../math/shape.zig");
const sokol = @import("sokol");
const sapp = sokol.app;

const Mat4 = vec.Mat4;

// ACSII Generator: https://patorjk.com/software/taag/#p=display&f=ANSI%20Shadow&t=Graphics

//  ██████╗ ██████╗ ██████╗ ███████╗
// ██╔════╝██╔═══██╗██╔══██╗██╔════╝
// ██║     ██║   ██║██████╔╝█████╗
// ██║     ██║   ██║██╔══██╗██╔══╝
// ╚██████╗╚██████╔╝██║  ██║███████╗
//  ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝

pub const EnvironmentInfo = struct {
    world_time: f64,
    window_width: i32 = 0,
    window_height: i32 = 0,
};

pub const ID = struct {
    id: uuid.Uuid = uuid.new(),
};

pub const GameObject = struct {
    pos: vec.Vec3 = vec.Vec3.zero(),
};

//  ██████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗██╗ ██████╗███████╗
// ██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██║  ██║██║██╔════╝██╔════╝
// ██║  ███╗██████╔╝███████║██████╔╝███████║██║██║     ███████╗
// ██║   ██║██╔══██╗██╔══██║██╔═══╝ ██╔══██║██║██║     ╚════██║
// ╚██████╔╝██║  ██║██║  ██║██║     ██║  ██║██║╚██████╗███████║
//  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝ ╚═════╝╚══════╝

pub const ShapeType = enum {
    hexagon,
    rect,
    triangle,
    circle,
    quad,
    pyramid,
    cube,
    none,
};

pub const Shape = union(enum) {
    hexagon: HexagonShape,
};

pub const HexagonShape = shapeMaker(.hexagon).make();
// pub const Shape = struct {
//
//     const Self = @This();
//     type: ShapeType = .none,
//     vertices: []vec.Vec3 = undefined,
//     tex_coords: []vec.Vec2 = undefined,
//     indices: []u32 = undefined,
//     vertex_colors: []color.ColorUB4 = undefined,
//
//     pub fn make(t: ShapeType) Shape {
//         var s: Shape = .{};
//         s.type = t;
//         s.vertices = &[1]vec.Vec3{vec.Vec3.zero()};
//         s.tex_coords = &[1]vec.Vec3{vec.Vec2.zero()};
//         s.indices = &[1]u32{0};
//         s.vertex_colors = &[1]color.ColorUB4{.{}};
//         return s;
//     }
// };

fn shapeMaker(comptime T: ShapeType) type {
    const vertices = switch (T) {
        .hexagon => 6,
        else => 0,
    };
    const indices = switch (T) {
        .hexagon => 6,
        else => 0,
    };
    const tex_coords = switch (T) {
        .hexagon => 0,
        else => 0,
    };
    const vertex_colors = switch (T) {
        .hexagon => 6,
        else => 0,
    };

    return struct {
        const Self = @This();
        type: ShapeType = T,
        vertices: [vertices]vec.Vec3 = @splat(vec.Vec3.zero()),
        tex_coords: [tex_coords]vec.Vec2 = @splat(vec.Vec2.zero()),
        indices: [indices]u32 = @splat(0),
        vertex_colors: [vertex_colors]color.ColorUB4 = @splat(.{}),

        // struct ShapeComponent
        // {
        // Rendering::ShapeTypes CurrentShape = Rendering::ShapeTypes::None;
        // Ref<std::vector<Math::vec3>> Vertices {};
        // Ref<std::vector<Math::vec2>> TextureCoordinates {};
        // Ref<std::vector<uint32_t>> Indices {};
        // Ref<std::vector<Math::vec4>> VertexColors {};
        // Ref<Rendering::Shader> Shader;
        // Rendering::ShaderSpecification ShaderSpecification {Rendering::ColorInputType::None, Rendering::TextureInputType::None, false, true, true, Rendering::RenderingType::DrawIndex, false};
        // Assets::AssetHandle ShaderHandle{ Assets::EmptyHandle };
        // Ref<Rendering::Texture2D> Texture;
        // Assets::AssetHandle TextureHandle{ Assets::EmptyHandle };
        // Buffer ShaderData;
        //         }

        pub fn make() type {
            return shapeMaker(T);
            // const s = Self{};
            // switch (T) {
            //     .hexagon => {
            //         // shape.vertices = hex.
            //     },
            //     else => {},
            // }
            //
            // return s;
        }
    };
}

pub const CircleCollider2D = struct {
    offset: vec.Vec2 = vec.Vec2.zero(),
    radius: f32 = 0.5,

    // struct CircleCollider2DComponent
    // {
    // Math::vec2 Offset = { 0.0f, 0.0f };
    // float Radius =  0.5f;
    //
    // // TODO: move into physics material maybe
    // float Density = 1.0f;
    // float Friction = 0.5f;
    // float Restitution = 0.0f;
    // float RestitutionThreshold = 0.5f;
    // bool IsSensor = false;
    //
    // // Storage for runtime
    // void* RuntimeFixture = nullptr;
    //
    // CircleCollider2DComponent() = default;
    // CircleCollider2DComponent(const CircleCollider2DComponent&) = default;
    // };
};

// ███╗   ███╗ █████╗ ██████╗
// ████╗ ████║██╔══██╗██╔══██╗
// ██╔████╔██║███████║██████╔╝
// ██║╚██╔╝██║██╔══██║██╔═══╝
// ██║ ╚═╝ ██║██║  ██║██║
// ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝

pub const OverlayType = enum {
    objective,
    icy,
    difficult,
    hazardous,
    obstacle,
    trap,
    corridor,
};

pub const Coordinate = struct { x: i8, y: i8 };

pub const Overlay = struct {
    type: OverlayType,
};

// pub const Tile = struct {
//     coord: Coordinate,
//     overlay: Overlay,
// };
pub const Tile = struct {
    coord: Coordinate,
    overlay: []const u8,
};

pub const Map = struct {
    map_tiles_offset: []const MapTileOffset,
};

pub const MapTileOffset = struct {
    map_tile: MapTile,
    offset: Coordinate,
};

pub const MapTile = struct {
    tiles: []const Tile,
    name: []const u8,
};

pub const Scenario = struct {
    map: Map,
    name: []const u8,
    id: u8,
};

// ██╗███╗   ██╗██████╗ ██╗   ██╗████████╗███████╗
// ██║████╗  ██║██╔══██╗██║   ██║╚══██╔══╝██╔════╝
// ██║██╔██╗ ██║██████╔╝██║   ██║   ██║   ███████╗
// ██║██║╚██╗██║██╔═══╝ ██║   ██║   ██║   ╚════██║
// ██║██║ ╚████║██║     ╚██████╔╝   ██║   ███████║
// ╚═╝╚═╝  ╚═══╝╚═╝      ╚═════╝    ╚═╝   ╚══════╝

pub const Event = sapp.Event;
pub const InputEvent = packed struct {
    code: sapp.Keycode,
    status: sapp.EventType,
};

pub const InputsState = struct {
    keys: std.EnumArray(sapp.Keycode, sapp.EventType),
    mouse: MouseState,
};

pub const MouseState = struct {
    cursor: vec.Vec2,
    speed: vec.Vec2,
    scroll: vec.Vec2,
    buttons: std.EnumArray(sapp.Mousebutton, sapp.EventType),
};

// pub const InputKey = struct {
//     code: sapp.Keycode,
//     state: KeyState,
// };
//
// pub const ButtonState = struct {
//     code: sapp.Mousebutton,
//     state: KeyState,
// };

// pub const KeyState = enum {
//     released,
//     pressed,
// };

// pub const Event = struct {
//     frame_count: u64 = 0,
//     type: EventType = .INVALID,
//     key_code: Keycode = .INVALID,
//     char_code: u32 = 0,
//     key_repeat: bool = false,
//     modifiers: u32 = 0,
//     mouse_button: Mousebutton = .LEFT,
//     mouse_x: f32 = 0.0,
//     mouse_y: f32 = 0.0,
//     mouse_dx: f32 = 0.0,
//     mouse_dy: f32 = 0.0,
//     scroll_x: f32 = 0.0,
//     scroll_y: f32 = 0.0,
//     num_touches: i32 = 0,
//     touches: [8]Touchpoint = [_]Touchpoint{.{}} ** 8,
//     window_width: i32 = 0,
//     window_height: i32 = 0,
//     framebuffer_width: i32 = 0,
//     framebuffer_height: i32 = 0,
// };

// ██████╗ ██╗  ██╗██╗   ██╗███████╗██╗ ██████╗███████╗
// ██╔══██╗██║  ██║╚██╗ ██╔╝██╔════╝██║██╔════╝██╔════╝
// ██████╔╝███████║ ╚████╔╝ ███████╗██║██║     ███████╗
// ██╔═══╝ ██╔══██║  ╚██╔╝  ╚════██║██║██║     ╚════██║
// ██║     ██║  ██║   ██║   ███████║██║╚██████╗███████║
// ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝ ╚═════╝╚══════╝

//  ██████╗ █████╗ ███╗   ███╗███████╗██████╗  █████╗
// ██╔════╝██╔══██╗████╗ ████║██╔════╝██╔══██╗██╔══██╗
// ██║     ███████║██╔████╔██║█████╗  ██████╔╝███████║
// ██║     ██╔══██║██║╚██╔╝██║██╔══╝  ██╔══██╗██╔══██║
// ╚██████╗██║  ██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║
//  ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝

pub const Camera = struct {
    primary: bool = false,
    type: CameraType = .orthographic,
};

pub const CameraType = enum {
    perspective,
    orthographic,
};

pub const OrthographicCamera = CameraMaker(.orthographic);
pub const PerspectiveCamera = CameraMaker(.perspective);

fn CameraMaker(comptime T: CameraType) type {
    return struct {
        const Self = @This();
        type: CameraType = T,
        mvp: Mat4 = Mat4.identity(),
        projection_matrix: Mat4 = Mat4.identity(),
        view_matrix: Mat4 = Mat4.identity(),
        pos: vec.Vec3 = .{ .x = 0, .y = 1.5, .z = 6 },
        look_at: vec.Vec3 = vec.Vec3.zero(),
        direction: vec.Vec3 = vec.Vec3.up(),
        viewport: shape.IRect = shape.IRect.zero(),
        scissor: shape.IRect = .{ .x = 0, .y = 0, .h = 0, .w = 0 },

        pub fn setViewport(self: *Self, vp: shape.IRect) void {
            self.viewport = vp;
            self.offsetScissor(vp.x, vp.y);
            self.computeView();
            self.computeProj();
            self.computeMvp();
        }

        pub fn resetViewport(self: *Self, width: i32, height: i32) void {
            self.viewport = .{ .x = 0, .y = 0, .w = width, .h = height };
            self.resetProj();
            self.resetScissor();
        }

        fn resetProj(self: *Self) void {
            const ratio: f32 = if (self.viewport.h != 0) @as(f32, @floatFromInt(self.viewport.w)) / @as(f32, @floatFromInt(self.viewport.h)) else 1;
            const fov: f32 = std.math.degreesToRadians(70); // We assume the angle view from the eye to the monitor is 45 degrees
            self.projection_matrix = Mat4.proj(fov, ratio, 0.1, 100);
        }

        // fn computeProj(self: *Self, fov: f32, aspect_ratio:f32, near: f32, far: f32) void {
        fn computeProj(self: *Self) void {
            //TODO
            // const ratio: f32 = if (self.viewport.h != 0) @divExact(self.viewport.w, self.viewport.h) else 1;
            // const ratio: f32 = if (self.viewport.h != 0) @as(f32, @floatFromInt(self.viewport.w)) / @as(f32, @floatFromInt(self.viewport.h)) else 1;
            // const fov: f32 = std.math.degreesToRadians(45); // We assume the angle view from the eye to the monitor is 45 degrees
            // self.projection_matrix = Mat4.proj(fov, ratio, 0.1, 100);

            // self.proj = Mat4.proj(fov, ratio, 0.1, 100);
            self.resetProj();
        }

        /// The formula is:
        /// 1. Model: Scale * Rotation * Translation
        /// 2. View: 1) translate the world so that the camera is at the origin; 2) reorient the world so that the camera's forward axis points along Z, right axis points along X, and up axis points along Y. As before, you can come up with these individual transform equations pretty easily and then multiply them together, but it's more efficient to have one formula that builds the entire View Matrix.
        /// 3. Projection:
        ///    Rescale the horizontal space so that -1 is the camera's left edge, and +1 is the camera's right edge. Keep in mind that with a perspective projection, the "edges" are constantly widening as you move farther from the camera, so it's not a simple rescaling.
        ///    Rescale the vertical space so that so that -1 is the camera's bottom edge, and +1 is the camera's top edge (or vice-versa).
        ///    Rescale the depth (Z axis) so that 0 represents being right in front of the camera, and 1 represents the farthest distance that the camera can see. In some cases, it's not 0 to 1 but -1 to +1, like the other axes. Self transformation is usually *extremely* non-linear, with most of the floating-point precision wasted in the tiny space right in front of the camera. Self makes Z-fighting a common problem for far-away surfaces, due to the lack of precision. There has been some work on using a different depth equation to spread out the values more.
        fn computeMvp(self: *Self) void {

            // self.mvp = Mat4.mul(self.projection_matrix, Mat4.mul(self.view_matrix, self.model));
            self.mvp = Mat4.mul(self.projection_matrix, self.view_matrix);
            // log.debug("[Delil.Camera][DEBUG] computeMvp: MVP{}, Projection{},  View{}, Pos{}", .{ self.mvp, self.projection_matrix, self.view_matrix, self.pos });

            // self.mvp = vec.Mat2x3.mul_proj_transform(&self.proj, &self.transform);
        }

        fn computeView(self: *Self) void {
            self.view_matrix = Mat4.lookat(self.pos, self.look_at, self.direction);
        }

        pub fn offsetScissor(self: *Self, x: i32, y: i32) void {
            if (!(self.scissor.w < 0 and self.scissor.h < 0)) {
                self.scissor.x += x - self.viewport.x;
                self.scissor.y += y - self.viewport.y;
            }
        }

        fn resetScissor(self: *Self) void {
            self.scissor = .{ .x = 0, .y = 0, .w = -1, .h = -1 };
        }
    };
}
