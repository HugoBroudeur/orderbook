const std = @import("std");

// const zecs = @import("zecs");
const ecs = @import("../ecs.zig");
const RenderSystem = @import("render_system.zig");
const RenderingPipeline = @import("../rendering_pipeline.zig");
const ig = @import("cimgui");

const sokol = @import("sokol");
const sapp = sokol.app;
const simgui = sokol.imgui;
const sg = sokol.gfx;
const slog = sokol.log;
const sglue = sokol.glue;

const UiSystem = @This();

pub const settings_file_path = "config/cimgui.ini";
pub const font_path = "assets/fonts/SNPro-Regular.ttf";
pub const font_size: f32 = 18;

pub var w: *ecs.zflecs.world_t = undefined;

pub fn init() UiSystem {
    return .{};
}
pub fn deinit(self: *UiSystem) void {
    _ = self;
    simgui.shutdown();
}

pub fn system(self: *UiSystem) RenderSystem {
    return RenderSystem.init(self);
}

pub fn setup(self: *UiSystem) void {
    _ = &self;

    ensureSettingFileExist(settings_file_path);
    // initialize sokol-imgui
    simgui.setup(.{
        .logger = .{ .func = slog.func },
        .ini_filename = settings_file_path,
        .no_default_font = true,
    });

    ecs.create_single_component_entity(&ecs.cb, ecs.components.UIState, .{});
    // Change Font
    // const io: *ig.ImGuiIO = ig.igGetIO();
    // _ = ig.ImFontAtlas_AddFontFromFileTTF(io.Fonts, font_path, font_size, null, null);

    // _ = ecs.zflecs.ADD_SYSTEM(w, "start_imgui_pass", RenderingPipeline.BeginImguiPass, start_imgui_pass);

    // _ = ecs.zflecs.ADD_SYSTEM(w, "market-trade-view", RenderingPipeline.RenderImguiPass, render_market_view);
    // _ = ecs.zflecs.ADD_SYSTEM(w, "render_ui", RenderingPipeline.RenderImguiPass, render_ui);
    // _ = ecs.zflecs.ADD_SYSTEM(w, "render_resource_view", RenderingPipeline.RenderImguiPass, render_resource_view);
    // ecs.make_system(struct { resource: *ecs.components.Resource }, system_render_resource_view);

    // _ = ecs.zflecs.ADD_SYSTEM(w, "end_imgui_pass", RenderingPipeline.EndImguiPass, end_imgui_pass);
}

pub fn render(self: *UiSystem, world: *ecs.zflecs.world_t, pass_action: *sg.PassAction) void {
    _ = &world;
    _ = &self;
    _ = &pass_action;

    // simgui.render();
}

pub fn render_ui(ctx: struct { cb: *ecs.CmdBuf, es: *ecs.Entities }, state: *ecs.components.UIState) void {
    update_ui_state(.{ .es = ctx.es }, state);

    start_imgui_pass(state);

    render_menu_bar(state);

    switch (state.current_tab) {
        .HQ => {
            ctx.es.forEach("render_ui_test", render_ui_test, .{});
        },
        .Resources => {
            ctx.es.forEach("system_render_resource_view", system_render_resource_view, .{
                .cb = ctx.cb,
                .es = ctx.es,
            });
        },
        .Market => {
            ctx.es.forEach("render_market_view", render_main_market_view, .{
                .cb = ctx.cb,
                .es = ctx.es,
            });
        },
        else => {},
    }

    end_imgui_pass();
}

pub fn start_imgui_pass(state: *ecs.components.UIState) void {
    ecs.logger.info("[UiRenderSystem.start_imgui_pass]", .{});
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    var flags: c_int = 0;
    flags |= ig.ImGuiWindowFlags_NoTitleBar;
    flags |= ig.ImGuiWindowFlags_MenuBar;
    // flags |= ig.ImGuiWindowFlags_NoResize;
    flags |= ig.ImGuiWindowFlags_NoCollapse;
    // flags |= ig.ImGuiWindowFlags_NoMove;

    ig.igShowDemoWindow(&state.is_demo_open);

    ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = @floatFromInt(state.window_width), .y = @floatFromInt(state.window_height) }, ig.ImGuiCond_Once);

    if (ig.igBegin("Price is Power", &state.show_first_window, flags)) {}
}

pub fn end_imgui_pass() void {
    ecs.logger.info("[UiRenderSystem.end_imgui_pass]", .{});

    ig.igEnd(); // Opened in the start frame
    simgui.render();
}

fn render_menu_bar(state: *ecs.components.UIState) void {
    ecs.logger.info("[UiRenderSystem.render_menu_bar]", .{});
    if (ig.igBeginMenuBar()) {
        for (std.enums.values(ecs.components.MainMenuTab)) |tab| {
            if (ig.igBeginMenu(@tagName(tab))) {
                state.current_tab = tab;
                ig.igEndMenu();
            }
        }
        ig.igEndMenuBar();
    }
}

pub fn ensureSettingFileExist(path: []const u8) void {
    const cwd = std.fs.cwd();
    _ = cwd.createFile(path, .{ .truncate = false, .exclusive = true }) catch true;
}

pub fn update_ui_state(ctx: struct { es: *ecs.Entities }, state: *ecs.components.UIState) void {
    ecs.logger.info("[UiRenderSystem.system_update_ui_state]", .{});

    var iter = ctx.es.iterator(struct { pass_action: *sg.PassAction });
    while (iter.next(ctx.es)) |i| {
        state.pass_action = i.pass_action;
    }
}

pub fn render_ui_test(ctx: struct {}, state: *ecs.components.UIState) void {
    _ = ctx;
    ecs.logger.info("[UiRenderSystem.render_ui]", .{});
    const io: *ig.ImGuiIO = ig.igGetIO();

    const backendName: [*c]const u8 = switch (sg.queryBackend()) {
        .D3D11 => "Direct3D11",
        .GLCORE => "OpenGL",
        .GLES3 => "OpenGLES3",
        .METAL_IOS => "Metal iOS",
        .METAL_MACOS => "Metal macOS",
        .METAL_SIMULATOR => "Metal Simulator",
        .WGPU => "WebGPU",
        .DUMMY => "Dummy",
    };

    ecs.components.Styles.setStyle(@enumFromInt(state.current_theme));

    //=== UI CODE STARTS HERE
    if (ig.igBegin("Hello Dear ImGui!", &state.show_first_window, ig.ImGuiWindowFlags_None)) {
        _ = ig.igColorEdit3("Background", &state.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);
        _ = ig.igText("Dear ImGui Version: %s", ig.IMGUI_VERSION);
    }
    ig.igEnd();

    ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = @floatFromInt(state.window_width), .y = @floatFromInt(state.window_height) }, ig.ImGuiCond_Once);
    if (ig.igBegin("Price is Power", &state.show_second_window, ig.ImGuiWindowFlags_None)) {
        _ = ig.igText("Sokol Backend: %s", backendName);

        {
            if (ig.igBeginCombo("Theme", state.themes[@min(state.current_theme, state.themes.len - 1)].ptr, ig.ImGuiComboFlags_None)) {
                for (state.themes, 0..) |theme, i| {
                    const is_selected = (state.current_theme == i);
                    if (ig.igSelectable(theme.ptr)) {
                        state.current_theme = i;

                        if (is_selected) {
                            ig.igSetItemDefaultFocus();
                        }
                    }
                }
                ig.igEndCombo();
            }
        }
        {
            state.progress += state.progress_dir * 0.4 * io.DeltaTime;
            if (state.progress >= 1) {
                state.progress = 1;
                state.progress_dir *= -1;
            }
            if (state.progress <= 0) {
                state.progress = 0;
                state.progress_dir *= -1;
            }

            const max = 1234;
            const progress_saturated = @floor(std.math.clamp(state.progress, 0, 1) * max);

            state.progress_bar_overlay = @splat(0);
            const text = std.fmt.bufPrint(
                &state.progress_bar_overlay,
                "{}/{}",
                .{ progress_saturated, max },
            ) catch "Buffer overload";
            // @memcpy(&state.progress_bar_overlay, progress_saturated * 1234 ++ "/" ++ 1234);

            ig.igProgressBar(state.progress, ig.ImVec2{ .x = 0, .y = 0 }, null);
            ig.igProgressBar(state.progress, ig.ImVec2{ .x = 0, .y = 0 }, text.ptr);
        }
        {
            if (ig.igButton("Buy")) {
                state.is_buy_button_clicked = true;
            }
            if (state.is_buy_button_clicked) {
                state.is_buy_button_clicked = false;
                std.log.info("Buy button clicked", .{});
            }
        }
        // if (ImGui::Button("Button"))
        //     clicked++;
        // if (clicked & 1)
        // {
        //     ImGui::SameLine();
        //     ImGui::Text("Thanks for clicking me!");
        // }
        //     }

    }
    ig.igEnd();
}

pub fn render_main_market_view(
    ctx: struct { cb: *ecs.CmdBuf, es: *ecs.Entities },
    state: *ecs.components.UIState,
) void {
    ecs.logger.info("[UiRenderSystem.render_market_main_view]", .{});

    ctx.es.forEach("render_market_view", render_market_view, .{
        .cb = ctx.cb,
        .es = ctx.es,
        .state = state,
    });
}

pub fn render_market_view(ctx: struct { cb: *ecs.CmdBuf, es: *ecs.Entities, state: *ecs.components.UIState }, mt: *ecs.components.MarketTrading, locked: ?*ecs.components.Locked) void {
    ecs.logger.info("[UiRenderSystem.render_market_view]", .{});

    if (locked != null) {
        return;
    }

    // const asset = @tagName(mt.asset);
    _ = ig.igText("Asset: %s", mt.asset.getName().ptr);
    _ = ig.igText("Current size: %i", mt.book.size());

    ig.igPushID(mt.asset.getName().ptr);

    if (ig.igButton("Buy")) {
        std.log.info("Buy button clicked", .{});

        const entity: ecs.Entity = .reserve(ctx.cb);
        _ = entity.add(ctx.cb, ecs.components.Event.PlaceOrderEvent, .{ .quantity = 1, .price = 10, .side = ecs.components.OrderBook.Side.Buy, .asset = mt.asset });
    }

    ig.igPopID();
}

pub fn system_render_resource_view(ctx: struct { cb: *ecs.CmdBuf, es: *ecs.Entities }, state: *ecs.components.UIState) void {
    ecs.logger.info("[UiRenderSystem.system_render_resource_view]", .{});

    // var iter = ctx.unlock_state.resources.iterator();
    var iter = ctx.es.iterator(struct {
        resource: *ecs.components.Resource,
        locked: *ecs.components.Locked,
        // locked: ?*ecs.components.Locked,
    });

    var i: u8 = 0;

    {
        _ = ig.igText("Add Resource");
        if (ig.igBeginCombo("##", state.resource_view_ui.selected_resource_to_add.getName().ptr, ig.ImGuiComboFlags_HeightLargest)) {
            while (iter.next(ctx.es)) |e| : (i += 1) {
                const is_selected = (state.resource_view_ui.selected_resource_to_add_id == i);

                if (ig.igSelectable(e.resource.getName().ptr)) {
                    state.resource_view_ui.selected_resource_to_add_id = i;
                    state.resource_view_ui.selected_resource_to_add = e.resource.type;

                    ecs.logger.print_info("[UiRenderSystem.render_resource_view] {}, {}", .{ is_selected, state.resource_view_ui.selected_resource_to_add });
                    if (is_selected) {
                        ig.igSetItemDefaultFocus();
                    }
                }
            }
            ig.igEndCombo();
        }

        if (ig.igButton("Add Resource")) {
            ecs.create_single_component_entity(ctx.cb, ecs.components.Event.UnlockResourceEvent, .{ .asset = state.resource_view_ui.selected_resource_to_add });
        }
    }
}

// zflecs implementation
// pub fn render_resource_view(it: *ecs.zflecs.iter_t, resources: []ecs.components.Resource) void {
//     ecs.logger.info("[UiRenderSystem.render_resource_view]", .{});
//     const state = ecs.zflecs.singleton_ensure(it.world, ecs.components.UIState);
//     const unlock_state = ecs.zflecs.singleton_ensure(it.world, ecs.components.UnlockState);
//
//     var iter = unlock_state.resources.iterator();
//     var i: u8 = 0;
//
//     ig.igSetNextWindowPos(.{ .x = 150, .y = 300 }, ig.ImGuiCond_Once);
//     ig.igSetNextWindowSize(.{ .x = 400, .y = 500 }, ig.ImGuiCond_Once);
//
//     if (ig.igBegin("Resource", 1, ig.ImGuiWindowFlags_None)) {
//         {
//             _ = ig.igText("Add Resource");
//             // const i = @as(u8, @intFromEnum(state.selected_resource_to_add));
//             if (ig.igBeginCombo("##", &state.resource_view_ui.selected_resource_to_add_id, ig.ImGuiComboFlags_HeightLargest)) {
//                 while (iter.next()) |res| : (i += 1) {
//                     var is_selected = (state.resource_view_ui.selected_resource_to_add_id == i);
//                     if (unlock_state.is_resource_unlocked(res.key)) {
//                         continue;
//                     }
//
//                     if (ig.igSelectableBoolPtr(@tagName(res.key), &is_selected, 0)) {
//                         // if (ig.igSelectable(@tagName(res.key).ptr)) {
//                         state.resource_view_ui.selected_resource_to_add_id = i;
//                         state.resource_view_ui.selected_resource_to_add = res.key;
//
//                         ecs.logger.print_info("[UiRenderSystem.render_resource_view] {}, {}", .{ is_selected, state.resource_view_ui.selected_resource_to_add });
//                         if (is_selected) {
//                             ig.igSetItemDefaultFocus();
//                         }
//                     }
//                 }
//                 ig.igEndCombo();
//             }
//
//             if (ig.igButton("Add Resource")) {
//                 const entity = ecs.zflecs.new_id(it.world);
//                 _ = ecs.zflecs.set(it.world, entity, ecs.components.Event.UnlockResourceEvent, .{ .id = entity, .asset = state.resource_view_ui.selected_resource_to_add });
//                 const e = ecs.zflecs.new_id(it.world);
//                 _ = ecs.zflecs.set(it.world, e, ecs.components.Resource, .{ .asset = state.resource_view_ui.selected_resource_to_add, .qty_owned = 0 });
//             }
//         }
//
//         for (resources) |r| {
//             const asset = @tagName(r.asset);
//             _ = ig.igText("%s: ", asset.ptr);
//             _ = ig.igSameLine();
//             _ = ig.igText("%i / ", r.qty_owned);
//             _ = ig.igSameLine();
//             _ = ig.igText("%i", r.qty_max);
//         }
//         ig.igEnd();
//     }
// }

// zflecs implementation
// pub fn render_market_view(it: *ecs.zflecs.iter_t, market_tradings: []ecs.components.MarketTrading) void {
//     ecs.logger.info("[UiRenderSystem.render_market_view]", .{});
//     const state = ecs.zflecs.singleton_ensure(it.world, ecs.components.UIState);
//     ig.igSetNextWindowPos(.{ .x = 150, .y = 300 }, ig.ImGuiCond_Once);
//     ig.igSetNextWindowSize(.{ .x = @floatFromInt(state.window_width), .y = @floatFromInt(state.window_height) }, ig.ImGuiCond_Once);
//     if (ig.igBegin("QuantEx", &state.show_second_window, ig.ImGuiWindowFlags_None)) {
//         for (market_tradings) |m| {
//             {
//                 ecs.logger.info("[UiRenderSystem.render_market_view] m: {any}", .{m});
//                 const asset = @tagName(m.asset);
//                 _ = ig.igText("Asset: %s", asset.ptr);
//                 _ = ig.igText("Current size: %i", m.book.size());
//
//                 if (ig.igButton("Buy")) {
//                     std.log.info("Buy button clicked", .{});
//
//                     //     const order = Orderbook.
//                     // m.book.addOrder(order: Order)
//                     // f.entity_init(w, .{})
//                     // f.get_id(w, m., component: u64)
//                     const e = ecs.zflecs.new_id(w);
//                     _ = ecs.zflecs.set(w, e, ecs.components.Event.PlaceOrderEvent, .{ .id = e, .quantity = 1, .price = 10, .side = ecs.components.OrderBook.Side.Buy, .asset = m.asset });
//                     // _ = f.set(w, e, data.MarketTrading, m);
//                     // f.
//
//                     // var ev = std.mem.zeroes(f.event_desc_t);
//                     // ev.event = f.id(events.PlaceOrderEvent);
//                     // ev.entity = e;
//                     // ev.param = &.{ .product = data.MetalTypes.aluminium, .quantity = 1, .price = 10, .side = Orderbook.Side.Buy };
//                     // Emit entity event.
//                     // ecs_emit(world, &(ecs_event_desc_t){ .event = ecs_id(Resize), .entity = widget, .param = &(Resize){ 100, 200 } });
//                     // const ev = std.mem.zeroes(f.event_desc_t);
//                     // ev.entity
//                     // f.emit(w, ev);
//                     // f.emit(world: *world_t, desc: *event_desc_t)
//                     // m.book.addOrder(.init(id: u32, order_type: OrderType, side: Side, price: i32, quantity: u32))
//                 }
//             }
//         }
//     }
//     ig.igEnd();
// }

// fn renderScenario(self: *UiSystem, reg: *ecs.zflecs.world_t, render_texture: *sg.Image) void {
//     _ = &self;
//     _ = &reg;
//
//     ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Once);
//
//     if (ig.igBegin("Game", 0, 0)) {
//         if (ig.igBeginChild("sokol-gfx", .{
//             // .x = @as(f32, @floatFromInt(game.gfx.camera.viewport.w)),
//             // .y = @as(f32, @floatFromInt(game.gfx.camera.viewport.h)),
//             .x = @as(f32, @floatFromInt(1024)),
//             .y = @as(f32, @floatFromInt(800)),
//         }, ig.ImGuiWindowFlags_None, ig.ImGuiWindowFlags_None)) {
//             // if (ig.igBeginChild("sokol-gfx", .{ .x = 360, .y = 360 }, ig.ImGuiWindowFlags_None, ig.ImGuiWindowFlags_None)) {
//             // const draw_list = ig.igGetWindowDrawList();
//             // ig.ImDrawList_AddCallback(draw_list, imgui_draw_callback, null);
//
//         }
//         const textId = simgui.imtextureid(render_texture);
//         ig.igImage(textId, .{
//             // .x = @as(f32, @floatFromInt(game.gfx.camera.viewport.w)),
//             // .y = @as(f32, @floatFromInt(game.gfx.camera.viewport.h)),
//             .x = @as(f32, @floatFromInt(1024)),
//             .y = @as(f32, @floatFromInt(800)),
//         });
//         // ig.igImage(textId, .{ .x = 360, .y = 360 });
//         ig.igEndChild();
//         ig.igSameLineEx(0, 10);
//         // if (igBeginChild("sokol-gl", (ImVec2){360, 360}, true, ImGuiWindowFlags_None)) {
//         //     ImDrawList* dl = igGetWindowDrawList();
//         //     ImDrawList_AddCallback(dl, draw_scene_2, 0);
//         // }
//         // igEndChild();
//     }
//     ig.igEnd();
// }
//
