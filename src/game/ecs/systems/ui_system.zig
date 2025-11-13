const std = @import("std");

const zecs = @import("zecs");
const data = @import("../data.zig");
// const log = @import("../../debug/log.zig").ecs;
const System = @import("system.zig");
const ig = @import("cimgui");
const utils = @import("../utils.zig");
const game = @import("../../game.zig");
// const delil_pass = @import("../../gfx/render_pass.zig");

const sokol = @import("sokol");
const sapp = sokol.app;
const simgui = sokol.imgui;
const sg = sokol.gfx;
const slog = sokol.log;
const sglue = sokol.glue;

pub const UiSystem = struct {
    const Self = @This();

    pub const settings_file_path = "config/cimgui.ini";
    pub const font_path = "assets/fonts/SNPro-Regular.ttf";
    pub const font_size: f32 = 18;

    // render_pass: delil_pass.RenderPass,

    pub fn create() UiSystem {
        return .{
            // .render_pass = delil_pass.RenderPass.default(),
        };
    }

    pub fn system(self: *UiSystem) System {
        return .{
            .ptr = self,
            .vtable = &.{
                .onSetup = onSetup,
                .onFrame = onFrame,
                .once = once,
            },
        };
    }

    fn onSetup(ctx: *anyopaque, reg: *zecs.Registry) void {
        const self: *UiSystem = @ptrCast(@alignCast(ctx));
        _ = reg;
        _ = &self;

        ensureSettingFileExist(settings_file_path);
        // initialize sokol-imgui
        simgui.setup(.{
            .logger = .{ .func = slog.func },
            .ini_filename = settings_file_path,
            .no_default_font = true,
        });
        // Change Font
        const io: *ig.ImGuiIO = ig.igGetIO();
        _ = ig.ImFontAtlas_AddFontFromFileTTF(io.Fonts, font_path, font_size, null, null);
    }

    fn onRender(ctx: *anyopaque, reg: *zecs.Registry, previous_pass: *sokol.sg.RenderPass) *sokol.sg.RenderPass {
        const self: *UiSystem = @ptrCast(@alignCast(ctx));
        _ = &previous_pass;

        sg.beginPass(.{ .swapchain = sglue.swapchain() });
        // ui.frame(pass.render_texture);

        simgui.newFrame(.{
            .width = sapp.width(),
            .height = sapp.height(),
            .delta_time = sapp.frameDuration(),
            .dpi_scale = sapp.dpiScale(),
        });
        self.renderCameraControlUi(reg);
        self.renderScenario(reg, previous_pass.render_texture);
        simgui.render();

        sg.endPass();

        return previous_pass;
    }

    fn onFrame(ctx: *anyopaque, reg: *zecs.Registry) void {
        const self: *UiSystem = @ptrCast(@alignCast(ctx));
        // const self: *CameraSystem = @ptrCast(@alignCast(ctx));
        _ = &reg;
        _ = &self;
        // _ = &reg;
        // log.debug("[ECS.System][DEBUG] Hello from zecs System ", .{});
        //
        // const i = reg.singletons().getConst(data.EnvironmentInfo);
        // log.debug("[ECS.System][DEBUG] World time {}", .{i.world_time});
        //
        // self.updatePrimaryCamera(reg);
        //
        // // Reset viewport
        // self.camera.resetViewport(i.window_width, i.window_height);
        //
        // //TODO, change that to collect commands? Set viewport
        // self.camera.setViewport(.{ .x = 0, .y = 0, .w = i.window_width, .h = i.window_height });
        // self.handleCameraControl(reg);

    }

    fn once(ctx: *anyopaque, reg: *zecs.Registry) void {
        const self: *UiSystem = @ptrCast(@alignCast(ctx));

        _ = &reg;
        _ = &self;
        // self.handleCoreInputs(reg);
    }

    fn renderCameraControlUi(self: *Self, reg: *zecs.Registry) void {
        _ = &self;
        if (utils.getPrimaryCamera(reg)) |camera| {
            if (ig.igBegin("Camera", 0, ig.ImGuiWindowFlags_None)) {
                ig.igSeparatorText("Position");
                _ = ig.igDragFloat("Position X", &camera.pos.x);
                _ = ig.igDragFloat("Position Y", &camera.pos.y);
                _ = ig.igDragFloat("Position Z", &camera.pos.z);
                ig.igSeparatorText("Look at");
                _ = ig.igDragFloat("Look at X", &camera.look_at.x);
                _ = ig.igDragFloat("Look at Y", &camera.look_at.y);
                _ = ig.igDragFloat("Look at Z", &camera.look_at.z);

                // ig.igTextWrapped("Application %.3f ms/frame (%.1f FPS)", 1000.0 / ig.igGetIO().*.Framerate, ig.igGetIO().*.Framerate);
                // ig.igTextWrapped("Stats %.3f ms/frame (%.1f FPS)", &game.gfx.stats.fps_refresh_time_ns, &game.gfx.stats);
                // ig.igTextWrapped("Backend : %s", slice_to_cstring(game.gfx.camera.direction.x()));

            }
            ig.igEnd();
        }
    }

    fn renderScenario(self: *Self, reg: *zecs.Registry, render_texture: *sg.Image) void {
        _ = &self;
        _ = &reg;

        ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Once);

        if (ig.igBegin("Game", 0, 0)) {
            if (ig.igBeginChild("sokol-gfx", .{
                // .x = @as(f32, @floatFromInt(game.gfx.camera.viewport.w)),
                // .y = @as(f32, @floatFromInt(game.gfx.camera.viewport.h)),
                .x = @as(f32, @floatFromInt(1024)),
                .y = @as(f32, @floatFromInt(800)),
            }, ig.ImGuiWindowFlags_None, ig.ImGuiWindowFlags_None)) {
                // if (ig.igBeginChild("sokol-gfx", .{ .x = 360, .y = 360 }, ig.ImGuiWindowFlags_None, ig.ImGuiWindowFlags_None)) {
                // const draw_list = ig.igGetWindowDrawList();
                // ig.ImDrawList_AddCallback(draw_list, imgui_draw_callback, null);

            }
            const textId = simgui.imtextureid(render_texture);
            ig.igImage(textId, .{
                // .x = @as(f32, @floatFromInt(game.gfx.camera.viewport.w)),
                // .y = @as(f32, @floatFromInt(game.gfx.camera.viewport.h)),
                .x = @as(f32, @floatFromInt(1024)),
                .y = @as(f32, @floatFromInt(800)),
            });
            // ig.igImage(textId, .{ .x = 360, .y = 360 });
            ig.igEndChild();
            ig.igSameLineEx(0, 10);
            // if (igBeginChild("sokol-gl", (ImVec2){360, 360}, true, ImGuiWindowFlags_None)) {
            //     ImDrawList* dl = igGetWindowDrawList();
            //     ImDrawList_AddCallback(dl, draw_scene_2, 0);
            // }
            // igEndChild();
        }
        ig.igEnd();
    }
};

pub fn ensureSettingFileExist(path: []const u8) void {
    const cwd = std.fs.cwd();
    _ = cwd.createFile(path, .{ .truncate = false, .exclusive = true }) catch true;
}
