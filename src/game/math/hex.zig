const std = @import("std");
const vec = @import("vec.zig");
const math = std.math;

pub const SIZE = 0.3;

// pub const layout_pointy: Orientation
//   = Orientation(sqrt(3.0), sqrt(3.0) / 2.0, 0.0, 3.0 / 2.0,
//                 sqrt(3.0) / 3.0, -1.0 / 3.0, 0.0, 2.0 / 3.0,
//                 0.5);
// pub const layout_flat:Orientation
//   = Orientation(3.0 / 2.0, 0.0, sqrt(3.0) / 2.0, sqrt(3.0),
//                 2.0 / 3.0, 0.0, -1.0 / 3.0, sqrt(3.0) / 3.0,
//                 0.0);

pub const layout_pointy: Orientation = .{
    .transform_hex_to_px = .{
        .x = std.math.sqrt(3),
        .y = std.math.sqrt(3) / 2,
        .z = 0,
        .a = 3 / 2,
    },
    .transform_px_to_hex = .{
        .x = std.math.sqrt(3) / 3,
        .y = -1 / 3,
        .z = 0,
        .a = 2 / 3,
    },
    .start_angle = 0.5,
};

pub const layout_flat: Orientation = .{
    .transform_hex_to_px = .{
        .x = 3 / 2,
        .y = 0,
        .z = std.math.sqrt(3) / 2,
        .a = std.math.sqrt(3),
    },
    .transform_px_to_hex = .{
        .x = 2 / 3,
        .y = 0,
        .z = -1 / 3,
        .a = std.math.sqrt(3) / 3,
    },
    .start_angle = 0,
};

pub const Orientation = struct {
    transform_hex_to_px: vec.Vec4,
    transform_px_to_hex: vec.Vec4,

    /// In multiples of 60°
    start_angle: f32,
};

pub const Layout = struct {
    orientation: Orientation,
    size: vec.Vec2,
    origin: vec.Vec2,
};

pub const DEFAULT_LAYOUT = Layout{
    .orientation = layout_flat,
    .size = vec.Vec2{ .x = SIZE, .y = SIZE },
    .origin = vec.Vec2.zero(),
};

pub const Hex = struct {
    const Self = @This();
    q: i32 = 0,
    r: i32 = 0,
    s: i32 = 0,

    pub fn init(q: i32, r: i32, s: i32) !Hex {
        if (q + r + s != 0) return error.InvalidHex;
        return Hex{ .q = q, .r = r, .s = s };
    }

    pub fn add(a: Hex, b: Hex) Hex {
        return Hex{ .q = a.q + b.q, .r = a.r + b.r, .s = a.s + b.s };
    }

    pub fn subtract(a: Hex, b: Hex) Hex {
        return Hex{ .q = a.q - b.q, .r = a.r - b.r, .s = a.s - b.s };
    }

    pub fn scale(a: Hex, k: i32) Hex {
        return Hex{ .q = a.q * k, .r = a.r * k, .s = a.s * k };
    }

    pub fn rotateLeft(a: Hex) Hex {
        return Hex{ .q = -a.s, .r = -a.q, .s = -a.r };
    }

    pub fn rotateRight(a: Hex) Hex {
        return Hex{ .q = -a.r, .r = -a.s, .s = -a.q };
    }

    pub fn length(self: Hex) i32 {
        return @divTrunc((math.absCast(self.q) + math.absCast(self.r) + math.absCast(self.s)), 2);
    }

    pub fn distance(a: Hex, b: Hex) i32 {
        return a.subtract(a, b).length();
    }

    pub fn hex_to_pixel(h: Self, layout: Layout) vec.Vec2 {
        const M = &layout.orientation;
        const x: f32 = (M.transform_hex_to_px.x * @as(f32, @floatFromInt(h.q)) + M.transform_hex_to_px.y * @as(f32, @floatFromInt(h.r))) * layout.size.x;
        const y: f32 = (M.transform_hex_to_px.z * @as(f32, @floatFromInt(h.q)) + M.transform_hex_to_px.a * @as(f32, @floatFromInt(h.r))) * layout.size.y;

        return vec.Vec2{
            .x = x + layout.origin.x,
            .y = y + layout.origin.y,
        };
    }
};

pub const FractionalHex = struct {
    q: f64,
    r: f64,
    s: f64,

    pub fn init(q: f64, r: f64, s: f64) !FractionalHex {
        if (math.round(q + r + s) != 0) return error.InvalidHex;
        return FractionalHex{ .q = q, .r = r, .s = s };
    }

    pub fn round(self: FractionalHex) Hex {
        var qi: u16 = @intFromFloat(math.round(self.q));
        var ri: u16 = @intFromFloat(math.round(self.r));
        var si: u16 = @intFromFloat(math.round(self.s));

        const q_diff = math.absCast(qi - self.q);
        const r_diff = math.absCast(ri - self.r);
        const s_diff = math.absCast(si - self.s);

        if (q_diff > r_diff and q_diff > s_diff) {
            qi = -ri - si;
        } else if (r_diff > s_diff) {
            ri = -qi - si;
        } else {
            si = -qi - ri;
        }

        return Hex{ .q = qi, .r = ri, .s = si };
    }

    pub fn lerp(a: FractionalHex, b: FractionalHex, t: f64) FractionalHex {
        return FractionalHex{
            .q = a.q * (1.0 - t) + b.q * t,
            .r = a.r * (1.0 - t) + b.r * t,
            .s = a.s * (1.0 - t) + b.s * t,
        };
    }

    pub fn pixel_to_hex(layout: Layout, p: vec.Vec(f32)) FractionalHex {
        const M: *Orientation = &layout.orientation;
        const pt: vec.Vec2 = vec.Vec2{
            .x = (p.x - layout.origin.x) / layout.size.x,
            .y = (p.y - layout.origin.y) / layout.size.y,
        };
        const q: f32 = M.transform_px_to_hex.x * pt.x + M.transform_px_to_hex.y * pt.y;
        const r: f32 = M.transform_hex_to_px.z * pt.x + M.transform_hex_to_px.a * pt.y;
        return FractionalHex(q, r, -q - r);
    }
};
