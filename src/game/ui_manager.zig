const std = @import("std");
const ig = @import("cimgui");
const Components = @import("ecs/components/components.zig");
const DbManager = @import("db_manager.zig");
const Ecs = @import("ecs/ecs.zig");
const EcsManager = @import("ecs_manager.zig");
const MarketManager = @import("market_manager.zig");
const UiSystem = @import("ecs/systems/ui_system.zig");
const UiManager = @This();

var IMGUI_HAS_DOCK = false;

allocator: std.mem.Allocator,
db_manager: *DbManager,

ui_system: *UiSystem,
io: *ig.ImGuiIO,

ig_ctx: *ig.ImGuiContext = undefined,
implot_ctx: *ig.struct_ImPlotContext = undefined,

is_in_draw_frame: bool = false,

pub const settings_file_path = "config/cimgui.ini";
// pub const font_path = "assets/fonts/SNPro-Regular.ttf";
pub const fonts: [2][]const u8 = .{
    "assets/fonts/SNPro/SNPro-Regular.ttf",
    "assets/fonts/ferrum.otf",
};
pub const font_size: f32 = 18;

pub fn init(allocator: std.mem.Allocator, db_manager: *DbManager, ui_system: *UiSystem) UiManager {
    // Setup Dear ImGui context
    const ig_ctx = ig.igCreateContext(null);
    const implot_ctx = ig.ImPlot_CreateContext();

    return .{
        .allocator = allocator,
        .db_manager = db_manager,
        // .cimgui_render_system = cimgui_render_system,
        .ui_system = ui_system,
        .io = ig.igGetIO_Nil(),
        .ig_ctx = ig_ctx.?,
        .implot_ctx = implot_ctx,
    };
}

pub fn deinit(self: *UiManager) void {
    // _ = self;
    // self.ui_system.deinit();
    ig.ImPlot_DestroyContext(self.implot_ctx);
    ig.igDestroyContext(self.ig_ctx);
}

pub fn setup(self: *UiManager, ecs_manager: *EcsManager) !void {
    // _ = &self;

    // self.io = ig.igGetIO_Nil();
    self.io.*.ConfigFlags |= ig.ImGuiConfigFlags_NavEnableKeyboard; // Enable Keyboard Controls
    self.io.*.ConfigFlags |= ig.ImGuiConfigFlags_NavEnableGamepad; // Enable Gamepad Controls
    // Setup doncking feature --- can't compile well at this moment.
    if (IMGUI_HAS_DOCK) {
        self.io.*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable; // Enable Docking
        self.io.*.ConfigFlags |= ig.ImGuiConfigFlags_ViewportsEnable; // Enable Multi-Viewport / Platform Windows
    }

    ecs_manager.create_single_component_entity(Ecs.components.UIState, .{});
    ecs_manager.flush_cmd_buf();

    // Setup Dear ImGui context
    const ig_ctx = ig.igCreateContext(null);
    if (ig_ctx == null) {
        return error.ImGuiCreateContextFailure;
    }
    self.ig_ctx = ig_ctx.?;
    self.implot_ctx = ig.ImPlot_CreateContext();

    ensureSettingFileExist(settings_file_path);

    // Change Font
    const io: *ig.ImGuiIO = ig.igGetIO_Nil();
    for (&fonts) |*font| {
        _ = ig.ImFontAtlas_AddFontFromFileTTF(io.Fonts, font.ptr, font_size, null, null);
    }
}

pub fn begin_frame(self: *UiManager, ui_state: *Ecs.components.UIState) void {
    if (self.is_in_draw_frame) {
        Ecs.logger.err("[UiManager][begin_frame] Calling begin_frame but you forgot to render the previous frame, you need to call render_frame first", .{});
        return;
    }
    self.is_in_draw_frame = true;
    start_cimgui_pass(ui_state);
}

pub fn render_frame(self: *UiManager, ecs_manager: *EcsManager) void {
    if (!self.is_in_draw_frame) {
        Ecs.logger.err("[UiManager][render_frame] Calling render_frame but you forgot to call begin_frame first", .{});
        return;
    }

    ecs_manager.entities.forEach("render_ui", render_ui, .{
        .cb = &ecs_manager.cmd_buf,
        .es = &ecs_manager.entities,
        .mm = ecs_manager.market_manager,
    });

    end_cimgui_pass();

    self.is_in_draw_frame = false;
}

pub fn get_draw_data(self: *UiManager) ?*ig.ImDrawData {
    if (self.is_in_draw_frame) {
        Ecs.logger.err("[UiManager][get_draw_data] Calling get_draw_data but you forgot to call render_frame first", .{});
        return null;
    }

    const draw_data: *ig.ImDrawData = ig.igGetDrawData();

    return draw_data;
}

// Update and Render additional Platform Windows
pub fn impl_update_plateform(self: *UiManager) void {
    if (IMGUI_HAS_DOCK) {
        // const pio = ig.igGetIO_Nil();
        if ((self.io.*.ConfigFlags & ig.ImGuiConfigFlags_ViewportsEnable) != 0) {
            ig.igUpdatePlatformWindows();
            ig.igRenderPlatformWindowsDefault(null, null);
        }
    }
}

fn render_ui(ctx: struct { cb: *Ecs.CmdBuf, es: *Ecs.Entities, mm: *MarketManager }, state: *Ecs.components.UIState) void {
    Ecs.logger.info("[UiManager.render_ui]", .{});

    UiSystem.system_update_ui_state(.{ .es = ctx.es }, state);

    // Create Main IG window
    {
        var flags: c_int = 0;
        flags |= ig.ImGuiWindowFlags_NoTitleBar;
        flags |= ig.ImGuiWindowFlags_MenuBar;
        // flags |= ig.ImGuiWindowFlags_NoResize;
        flags |= ig.ImGuiWindowFlags_NoCollapse;
        // flags |= ig.ImGuiWindowFlags_NoMove;

        ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Once, .{ .x = 0, .y = 0 });
        ig.igSetNextWindowSize(.{ .x = @floatFromInt(state.window_width), .y = @floatFromInt(state.window_height) }, ig.ImGuiCond_Once);

        if (ig.igBegin("Price is Power", &state.show_first_window, flags)) {}
    }

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
}

fn start_cimgui_pass(state: *Ecs.components.UIState) void {
    Ecs.logger.info("[UiManager.start_cimgui_pass]", .{});
    // simgui.newFrame(.{
    //     .width = sapp.width(),
    //     .height = sapp.height(),
    //     .delta_time = sapp.frameDuration(),
    //     .dpi_scale = sapp.dpiScale(),
    // });

    // Start the Dear ImGui frame
    ig.igNewFrame();

    ig.igShowDemoWindow(&state.is_demo_open);

    ig.ImPlot_ShowDemoWindow(&state.is_demo_open);
}

fn end_cimgui_pass() void {
    Ecs.logger.info("[UiManager.end_imgui_pass]", .{});

    ig.igEnd(); // Opened in the start frame
    ig.igRender();
}

fn ensureSettingFileExist(path: []const u8) void {
    const cwd = std.fs.cwd();
    _ = cwd.createFile(path, .{ .truncate = false, .exclusive = true }) catch true;
}
