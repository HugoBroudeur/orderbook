// 2D Command queue and 2D command data

const std = @import("std");

const zm = @import("zmath");

const DataStructure = @import("../data_structure.zig");
const Logger = @import("../core/log.zig").MaxLogs(50);

const Api = @import("backend.zig").Backend.default().Api();
const Batcher = Api.Batcher;
const Texture = Api.Texture;
const Engine = Api.Engine;

// const Batcher = @import("batcher.zig");
// const Texture = @import("texture.zig");
// const Renderer2D = @import("engine.zig");
const Primitive = @import("../primitive.zig");
const Clay = @import("zclay");
const Rect = Primitive.Rect;
const Color = Primitive.Color;
const Point = Primitive.Point;
// const ig = @import("cimgui");

const COMMAND_QUEUE_SIZE = 1000000;

pub const SceneData = struct {
    view: zm.Mat = zm.identity(),
    proj: zm.Mat = zm.identity(),
    view_proj: zm.Mat = zm.identity(),
    ambient_color: Color = Color.White,
    sunlight_direction: @Vector(4, f32) = .{ 1, 1, 1, 1 }, // w for sun power
    sunlight_color: Color = Color.White,
    time: f32 align(4) = 0,
};

pub const QuadImgCmd = struct {
    p1: Point,
    p2: Point,
    p3: Point,
    p4: Point,
    texture: Texture,
};

pub const QuadCmd = struct {
    p1: Point,
    p2: Point,
    p3: Point,
    p4: Point,
    color: Color = Color.White,
};

pub const QuadFillCmd = struct {
    p1: Point,
    p2: Point,
    p3: Point,
    p4: Point,
    color1: Color = Color.White,
    color2: Color = Color.White,
    color3: Color = Color.White,
    color4: Color = Color.White,
};

pub const MeshCmd = struct {
    p1: Point,
    p2: Point,
    p3: Point,
    p4: Point,
    color: Color = Color.White,
};

pub const ImguiCmd = struct {
    data: *anyopaque,
    // data: *ig.ImDrawData,
};

pub const ClayCmd = struct {
    render_cmd: Clay.RenderCommand,
};

pub const DrawQueue = struct {
    engine: *Engine,

    cmds: DataStructure.DynamicBuffer(DrawCmd),

    scene_data: SceneData = .{},

    // ptr
    last_cmd: usize = 0,
    current_cmd: usize = 0,

    pub fn init(allocator: std.mem.Allocator, engine: *Engine) !DrawQueue {
        return .{
            .engine = engine,
            .cmds = try .init(allocator, COMMAND_QUEUE_SIZE),
        };
    }

    pub fn deinit(self: *DrawQueue) void {
        self.cmds.deinit();
    }

    pub fn setSceneData(self: *DrawQueue, data: SceneData) void {
        self.scene_data = data;
    }

    pub fn push(self: *DrawQueue, cmd: DrawCmd) void {
        if (self.cmds.getRemainingSlot() == 0) {
            Logger.info("[DrawQueue.push] Command buffer full, flushing", .{});

            self.submit();
        }
        self.cmds.push(cmd);
    }

    pub fn rewind(self: *DrawQueue, to: usize) void {
        self.cmds.rewind(to);
    }

    pub fn submit(self: *DrawQueue) void {
        self.engine.update_scene(self);
    }
};

pub const DrawCmd = union(enum) {
    quad: QuadCmd,
    quad_img: QuadImgCmd,
    quad_fill: QuadFillCmd,
    imgui: ImguiCmd,
    clay: ClayCmd,

    pub inline fn getRect(self: DrawCmd) Rect {
        var rect: Rect = undefined;
        switch (self) {
            .quad => |c| {
                rect.x = @min(c.p1.x, c.p2.x, c.p3.x, c.p4.x);
                rect.y = @min(c.p1.y, c.p2.y, c.p3.y, c.p4.y);
                rect.width = @max(c.p1.x, c.p2.x, c.p3.x, c.p4.x) - rect.x;
                rect.height = @max(c.p1.y, c.p2.y, c.p3.y, c.p4.y) - rect.y;
            },
            .quad_img => |c| {
                rect.x = @min(c.p1.x, c.p2.x, c.p3.x, c.p4.x);
                rect.y = @min(c.p1.y, c.p2.y, c.p3.y, c.p4.y);
                rect.width = @max(c.p1.x, c.p2.x, c.p3.x, c.p4.x) - rect.x;
                rect.height = @max(c.p1.y, c.p2.y, c.p3.y, c.p4.y) - rect.y;
            },
            // .image_rounded => |c| {
            //     rect.x = c.pmin.x;
            //     rect.y = c.pmin.y;
            //     rect.width = c.pmax.x - c.pmin.x;
            //     rect.height = c.pmax.y - c.pmin.y;
            // },
            // .line => |c| {
            //     rect.x = @min(c.p1.x, c.p2.x);
            //     rect.y = @min(c.p1.y, c.p2.y);
            //     rect.width = @max(c.p1.x, c.p2.x) - rect.x;
            //     rect.height = @max(c.p1.y, c.p2.y) - rect.y;
            // },
            // .rect_rounded => |c| {
            //     rect.x = c.pmin.x;
            //     rect.y = c.pmin.y;
            //     rect.width = c.pmax.x - c.pmin.x;
            //     rect.height = c.pmax.y - c.pmin.y;
            // },
            // .rect_rounded_fill => |c| {
            //     rect.x = c.pmin.x;
            //     rect.y = c.pmin.y;
            //     rect.width = c.pmax.x - c.pmin.x;
            //     rect.height = c.pmax.y - c.pmin.y;
            // },
            // .quad_fill => |c| {
            //     rect.x = @min(c.p1.x, c.p2.x);
            //     rect.y = @min(c.p1.y, c.p2.y);
            //     rect.width = @max(c.p1.x, c.p2.x) - rect.x;
            //     rect.height = @max(c.p1.y, c.p2.y) - rect.y;
            // },
            // .triangle => |c| {
            //     rect.x = @min(c.p1.x, c.p2.x, c.p3.x);
            //     rect.y = @min(c.p1.y, c.p2.y, c.p3.y);
            //     rect.width = @max(c.p1.x, c.p2.x, c.p3.x) - rect.x;
            //     rect.height = @max(c.p1.y, c.p2.y, c.p3.y) - rect.y;
            // },
            // .triangle_fill => |c| {
            //     rect.x = @min(c.p1.x, c.p2.x, c.p3.x);
            //     rect.y = @min(c.p1.y, c.p2.y, c.p3.y);
            //     rect.width = @max(c.p1.x, c.p2.x, c.p3.x) - rect.x;
            //     rect.height = @max(c.p1.y, c.p2.y, c.p3.y) - rect.y;
            // },
            // .circle => |c| {
            //     rect.x = c.p.x - c.radius;
            //     rect.y = c.p.y - c.radius;
            //     rect.width = c.radius * 2;
            //     rect.height = c.radius * 2;
            // },
            // .circle_fill => |c| {
            //     rect.x = c.p.x - c.radius;
            //     rect.y = c.p.y - c.radius;
            //     rect.width = c.radius * 2;
            //     rect.height = c.radius * 2;
            // },
            // .ellipse => |c| {
            //     rect.x = c.p.x - c.radius.x;
            //     rect.y = c.p.y - c.radius.y;
            //     rect.width = c.radius.x * 2;
            //     rect.height = c.radius.y * 2;
            // },
            // .ellipse_fill => |c| {
            //     rect.x = c.p.x - c.radius.x;
            //     rect.y = c.p.y - c.radius.y;
            //     rect.width = c.radius.x * 2;
            //     rect.height = c.radius.y * 2;
            // },
            // .ngon => |c| {
            //     rect.x = c.p.x - c.radius;
            //     rect.y = c.p.y - c.radius;
            //     rect.width = c.radius * 2;
            //     rect.height = c.radius * 2;
            // },
            // .ngon_fill => |c| {
            //     rect.x = c.p.x - c.radius;
            //     rect.y = c.p.y - c.radius;
            //     rect.width = c.radius * 2;
            //     rect.height = c.radius * 2;
            // },
            // .convex_polygon_fill => |c| {
            //     var minx: f32 = std.math.floatMax(f32);
            //     var maxx: f32 = 0;
            //     var miny: f32 = std.math.floatMax(f32);
            //     var maxy: f32 = 0;
            //     for (c.points.items) |p| {
            //         const pos = c.transform.transformPoint(p.pos);
            //         if (minx > pos.x) minx = pos.x;
            //         if (miny > pos.y) miny = pos.y;
            //         if (maxx < pos.x) maxx = pos.x;
            //         if (maxy < pos.y) maxy = pos.y;
            //     }
            //     rect.x = minx;
            //     rect.y = miny;
            //     rect.width = maxx - minx;
            //     rect.height = maxy - miny;
            // },
            // .concave_polygon_fill => |c| {
            //     var minx: f32 = std.math.floatMax(f32);
            //     var maxx: f32 = 0;
            //     var miny: f32 = std.math.floatMax(f32);
            //     var maxy: f32 = 0;
            //     for (c.points.items) |p| {
            //         const pos = c.transform.transformPoint(p);
            //         if (minx > pos.x) minx = pos.x;
            //         if (miny > pos.y) miny = pos.y;
            //         if (maxx < pos.x) maxx = pos.x;
            //         if (maxy < pos.y) maxy = pos.y;
            //     }
            //     rect.x = minx;
            //     rect.y = miny;
            //     rect.width = maxx - minx;
            //     rect.height = maxy - miny;
            // },
            // .polyline => |c| {
            //     var minx: f32 = std.math.floatMax(f32);
            //     var maxx: f32 = 0;
            //     var miny: f32 = std.math.floatMax(f32);
            //     var maxy: f32 = 0;
            //     for (c.points.items) |p| {
            //         const pos = c.transform.transformPoint(p);
            //         if (minx > pos.x) minx = pos.x;
            //         if (miny > pos.y) miny = pos.y;
            //         if (maxx < pos.x) maxx = pos.x;
            //         if (maxy < pos.y) maxy = pos.y;
            //     }
            //     rect.x = minx;
            //     rect.y = miny;
            //     rect.width = maxx - minx;
            //     rect.height = maxy - miny;
            // },
            else => {
                rect.x = 0;
                rect.y = 0;
                rect.width = 1;
                rect.height = 1;
            },
        }
        return rect;
    }
};
