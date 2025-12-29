const sdl = @import("sdl3");
const vec = @import("../math/vec.zig");
const color = @import("../math/color.zig");

//  ██████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗██╗ ██████╗███████╗
// ██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██║  ██║██║██╔════╝██╔════╝
// ██║  ███╗██████╔╝███████║██████╔╝███████║██║██║     ███████╗
// ██║   ██║██╔══██╗██╔══██║██╔═══╝ ██╔══██║██║██║     ╚════██║
// ╚██████╔╝██║  ██║██║  ██║██║     ██║  ██║██║╚██████╗███████║
//  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝ ╚═════╝╚══════╝

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const RenderPass = struct {
    gpu_target_info: sdl.gpu.ColorTargetInfo,
    gpu_pass: ?sdl.gpu.RenderPass,
    clear_color: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    // pass_action: sg.PassAction = .{},
};

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
