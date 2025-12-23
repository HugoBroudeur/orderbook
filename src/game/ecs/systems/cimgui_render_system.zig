const std = @import("std");

const ecs = @import("../ecs.zig");
const RenderSystem = @import("render_system.zig");
const ig = @import("cimgui");

const UiSystem = @import("ui_system.zig");

const CimguiRenderSystem = @This();

pub fn init() CimguiRenderSystem {
    return .{};
}
pub fn deinit(self: *CimguiRenderSystem) void {
    _ = self;
}

pub fn system(self: *CimguiRenderSystem) RenderSystem {
    return RenderSystem.init(self);
}

pub fn setup(self: *CimguiRenderSystem) void {
    _ = &self;
}

pub fn render(self: *CimguiRenderSystem) void {
    _ = &self;
}

pub fn render_ui(ctx: struct { cb: *ecs.CmdBuf, es: *ecs.Entities, mm: *ecs.MarketManager }, state: *ecs.components.UIState) void {
    ecs.logger.info("[CimguiRenderSystem.render_ui]", .{});
    UiSystem.system_update_ui_state(.{ .es = ctx.es }, state);

    start_imgui_pass(state);

    UiSystem.system_menu_bar(state);

    switch (state.current_tab) {
        .HQ => {
            ctx.es.forEach("system_ui_test", UiSystem.system_ui_test, .{});
        },
        .Resources => {
            ctx.es.forEach("system_render_resource_view", UiSystem.system_render_resource_view, .{
                .cb = ctx.cb,
                .es = ctx.es,
            });
        },
        .Market => {
            ctx.es.forEach("system_main_market_view", UiSystem.system_main_market_view, .{
                .cb = ctx.cb,
                .es = ctx.es,
                .mm = ctx.mm,
            });
            ctx.es.forEach("system_market_view", UiSystem.system_market_view, .{
                .cb = ctx.cb,
                .es = ctx.es,
                .state = state,
            });
        },
        else => {},
    }

    end_imgui_pass();
}

pub fn start_imgui_pass(state: *ecs.components.UIState) void {
    ecs.logger.info("[CimguiRenderSystem.start_imgui_pass]", .{});
    // simgui.newFrame(.{
    //     .width = sapp.width(),
    //     .height = sapp.height(),
    //     .delta_time = sapp.frameDuration(),
    //     .dpi_scale = sapp.dpiScale(),
    // });

    // Start the Dear ImGui frame
    ig.igNewFrame();

    var flags: c_int = 0;
    flags |= ig.ImGuiWindowFlags_NoTitleBar;
    flags |= ig.ImGuiWindowFlags_MenuBar;
    // flags |= ig.ImGuiWindowFlags_NoResize;
    flags |= ig.ImGuiWindowFlags_NoCollapse;
    // flags |= ig.ImGuiWindowFlags_NoMove;

    ig.igShowDemoWindow(&state.is_demo_open);

    ig.ImPlot_ShowDemoWindow(&state.is_demo_open);

    ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = @floatFromInt(state.window_width), .y = @floatFromInt(state.window_height) }, ig.ImGuiCond_Once);

    if (ig.igBegin("Price is Power", &state.show_first_window, flags)) {}
}

pub fn end_imgui_pass() void {
    ecs.logger.info("[CimguiRenderSystem.end_imgui_pass]", .{});

    ig.igEnd(); // Opened in the start frame
    ig.igRender();
}
