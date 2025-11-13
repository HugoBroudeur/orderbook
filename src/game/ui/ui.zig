const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const simgui = sokol.imgui;
const sg = sokol.gfx;
const slog = sokol.log;
const ig = @import("cimgui");
const game = @import("../game.zig");
const data = @import("../ecs/data.zig");

pub const settings_file_path = "config/cimgui.ini";
pub const font_path = "assets/fonts/SNPro-Regular.ttf";
pub const font_size: f32 = 18;

pub fn init() void {
    ensureSettingFileExist();
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

pub fn ensureSettingFileExist() void {
    const cwd = std.fs.cwd();
    _ = cwd.createFile(settings_file_path, .{ .truncate = false, .exclusive = true }) catch true;
}

pub fn shutdown() void {
    simgui.shutdown();
}

pub fn handleEvent(ev: [*c]const sapp.Event) void {
    _ = &ev;
    // _ = simgui.handleEvent(ev.*);

}

pub fn frame(render_texture: sg.Image) void {
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Once);
    var show_demo = true;
    ig.igShowDemoWindow(&show_demo);

    ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
    _ = ig.igBegin("Hello Dear ImGui! Hola", 0, ig.ImGuiWindowFlags_None);
    // _ = ig.igColorEdit3("Background", &state.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);
    ig.igEnd();

    ig.igSetNextWindowPos(.{ .x = 10, .y = 100 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
    if (ig.igBegin("Debugger", 0, ig.ImGuiWindowFlags_None)) {
        // ig.igTextWrapped("Application %.3f ms/frame (%.1f FPS)", 1000.0 / ig.igGetIO().*.Framerate, ig.igGetIO().*.Framerate);
        ig.igTextWrapped("Stats %.3f ms/frame (%.1f FPS)", game.gfx.stats.average_cpu_time, game.gfx.stats.fps);
        ig.igTextWrapped("Backend : %s", slice_to_cstring(@tagName(sg.queryBackend())));
        if (ig.igCollapsingHeader("Inputs", ig.ImGuiTreeNodeFlags_DefaultOpen)) {
            const is = game.ecs.reg.singletons().get(data.InputsState);
            var it = is.keys.iterator();
            while (it.next()) |key| {
                ig.igTextWrapped("Key %s - State %s", slice_to_cstring(@tagName(key.key)), slice_to_cstring(@tagName(key.value.*)));
            }
        }

        if (ig.igCollapsingHeader("Logs", ig.ImGuiTreeNodeFlags_DefaultOpen)) {}
        if (ig.igButton("Save GUI")) {
            ig.igSaveIniSettingsToDisk(settings_file_path);
        }
        if (ig.igButton("Load GUI")) {
            ig.igLoadIniSettingsFromDisk(settings_file_path);
        }
    }
    ig.igEnd();

    if (ig.igBegin("Windowless", 0, ig.ImGuiWindowFlags_NoTitleBar)) {
        ig.igTextWrapped("EDITOR for Gloomy");
        ig.igSeparator();
        ig.igTextWrapped("<INTRODUCTION>");
        if (ig.igCollapsingHeader("Metadata", ig.ImGuiTreeNodeFlags_DefaultOpen)) {}
        if (ig.igCollapsingHeader("Tiles", ig.ImGuiTreeNodeFlags_DefaultOpen)) {}
        if (ig.igCollapsingHeader("Monstres", ig.ImGuiTreeNodeFlags_DefaultOpen)) {}
        if (ig.igCollapsingHeader("Modifiers", ig.ImGuiTreeNodeFlags_DefaultOpen)) {}
        if (ig.igCollapsingHeader("Loot Table", ig.ImGuiTreeNodeFlags_DefaultOpen)) {}
        if (ig.igButton("Save")) {}
        ig.igSameLine();
        ig.igTextWrapped("Save scenario %d", @as(c_int, 0));
    }

    ig.igEnd();

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

    simgui.render();
}

pub fn slice_to_cstring(slice: [:0]const u8) [*c]const u8 {
    return @as([*c]const u8, @ptrCast(slice.ptr));
}

pub fn array_to_cstring(slice: []const u8) [*c]const u8 {
    return @as([*c]const u8, @ptrCast(slice.ptr));
}

pub fn i32_to_cint(num: i32) c_int {
    return @as(c_int, num);
}
