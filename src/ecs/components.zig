const std = @import("std");
const sdl = @import("sdl3");
const Serde = @import("serde");

const zm = @import("zmath");
const IRect = @import("../primitive.zig").IRect;
const Uuid = @import("uuid");

// ACSII Generator: https://patorjk.com/software/taag/#p=display&f=ANSI%20Shadow&t=Graphics

//  ██████╗ ██████╗ ██████╗ ███████╗
// ██╔════╝██╔═══██╗██╔══██╗██╔════╝
// ██║     ██║   ██║██████╔╝█████╗
// ██║     ██║   ██║██╔══██╗██╔══╝
// ╚██████╗╚██████╔╝██║  ██║███████╗
//  ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝

pub const ID = struct { guid: Uuid.Uuid = 0 };
pub const Tag = enum {
    data,
    mesh,
    event,
};

pub const Timers = struct {
    dt: u64 = 0,
    world_time: u64 = 0,
};

pub const WindowState = struct {
    width: i32 = 0,
    height: i32 = 0,
};

pub const Stats = @import("../engine/stats.zig");

//  ██████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗██╗ ██████╗███████╗
// ██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██║  ██║██║██╔════╝██╔════╝
// ██║  ███╗██████╔╝███████║██████╔╝███████║██║██║     ███████╗
// ██║   ██║██╔══██╗██╔══██║██╔═══╝ ██╔══██║██║██║     ╚════██║
// ╚██████╔╝██║  ██║██║  ██║██║     ██║  ██║██║╚██████╗███████║
//  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝ ╚═════╝╚══════╝

pub const Transform = struct {
    translation: Translation = .{},
    /// Identity quaternion
    rotation: [4]f32 = .{ 0, 0, 0, 1 },
    scale: Scale = .{},
};

const Translation = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

const Scale = struct {
    x: f32 = 1,
    y: f32 = 1,
    z: f32 = 1,
};

pub const CameraActive = struct {
    is_active: bool = true,
};
pub const CameraSpeed = struct {
    speed: f32 = 0.05,
};
pub const CameraSensitivity = struct {
    sensitivity: f32 = 200,
    /// -1: normal, 1: inverted
    inverted_multiplier: f32 = -1,
};

pub const RenderCamera = Camera;

pub const Camera = struct {
    pub const CameraType = enum { orthographic, perspective };

    kind: CameraType,

    speed: f32 = 0.05,
    sensitivity: f32 = 200,

    mvp: zm.Mat = zm.identity(),
    projection_matrix: zm.Mat = zm.identity(),
    view_matrix: zm.Mat = zm.identity(),
    /// eye position
    pos: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
    /// focus point
    look_at: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
    /// up direction ('w' coord is zero because this is a vector not a point)
    up: [4]f32 = .{ 0.0, 1.0, 0.0, 0.0 },
    viewport: IRect = IRect.zero(),
    scissor: IRect = IRect.zero(),

    near: f32 = -1,
    far: f32 = 1,
    fov: f32 = 70,

    need_compute: bool = true,
    is_locked: bool = false,

    pub const serde = .{
        .skip = .{
            .mvp = Serde.SkipMode.always,
            .projection_matrix = Serde.SkipMode.always,
            .view_matrix = Serde.SkipMode.always,
        },
    };

    pub fn setViewport(self: *Camera, rect: IRect) void {
        if (!self.viewport.eq(rect)) self.need_compute = true;
        self.viewport = rect;
        self.offsetScissor(rect.x, rect.y);
        self.compute();
    }

    pub fn resetViewport(self: *Camera, width: f32, height: f32) void {
        self.viewport = .{ .x = 0, .y = 0, .w = width, .h = height };
        self.need_compute = true;
        self.resetScissor();
    }

    pub fn setFov(self: *Camera, fov_degrees: f32) void {
        self.fov = fov_degrees;
        self.need_compute = true;
    }

    pub fn setLookAt(self: *Camera, yaw: f32, pitch: f32) void {
        const yaw_rotation = zm.quatFromAxisAngle(.{ 0, -1, 0, 0 }, yaw);
        const pitch_rotation = zm.quatFromAxisAngle(.{ 1, 0, 0, 0 }, pitch);
        self.look_at = zm.qmul(pitch_rotation, yaw_rotation);
        self.need_compute = true;
    }

    pub fn setLookQuat(self: *Camera, quat: [4]f32) void {
        self.look_at = quat;
        self.need_compute = true;
    }

    pub fn getViewMatrix(self: *Camera) zm.Mat {
        self.compute();
        return self.view_matrix;
    }

    pub fn getProjectionMatrix(self: *Camera) zm.Mat {
        self.compute();
        return self.projection_matrix;
    }

    pub fn getViewProjMatrix(self: *Camera) zm.Mat {
        self.compute();
        return self.mvp;
    }

    fn compute(self: *Camera) void {
        if (!self.need_compute) return;

        const rot_matrix = zm.matFromQuat(self.look_at);
        const forward = zm.normalize3(zm.mul(zm.f32x4(0, 0, -1, 0), rot_matrix));
        self.view_matrix = zm.lookToRh(self.pos, forward, self.up);

        self.projection_matrix = switch (self.kind) {
            .perspective => zm.perspectiveFovRh(
                self.fov * (std.math.pi / 180.0),
                @as(f32, @floatFromInt(self.viewport.width)) / @as(f32, @floatFromInt(self.viewport.heigth)),
                self.near,
                self.far,
            ),
            .orthographic => zm.orthographicRh(
                @floatFromInt(self.viewport.width),
                @floatFromInt(self.viewport.heigth),
                -1,
                1,
            ),
        };

        self.projection_matrix[1][1] *= -1;
        self.mvp = zm.mul(self.view_matrix, self.projection_matrix);
        self.need_compute = false;
    }

    pub fn offsetScissor(self: *Camera, x: i32, y: i32) void {
        if (self.scissor.width < 0 or self.scissor.heigth < 0) return;
        self.scissor.x += x - self.viewport.x;
        self.scissor.y += y - self.viewport.y;
    }

    fn getAspectRatio(self: *Camera) f32 {
        return self.viewport.w / self.viewport.h;
    }

    fn resetScissor(self: *Camera) void {
        self.scissor = .{ .x = 0, .y = 0, .w = -1, .h = -1 };
    }
};

pub const Lights = struct {
    ambient_color: [4]f32 = .{ 1, 1, 1, 0.2 },
    sunlight_direction: [4]f32 = .{ 0, 1, 0.5, 1 }, // w for sun power
    sunlight_color: [4]f32 = .{ 1, 1, 1, 1 },
};

// ██╗███╗   ██╗██████╗ ██╗   ██╗████████╗███████╗
// ██║████╗  ██║██╔══██╗██║   ██║╚══██╔══╝██╔════╝
// ██║██╔██╗ ██║██████╔╝██║   ██║   ██║   ███████╗
// ██║██║╚██╗██║██╔═══╝ ██║   ██║   ██║   ╚════██║
// ██║██║ ╚████║██║     ╚██████╔╝   ██║   ███████║
// ╚═╝╚═╝  ╚═══╝╚═╝      ╚═════╝    ╚═╝   ╚══════╝

pub const InputState = struct {
    mouse: MouseState = .{},
    key: KeyState = .{},

    pub fn reset(self: *InputState) void {
        self.key.pressed = .initEmpty();
        self.key.released = .initEmpty();
        self.mouse.pressed = .initEmpty();
        self.mouse.released = .initEmpty();
        self.mouse.delta = .{ 0, 0 };
    }
};

pub const KeyState = struct {
    // Scancode values are sparse USB-HUT codes, so the bitset must span the
    // max *value*, not the number of named variants.
    const KEY_COUNT = blk: {
        var max: usize = 0;
        for (std.enums.values(sdl.Scancode)) |sc| max = @max(max, @intFromEnum(sc));
        break :blk max + 1;
    };

    // Keyboard — indexed by sdl.Scancode value
    held: std.bit_set.ArrayBitSet(usize, KEY_COUNT) = .initEmpty(),
    pressed: std.bit_set.ArrayBitSet(usize, KEY_COUNT) = .initEmpty(),
    released: std.bit_set.ArrayBitSet(usize, KEY_COUNT) = .initEmpty(),

    // -- Key queries ---------------------------------------------------------

    pub fn isPressed(self: *const KeyState, key: sdl.Scancode) bool {
        return self.pressed.isSet(@intFromEnum(key));
    }
    pub fn isHeld(self: *const KeyState, key: sdl.Scancode) bool {
        return self.held.isSet(@intFromEnum(key));
    }
    pub fn isReleased(self: *const KeyState, key: sdl.Scancode) bool {
        return self.released.isSet(@intFromEnum(key));
    }

    pub fn onKeyDown(self: *KeyState, scancode: sdl.Scancode) void {
        const i = @intFromEnum(scancode);
        self.pressed.set(i);
        self.held.set(i);
        self.released.unset(i);
    }

    pub fn onKeyUp(self: *KeyState, scancode: sdl.Scancode) void {
        const i = @intFromEnum(scancode);
        self.pressed.unset(i);
        self.held.unset(i);
        self.released.set(i);
    }
};

pub const MouseState = struct {
    const MOUSE_BUTTON_COUNT = std.enums.values(sdl.mouse.Button).len;
    pub const Button = enum(u3) {
        left = 0,
        middle = 1,
        right = 2,
        x1 = 3,
        x2 = 4,
    };

    // Mouse buttons — indexed by sdl button index (1-based, store at index-1)
    held: std.bit_set.IntegerBitSet(MOUSE_BUTTON_COUNT) = .initEmpty(),
    pressed: std.bit_set.IntegerBitSet(MOUSE_BUTTON_COUNT) = .initEmpty(),
    released: std.bit_set.IntegerBitSet(MOUSE_BUTTON_COUNT) = .initEmpty(),

    // Mouse position and per-frame delta
    pos: [2]f32 = .{ 0, 0 },
    delta: [2]f32 = .{ 0, 0 },

    // -- Mouse button queries ------------------------------------------------

    pub fn mousePressed(self: *const MouseState, btn: Button) bool {
        return self.pressed.isSet(@intFromEnum(btn));
    }
    pub fn mouseHeld(self: *const MouseState, btn: Button) bool {
        return self.held.isSet(@intFromEnum(btn));
    }
    pub fn mouseReleased(self: *const MouseState, btn: Button) bool {
        return self.released.isSet(@intFromEnum(btn));
    }

    pub fn onMouseDown(self: *MouseState, btn: Button) void {
        self.pressed.set(@intFromEnum(btn));
        self.held.set(@intFromEnum(btn));
        self.released.unset(@intFromEnum(btn));
    }

    pub fn onMouseUp(self: *MouseState, btn: Button) void {
        self.pressed.unset(@intFromEnum(btn));
        self.held.unset(@intFromEnum(btn));
        self.released.set(@intFromEnum(btn));
    }

    pub fn onMouseMotion(self: *MouseState, x: f32, y: f32, dx: f32, dy: f32) void {
        self.pos = .{ x, y };
        self.delta[0] += dx;
        self.delta[1] += dy;
    }
};

// pub const CameraInput = struct {
//     velocity: Velocity = .{},
//     delta_yaw: f32 = 0,
//     delta_pitch: f32 = 0,
//     delta_fov: f32 = 0,
// };

// ██████╗ ██╗  ██╗██╗   ██╗███████╗██╗ ██████╗███████╗
// ██╔══██╗██║  ██║╚██╗ ██╔╝██╔════╝██║██╔════╝██╔════╝
// ██████╔╝███████║ ╚████╔╝ ███████╗██║██║     ███████╗
// ██╔═══╝ ██╔══██║  ╚██╔╝  ╚════██║██║██║     ╚════██║
// ██║     ██║  ██║   ██║   ███████║██║╚██████╗███████║
// ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝ ╚═════╝╚══════╝

pub const Velocity = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

pub const Rotated = struct {
    /// Delta rotation in the entity's local frame. Rotations about world axes
    /// must be converted by the producer (express the world axis in local
    /// coordinates first — see cameraInput).
    /// Identity quaternion — a zero quat produces NaN under normalize.
    delta: [4]f32 = .{ 0, 0, 0, 1 },
};

// ███████╗██╗   ██╗███████╗███╗   ██╗████████╗███████╗
// ██╔════╝██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔════╝
// █████╗  ██║   ██║█████╗  ██╔██╗ ██║   ██║   ███████╗
// ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ╚════██║
// ███████╗ ╚████╔╝ ███████╗██║ ╚████║   ██║   ███████║
// ╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝

pub const RawInputQueue = @import("../framework/event_queue.zig");
