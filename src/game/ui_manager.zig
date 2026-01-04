const std = @import("std");
const ig = @import("cimgui");
const clay = @import("zclay");
const sdl = @import("sdl3");
// const ttf = @import("sdl_ttf");
const Components = @import("ecs/components/components.zig");
const DbManager = @import("db_manager.zig");
const Ecs = @import("ecs/ecs.zig");
const EcsManager = @import("ecs_manager.zig");
const MarketManager = @import("market_manager.zig");
const FontManager = @import("font_manager.zig");
const ClayManager = @import("clay_manager.zig");
const UiSystem = @import("ecs/systems/ui_system.zig");
const UiManager = @This();

var IMGUI_HAS_DOCK = false;

const light_grey: clay.Color = .{ 224, 215, 210, 255 };
const red: clay.Color = .{ 168, 66, 28, 255 };
const orange: clay.Color = .{ 225, 138, 50, 255 };
const white: clay.Color = .{ 250, 250, 255, 255 };

const sidebar_item_layout: clay.LayoutConfig = .{ .sizing = .{ .w = .grow, .h = .fixed(50) } };

allocator: std.mem.Allocator,
db_manager: *DbManager,
font_manager: *FontManager,

ui_system: *UiSystem,
io: *ig.ImGuiIO,

ig_ctx: *ig.ImGuiContext = undefined,
implot_ctx: *ig.struct_ImPlotContext = undefined,

pub const settings_file_path = "config/cimgui.ini";
// pub const font_path = "assets/fonts/SNPro-Regular.ttf";
pub const fonts: [2][]const u8 = .{
    "assets/fonts/SNPro/SNPro-Regular.ttf",
    "assets/fonts/ferrum.otf",
};
pub const font_size: f32 = 18;

pub fn init(allocator: std.mem.Allocator, db_manager: *DbManager, ui_system: *UiSystem, font_manager: *FontManager) UiManager {
    // Setup Dear ImGui context
    const ig_ctx = ig.igCreateContext(null);
    const implot_ctx = ig.ImPlot_CreateContext();

    return .{
        .allocator = allocator,
        .db_manager = db_manager,
        .font_manager = font_manager,
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
    for (&fonts) |*f| {
        _ = ig.ImFontAtlas_AddFontFromFileTTF(io.Fonts, f.ptr, font_size, null, null);
    }
}

pub fn renderFrame(self: *UiManager, ecs_manager: *EcsManager) void {
    Ecs.logger.info("[UiManager][renderFrame]", .{});

    const state = ecs_manager.get_singleton(Ecs.components.UIState);

    // Start the Dear ImGui frame
    ig.igNewFrame();

    ig.igShowDemoWindow(&state.is_demo_open);

    ig.ImPlot_ShowDemoWindow(&state.is_demo_open);

    // self.render_font();
    const clay_cmds = createLayout();
    ecs_manager.entities.forEach("render_ui", renderUi, .{
        .cb = &ecs_manager.cmd_buf,
        .es = &ecs_manager.entities,
        .mm = ecs_manager.market_manager,
    });

    ig.igEnd(); // Opened in the start frame
    ig.igRender();
    self.impl_update_plateform();

    // Put the pointer to draw data in ECS
    const draw_data = ecs_manager.get_singleton(Ecs.components.Graphics.DrawData);
    draw_data.ui = ig.igGetDrawData();
    draw_data.clay_render_cmds = clay_cmds;

    // ClayManager.renderCommands(renderer_data: *RendererData, cmds: []RenderCommand)

}

// pub fn render_font(self: *UiManager, renderer: *sdl.SDL_Renderer) !void {
//     _ = self;
//     const text = "Hello SDL Font";
//
//     // TODO dont create new surface if unchanged
//     const text_surface: [*c]sdl.SDL_Surface = sdl.TTF_RenderText_Solid(font, @ptrCast(text), text.len, .{ .r = 255, .g = 255, .b = 255, .a = 255 }) orelse {
//         sdl.SDL_Log("Error loading text surface: %s\n", sdl.SDL_GetError());
//         return error.FailedToRenderSurface;
//     };
//     defer sdl.SDL_DestroySurface(text_surface);
//
//     // TODO dont create new texture if unchanged
//     const text_texture = sdl.SDL_CreateTextureFromSurface(renderer, text_surface) orelse {
//         sdl.SDL_Log("Error loading text texture: %s\n", sdl.SDL_GetError());
//         return error.FailedToRenderTexture;
//     };
//     defer sdl.SDL_DestroyTexture(text_texture);
//
//     const w: c_int = @intCast(text_surface.*.w);
//     const h: c_int = @intCast(text_surface.*.h);
//     const srcr = sdl.SDL_Rect{ .x = 0, .y = 0, .w = w, .h = h };
//     const destr = sdl.SDL_Rect{ .x = @intCast(text.offset.x), .y = @intCast(text.offset.y), .w = w, .h = h };
//     _ = sdl.SDL_RenderTexture(renderer, text_texture, &srcr, &destr);
// }

pub fn getDrawData() *ig.ImDrawData {
    return ig.igGetDrawData();
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

fn renderUi(ctx: struct { cb: *Ecs.CmdBuf, es: *Ecs.Entities, mm: *MarketManager }, state: *Ecs.components.UIState) void {
    Ecs.logger.info("[UiManager.render_ui]", .{});

    const cmd = createLayout();
    _ = cmd;

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

fn ensureSettingFileExist(path: []const u8) void {
    const cwd = std.fs.cwd();
    _ = cwd.createFile(path, .{ .truncate = false, .exclusive = true }) catch true;
}

// Re-useable components are just normal functions
fn sidebarItemComponent(index: u32) void {
    clay.UI()(.{
        .id = .IDI("SidebarBlob", index),
        .layout = sidebar_item_layout,
        .background_color = orange,
    })({});
}

// An example function to begin the "root" of your layout tree
// fn createLayout(profile_picture: *const rl.Texture2D) clay.ClayArray(clay.RenderCommand) {
fn createLayout() []clay.RenderCommand {
    clay.beginLayout();
    clay.UI()(.{
        .id = .ID("OuterContainer"),
        .layout = .{ .direction = .left_to_right, .sizing = .grow, .padding = .all(16), .child_gap = 16 },
        .background_color = white,
    })({
        clay.UI()(.{
            .id = .ID("SideBar"),
            .layout = .{
                .direction = .top_to_bottom,
                .sizing = .{ .h = .grow, .w = .fixed(300) },
                .padding = .all(16),
                .child_alignment = .{ .x = .center, .y = .top },
                .child_gap = 16,
            },
            .background_color = light_grey,
        })({
            clay.UI()(.{
                .id = .ID("ProfilePictureOuter"),
                .layout = .{ .sizing = .{ .w = .grow }, .padding = .all(16), .child_alignment = .{ .x = .left, .y = .center }, .child_gap = 16 },
                .background_color = red,
            })({
                clay.UI()(.{
                    .id = .ID("ProfilePicture"),
                    .layout = .{ .sizing = .{ .h = .fixed(60), .w = .fixed(60) } },
                    .background_color = white,
                    // .image = .{ .source_dimensions = .{ .h = 60, .w = 60 }, .image_data = @ptrCast(profile_picture) },
                })({});
                clay.text("Clay - UI Library", .{ .font_size = 24, .color = light_grey });
            });

            for (0..5) |i| sidebarItemComponent(@intCast(i));
        });

        clay.UI()(.{
            .id = .ID("MainContent"),
            .layout = .{ .sizing = .grow },
            .background_color = light_grey,
        })({
            //...
        });
    });
    return clay.endLayout();
}
