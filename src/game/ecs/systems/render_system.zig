const std = @import("std");
// const zmath = @import("zmath");
const sokol = @import("sokol");
const sg = sokol.gfx;
const zecs = @import("zecs");
// const log = @import("../../debug/log.zig").ecs;
const vec = @import("../../math/vec.zig");
const hex = @import("../../math/hex.zig");
const data = @import("../data.zig");
const game = @import("../../game.zig");
// const Region = @import("../../gfx/camera.zig").Region;
// const Vertex = @import("../../gfx/shader.zig").Vertex;
// const RenderPass = @import("../../gfx/render_pass.zig");
const System = @import("system.zig");
const PI = std.math.pi;
const Vec2 = vec.Vec2;

const f32_max = std.math.floatMax(f32);

// pub fn system() ecs.system_desc_t {
//     var desc: ecs.system_desc_t = .{};
//     desc.callback = callback;
//     return desc;
// }
//
// pub fn callback(it: *ecs.iter_t) callconv(.C) void {
//     if (it.count() > 0) return;
//
//     const uniforms = gfx.UniformBufferObject{
//         .mvp = zmath.transpose(zmath.orthographicLh(game.settings.design_size[0], game.settings.design_size[1], -100, 100)),
//     };
//
//     game.state.batcher.begin(.{
//         .pipeline_handle = game.state.pipeline_bloom,
//         .bind_group_handle = game.state.bind_group_bloom,
//         .output_handle = game.state.bloom_output.view_handle,
//     }) catch unreachable;
//
//     const position = zmath.f32x4(-@as(f32, @floatFromInt(game.state.bloom_output.image.width)) / 2, -@as(f32, @floatFromInt(game.state.bloom_output.image.height)) / 2, 0, 0);
//
//     game.state.batcher.texture(position, &game.state.bloom_output, .{}) catch unreachable;
//
//     game.state.batcher.end(uniforms, game.state.uniform_buffer_default) catch unreachable;
// }

// pub const RenderSystem = struct {
//     const Self = @This();
//
//     camera: *data.PerspectiveCamera = undefined,
//
//     pub fn create() RenderSystem {
//         return .{};
//     }
//
//     pub fn system(self: *RenderSystem) System {
//         return .{
//             .ptr = self,
//             .vtable = &.{
//                 // .onSetup = onSetup,
//                 // .onFrame = onFrame,
//                 // .onRender = onRender,
//             },
//         };
//     }
//
//     fn onSetup(ctx: *anyopaque, reg: *zecs.Registry) void {
//         const self: *RenderSystem = @ptrCast(@alignCast(ctx));
//         _ = reg;
//         _ = self;
//     }
//     fn onRender(ctx: *anyopaque, reg: *zecs.Registry, previous_pass: *RenderPass) *RenderPass {
//         const self: *RenderSystem = @ptrCast(@alignCast(ctx));
//
//         _ = &reg;
//         _ = &self;
//         return previous_pass;
//
//         // const i = reg.singletons().getConst(data.EnvironmentInfo);
//         // var col = sg.Color{ .a = 1 };
//         // col.r = @abs(@cos(@as(f32, @floatCast(i.world_time))));
//         // col.g = @abs(@sin(@as(f32, @floatCast(i.world_time))));
//         // col.b = @abs(@tan(@as(f32, @floatCast(i.world_time))));
//         //
//         // const width = i.window_width;
//         // const height = i.window_height;
//         //
//         // for (game.gfx.passes) |pass| {
//         //     // pass.draw(pass);
//         //     if (game.gfx.begin(width, height)) {} else |err| {
//         //         std.log.err("[DELIL]Can't draw DELIL frame: {}", .{err});
//         //     }
//         //
//         //     // // Set frame buffer drawing region to (0,0,width,height).
//         //     if (game.gfx.setViewport(.{ .x = 0, .y = 0, .w = width, .h = height })) {} else |err| {
//         //         std.log.err("[DELIL]Can't draw DELIL hexagon: {}", .{err});
//         //     }
//         //     // // Set drawing coordinate space to (left=-ratio, right=ratio, top=1, bottom=-1).
//         //     // gfx2.state.projection(-ratio, ratio, 1.0, -1.0);
//         //     game.gfx.set_color(col);
//         //     // gfx2.drawHexagon(.{ .x = 0, .y = 0 }) catch unreachable;
//         //
//         //     sg.beginPass(pass.pass);
//         //     // sg.beginPass(.{ .swapchain = sglue.swapchain() });
//         //     if (game.gfx.flush()) {} else |err| {
//         //         std.log.err("[GAME]Can't flush DELIL: {}", .{err});
//         //     }
//         //
//         //     if (game.gfx.end()) {} else |err| {
//         //         std.log.err("[GAME]Can't end DELIL: {}", .{err});
//         //     }
//         //
//         //     sg.endPass();
//         // }
//     }
//
//     fn onFrame(ctx: *anyopaque, reg: *zecs.Registry) void {
//         const self: *RenderSystem = @ptrCast(@alignCast(ctx));
//         _ = reg;
//         _ = self;
//
//         // self.updatePrimaryCamera(reg);
//         // self.renderGraph(reg);
//     }
//
//     fn updatePrimaryCamera(self: *Self, reg: *zecs.Registry) void {
//         var view = reg.view(.{ data.Camera, data.PerspectiveCamera }, .{});
//         var it = view.entityIterator();
//         while (it.next()) |entity| {
//             const cameraConfig = view.getConst(data.Camera, entity);
//             const camera = view.get(data.PerspectiveCamera, entity);
//             // _ = &camera;
//             if (!cameraConfig.primary) {
//                 continue;
//             }
//
//             self.camera = camera;
//             log.debug("[ECS.System][DEBUG] Camera Found {}", .{camera});
//         }
//     }
//
//     fn renderGraph(self: *Self, reg: *zecs.Registry) void {
//         _ = &reg;
//         log.debug("[ECS.System][DEBUG] Hello from zecs System ", .{});
//
//         var viewOb = reg.view(.{data.GameObject}, .{});
//         var iter = viewOb.entityIterator();
//
//         const i = reg.singletons().getConst(data.EnvironmentInfo);
//         log.debug("[ECS.System][DEBUG] World time {}", .{i.world_time});
//
//         // const mvp = gfx.camera.mvp; // copy to stack for more efficiency
//         // var region: Region = .{ .x1 = f32_max, .y1 = f32_max, .x2 = -f32_max, .y2 = -f32_max };
//         // Check if camera.type == gfx.camera.type
//         while (iter.next()) |e| {
//             const object = viewOb.getConst(e);
//             // object.hexagon.
//             log.debug("Shape to draw {}", .{object});
//
//             // for (object.hexagon.vertices, 0..) |v, i| {
//             //     const p = vec.Mat4.mulV(.{
//             //         .x = v.x,
//             //         .y = v.y,
//             //         .z = v.z,
//             //         .a = 1,
//             //     }, mvp);
//             //
//             //     region.x1 = @min(region.x1, p.x - gfx.render_data.thickness);
//             //     region.y1 = @min(region.y1, p.y - gfx.render_data.thickness);
//             //     region.x2 = @max(region.x2, p.x + gfx.render_data.thickness);
//             //     region.y2 = @max(region.y2, p.y + gfx.render_data.thickness);
//             //
//             //     // const vv = gfx.Vertex{ .pos = p, .textcoord = .{ .x = 0, .y = 0 }, .color = color };
//             //     const vertex = Vertex{ .position = p, .color = object.hexagon.vertex_colors[i] };
//             //
//             //     if (gfx.pools.vertice.append(vertex)) {} else |err| {
//             //         log.debug("Can't render scene, vertex queue bug {}", .{err});
//             //     }
//             // }
//             //
//             // const pip = gfx.pipelines.get(.main, .TRIANGLES, .BLENDMODE_NONE);
//             // if (gfx.queue_draw(pip.*, region, object.hexagon.vertices.len, .TRIANGLES)) {} else |err| {
//             //     log.debug("Can't queue_draw in system render {}", .{err});
//             // }
//
//             // if (cgfx.drawHexagon(v2)) {} else |err| {
//             //
//             // }
//
//             log.debug("[ECS.System][DEBUG] POS {}, {}", .{ object.pos.x, object.pos.y });
//             self.drawHexagon(.{ .x = object.pos.x, .y = object.pos.y }) catch unreachable;
//
//             // if (object.hexagon) |h| {
//             //
//             // }
//             // switch (object) {
//             //
//             // }
//         }
//     }
//
//     pub fn drawTriangles(self: *Self, hw: f32, hh: f32, w: f32) !void {
//         const step: f32 = (2.0 * PI) / 6.0;
//         var count: u32 = 0;
//         var points_buffer: [4096]Vec2 = undefined;
//
//         var theta: f32 = 0.0;
//         while (theta <= 2.0 * PI + step * 0.5) : (theta += step) {
//             points_buffer[count] = Vec2{ .x = hw + w * @cos(theta), .y = hh - w * @sin(theta) };
//             count += 1;
//
//             if (count % 3 == 1) {
//                 points_buffer[count] = Vec2{ .x = hw, .y = hh };
//                 count += 1;
//             }
//         }
//
//         try self.drawfilledTrianglesStrip(&points_buffer, count);
//     }
//
//     pub fn drawHexagon(self: *Self, centre: Vec2) !void {
//         try self.drawTriangles(centre.x, centre.y, 0.3);
//     }
//
//     pub fn drawfilledTrianglesStrip(self: *Self, points: []Vec2, count: u32) !void {
//         try self.drawSolidPip(sg.PrimitiveType.TRIANGLE_STRIP, points, count);
//     }
//
//     fn drawSolidPip(self: *Self, primitive_type: sg.PrimitiveType, vertices: []vec.Vec2, num_vertices: u32) !void {
//         if (num_vertices == 0) {
//             return;
//         }
//
//         // fill vertices
//         const thickness: f32 = if (primitive_type == sg.PrimitiveType.POINTS or primitive_type == sg.PrimitiveType.LINES or primitive_type == sg.PrimitiveType.LINE_STRIP) game.gfx.render_data.thickness else 0;
//         const color = game.gfx.render_data.color;
//
//         // Culling
//         const mvp = self.camera.mvp; // copy to stack for more efficiency
//         var region: Region = .{ .x1 = f32_max, .y1 = f32_max, .x2 = -f32_max, .y2 = -f32_max };
//         for (0..num_vertices) |i| {
//             // const p = Vec2.multiply_by_mat2x3(vertices[i], &mvp);
//             const p = vec.Mat4.mulV(.{
//                 .x = vertices[i].x,
//                 .y = vertices[i].y,
//                 .z = 0,
//                 .a = 1,
//             }, mvp);
//             region.x1 = @min(region.x1, p.x - thickness);
//             region.y1 = @min(region.y1, p.y - thickness);
//             region.x2 = @max(region.x2, p.x + thickness);
//             region.y2 = @max(region.y2, p.y + thickness);
//
//             const v = Vertex{ .position = p, .color = color };
//
//             try game.gfx.pools.vertice.append(v);
//         }
//         // log.debug("vertices: {any}", .{state.vertices[num_vertices - 1]});
//         // queue draw
//         // const pip = self.getPip(primitive_type, self.state.blend_mode);
//         const pip = game.gfx.pipelines.get(.main, primitive_type, game.gfx.render_data.blend);
//         try game.gfx.queue_draw(pip.*, region, num_vertices, primitive_type);
//     }
// };
//
// pub fn render_scene(tiles: []data.Tile, objects: []data.Shape, cameras: []data.Camera) void {
//     _ = &tiles;
//     log.debug("[ECS.System][DEBUG] Render Scene ", .{});
//
//     // const cameras: [0]cgfx.Camera = .{};
//     for (cameras) |camera| {
//         log.debug("[ECS.System][DEBUG] Camera Found {}", .{camera});
//         if (!camera.primary) {
//             continue;
//         }
//
//         const mvp = game.gfx.camera.mvp; // copy to stack for more efficiency
//         var region: Region = .{ .x1 = f32_max, .y1 = f32_max, .x2 = -f32_max, .y2 = -f32_max };
//         // Check if camera.type == gfx.camera.type
//         for (objects) |object| {
//             // object.hexagon.
//             log.debug("Shape to draw {}", .{object});
//
//             for (object.hexagon.vertices, 0..) |v, i| {
//                 const p = vec.Mat4.mulV(.{
//                     .x = v.x,
//                     .y = v.y,
//                     .z = v.z,
//                     .a = 1,
//                 }, mvp);
//
//                 region.x1 = @min(region.x1, p.x - game.gfx.render_data.thickness);
//                 region.y1 = @min(region.y1, p.y - game.gfx.render_data.thickness);
//                 region.x2 = @max(region.x2, p.x + game.gfx.render_data.thickness);
//                 region.y2 = @max(region.y2, p.y + game.gfx.render_data.thickness);
//
//                 // const vv = gfx.Vertex{ .pos = p, .textcoord = .{ .x = 0, .y = 0 }, .color = color };
//                 const vertex = Vertex{ .position = p, .color = object.hexagon.vertex_colors[i] };
//
//                 if (game.gfx.pools.vertice.append(vertex)) {} else |err| {
//                     log.debug("Can't render scene, vertex queue bug {}", .{err});
//                 }
//             }
//
//             const pip = game.gfx.pipelines.get(.main, .TRIANGLES, .BLENDMODE_NONE);
//             if (game.gfx.queue_draw(pip.*, region, object.hexagon.vertices.len, .TRIANGLES)) {} else |err| {
//                 log.debug("Can't queue_draw in system render {}", .{err});
//             }
//
//             // if (cgfx.drawHexagon(v2)) {} else |err| {
//             //
//             // }
//
//             // if (object.hexagon) |h| {
//             //
//             // }
//             // switch (object) {
//             //
//             // }
//         }
//
//         break; // Stop at first primary camera (we should have only 1)
//     }
// }
