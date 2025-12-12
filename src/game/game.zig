const std = @import("std");
const builtin = @import("builtin");
// const sokol = @import("sokol");
// const sg = sokol.gfx;
// const sglue = sokol.glue;
// const slog = sokol.log;
// const sapp = sokol.app;
// const use_docking = @import("build_options").docking;
// const ig = @import("cimgui");
const ip = @import("implot");
const ig = ip;
const tracy = @import("tracy");
const Config = @import("../config.zig");
const DbManager = @import("db_manager.zig");
// // const Delil = @import("gfx/delil_imgui.zig");
// const Delilv2 = @import("gfx/delil_v2.zig");
// const Delil = @import("gfx/delil.zig");
// const delil_pass = @import("gfx/render_pass.zig");
const Ecs = @import("ecs/ecs.zig");
// const shape = @import("math/shape.zig");
// const logger = @import("debug/log.zig");

const sdl = @import("sdl3");
const impl_sdl3 = @import("impl_sdl3");
const impl_sdlgpu3 = @import("impl_sdlgpu3");
const ifa = @import("fonticon");

// const simgui = sokol.imgui;

const Game = @This();

const WINDOW_WIDTH = 1920;
const WINDOW_HEIGHT = 1060;
const IMGUI_HAS_DOCK = false;

var window: *sdl.SDL_Window = undefined;
var gpu_device: *sdl.SDL_GPUDevice = undefined;

pub const GameError = error{
    ErrorInitialisation,
};

const game_allocator: std.mem.Allocator = undefined;
var ecs: Ecs = undefined;
var db_manager: DbManager = undefined;

const FRAMES_PER_SECOND = 60.0;

// pub var gfx: Delilv2 = undefined;
// pub var pass: delil_pass.RenderPass = undefined;

var timing: Timing = .{
    .tick_acc = 0,
    .tick = 0,
    .fixed_framerate = .{
        .next_update_state = 0.0,
        .tick_frame = false,
    },
};

pub fn init(allocator: std.mem.Allocator, config: Config) !void {
    // _ = allocator;
    // _ = config;
    // tracy.frameMarkStart("Main");

    db_manager = try DbManager.init(allocator, config);

    ecs = Ecs.init(allocator, &db_manager) catch |err| {
        std.log.err("[ERROR][game.init] Can't initiate : {}", .{err});
        shutdown();
        return;
    };

    // return .{
    //     .allocator = allocator,
    //     .ecs = ecs,
    // };
}

// delil: delil.Context = undefined,
pub fn setup() !void {
    errdefer shutdown();
    // self.delil = delil.state;

    // sg.setup(.{
    //     .environment = sglue.environment(),
    //     .logger = .{ .func = slog.func },
    // });
    // sokol.time.setup();

    //-------------
    // For print()
    //-------------
    // Setup SDL
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_GAMEPAD) == false) {
        std.debug.print("Error: {s}\n", .{sdl.SDL_GetError()});
        return error.SDL_init;
    }

    const window_flags = sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_HIDDEN | sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY;
    const main_scale = sdl.SDL_GetDisplayContentScale(@intCast(sdl.SDL_GetPrimaryDisplay()));
    if (sdl.SDL_CreateWindow("SDL3GPU example", @intFromFloat(WINDOW_WIDTH * main_scale), @intFromFloat(WINDOW_HEIGHT * main_scale), window_flags)) |pointer| {
        window = pointer;
    } else {
        std.debug.print("Error: SDL_CreateWindow(): {s}\n", .{sdl.SDL_GetError()});
        return error.SDL_CreatWindow;
    }
    // Create GPU Device
    const flags_gpu = sdl.SDL_GPU_SHADERFORMAT_SPIRV + sdl.SDL_GPU_SHADERFORMAT_DXIL + sdl.SDL_GPU_SHADERFORMAT_METALLIB;
    if (sdl.SDL_CreateGPUDevice(flags_gpu, true, null)) |device| {
        gpu_device = device;
    } else {
        std.debug.print("Error: SDL_CreateGPUDevice(): {s}\n", .{sdl.SDL_GetError()});
        return error.SDL_CreateGPUDevice;
    }

    // Claim window for GPU Device
    if (!sdl.SDL_ClaimWindowForGPUDevice(gpu_device, window)) {
        std.debug.print("Error: SDL_ClaimWindowForGPUDevice(): {s}\n", .{sdl.SDL_GetError()});
        return error.SDL_ClaimWindowForGPUDevice;
    }
    _ = sdl.SDL_SetGPUSwapchainParameters(gpu_device, window, sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, sdl.SDL_GPU_PRESENTMODE_VSYNC);
    //const renderer = sdl.SDL_CreateRenderer(window, null); // TODO for Image load ?

    _ = sdl.SDL_SetWindowPosition(window, sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED);

    // Load ECS
    ecs.build_world() catch |err| {
        std.log.info("[ERROR][game.init] Can't build the world : {}", .{err});
        return;
    };
}

pub fn run() void {
    setup() catch |err| {
        std.log.err("Error during Game Setup: {}", .{err});
        return;
    };

    var done = false;
    var showDemoWindow = true;
    var showAnotherWindow = true;
    var sTextInuputBuf = [_:0]u8{0} ** 200;
    var showWindowDelay: i32 = 2; // TODO: Avoid flickering of window at startup.
    var fval: f32 = 0;
    var counter: i32 = 0;
    var clearColor = [_]f32{ 0.25, 0.55, 0.9, 1.0 };

    // Setup Dear ImGui context
    _ = ip.igCreateContext(null);
    if (ip.igCreateContext(null) == null) {
        // return error.ImGuiCreateContextFailure;
    }

    // Setup Platform/Renderer backends
    _ = impl_sdl3.ImGui_ImplSDL3_InitForSDLGPU(@ptrCast(window));
    var init_info: impl_sdlgpu3.ImGui_ImplSDLGPU3_InitInfo = undefined; //= {};
    init_info.Device = @ptrCast(gpu_device);
    init_info.ColorTargetFormat = sdl.SDL_GetGPUSwapchainTextureFormat(gpu_device, window);
    init_info.MSAASamples = sdl.SDL_GPU_SAMPLECOUNT_1;
    _ = impl_sdlgpu3.ImGui_ImplSDLGPU3_Init(&init_info);

    const pio = ig.igGetIO_Nil();
    pio.*.ConfigFlags |= ig.ImGuiConfigFlags_NavEnableKeyboard; // Enable Keyboard Controls
    pio.*.ConfigFlags |= ig.ImGuiConfigFlags_NavEnableGamepad; // Enable Gamepad Controls
    // Setup doncking feature --- can't compile well at this moment.
    if (IMGUI_HAS_DOCK) {
        pio.*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable; // Enable Docking
        pio.*.ConfigFlags |= ig.ImGuiConfigFlags_ViewportsEnable; // Enable Multi-Viewport / Platform Windows
    }

    const implot_ctx = ip.ImPlot_CreateContext();
    defer ip.ImPlot_DestroyContext(implot_ctx);

    while (!done) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event)) {
            _ = impl_sdl3.ImGui_ImplSDL3_ProcessEvent(@ptrCast(&event));
            if (event.type == sdl.SDL_EVENT_QUIT)
                done = true;
            if ((event.type == sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED) and (event.window.windowID == sdl.SDL_GetWindowID(window)))
                done = true;
        }
        // Start the Dear ImGui frame
        impl_sdlgpu3.ImGui_ImplSDLGPU3_NewFrame();
        impl_sdl3.ImGui_ImplSDL3_NewFrame();

        ig.igNewFrame();

        //------------------
        // Show demo window
        //------------------
        if (showDemoWindow) {
            ig.igShowDemoWindow(&showDemoWindow);
            ip.ImPlot_ShowDemoWindow(&showDemoWindow);
        }

        //------------------
        // Show main window
        //------------------
        {
            _ = ig.igBegin(ifa.ICON_FA_THUMBS_UP ++ " Dear ImGui in Zig: SDLGPU3 ", null, 0);
            defer ig.igEnd();
            ig.igText("%s", " SDL3 v");
            ig.igText("%s", ifa.ICON_FA_COMMENT ++ " SDL3 v");
            ig.igSameLine(0, -1.0);
            ig.igText("[%d],[%s]", sdl.SDL_GetVersion(), sdl.SDL_GetRevision());
            ig.igText("%s", ifa.ICON_FA_CIRCLE_INFO ++ " Dear ImGui v");
            // ig.igText("%s", ifa.ICON_FA_CIRCLE_INFO ++ " Dear ImGui v");
            ig.igSameLine(0, -1.0);
            ig.igText("%s", ig.igGetVersion());
            ig.igText("%s", ifa.ICON_FA_CIRCLE_INFO ++ " Zig v");
            ig.igSameLine(0, -1.0);
            ig.igText("%s", builtin.zig_version_string);

            ig.igSpacing();
            _ = ig.igInputTextWithHint("InputText", "Input text here", &sTextInuputBuf, sTextInuputBuf.len, 0, null, null);
            ig.igText("%s", "Input result:");
            ig.igSameLine(0, -1.0);
            ig.igText("%s", &sTextInuputBuf);

            ig.igSpacing();
            _ = ig.igCheckbox("Demo Window", &showDemoWindow);
            _ = ig.igCheckbox("Another Window", &showAnotherWindow);

            _ = ig.igSliderFloat("Float", &fval, 0.0, 1.0, "%.3f", 0);
            _ = ig.igColorEdit3("Clear color", &clearColor, 0);

            if (ig.igButton("Button", .{ .x = 0, .y = 0 })) counter += 1;
            ig.igSameLine(0, -1.0);
            ig.igText("Counter = %d", counter);
            ig.igText("Application average %.3f ms/frame (%.1f FPS)", 1000.0 / pio.*.Framerate, pio.*.Framerate);
            // Show icon fonts
            ig.igSeparatorText(ifa.ICON_FA_WRENCH ++ " Icon font test ");
            ig.igText("%s", ifa.ICON_FA_TRASH_CAN ++ " Trash");

            ig.igSpacing();
            ig.igText("%s", ifa.ICON_FA_MAGNIFYING_GLASS_PLUS ++ " " ++ ifa.ICON_FA_POWER_OFF ++ " " ++ ifa.ICON_FA_MICROPHONE ++ " " ++ ifa.ICON_FA_MICROCHIP ++ " " ++ ifa.ICON_FA_VOLUME_HIGH ++ " " ++ ifa.ICON_FA_SCISSORS ++ " " ++ ifa.ICON_FA_SCREWDRIVER_WRENCH ++ " " ++ ifa.ICON_FA_BLOG);
        } // end main window

        //---------------------
        // Show another window
        //---------------------
        if (showAnotherWindow) {
            _ = ig.igBegin("Another Window", &showAnotherWindow, 0);
            defer ig.igEnd();
            ig.igText("%s", "Hello from another window!");
            if (ig.igButton("Close Me", .{ .x = 0.0, .y = 0.0 })) showAnotherWindow = false;
        }

        //-----------
        // Rendering
        //-----------
        ig.igRender();
        const draw_data: *ig.ImDrawData = ig.igGetDrawData();
        var is_minimized: bool = undefined;
        is_minimized = (draw_data.*.DisplaySize.x <= 0.0) or (draw_data.*.DisplaySize.y <= 0.0);

        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(gpu_device); // Acquire a GPU command buffer
        //
        var swapchain_texture: ?*sdl.SDL_GPUTexture = undefined;
        _ = sdl.SDL_AcquireGPUSwapchainTexture(command_buffer, window, @ptrCast(&swapchain_texture), null, null); // Acquire a swapchain texture
        if (swapchain_texture) |swapchain_texture_val| {
            if (!is_minimized) {
                // This is mandatory: call ImGui_ImplSDLGPU3_PrepareDrawData() to upload the vertex/index buffer!
                impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(draw_data), @ptrCast(command_buffer));

                // Setup and start a render pass
                var target_info = std.mem.zeroes(sdl.SDL_GPUColorTargetInfo);
                target_info.texture = swapchain_texture_val;
                target_info.clear_color = sdl.SDL_FColor{ .r = clearColor[0], .g = clearColor[1], .b = clearColor[2], .a = clearColor[3] };
                target_info.load_op = sdl.SDL_GPU_LOADOP_CLEAR;
                target_info.store_op = sdl.SDL_GPU_STOREOP_STORE;
                target_info.mip_level = 0;
                target_info.layer_or_depth_plane = 0;
                target_info.cycle = false;

                const render_pass = sdl.SDL_BeginGPURenderPass(command_buffer, &target_info, 1, null);

                // Render ImGui
                impl_sdlgpu3.ImGui_ImplSDLGPU3_RenderDrawData(@ptrCast(draw_data), @ptrCast(command_buffer), @ptrCast(render_pass), null);

                sdl.SDL_EndGPURenderPass(render_pass);
            }
            // Update and Render additional Platform Windows

            if (IMGUI_HAS_DOCK) {
                if (pio.*.ConfigFlags & ig.ImGuiConfigFlags_ViewportsEnable) {
                    ig.igUpdatePlatformWindows();
                    ig.igRenderPlatformWindowsDefault();
                }
            }
            // Submit the command buffer
            _ = sdl.SDL_SubmitGPUCommandBuffer(command_buffer);
        }

        //
        if (showWindowDelay >= 0) {
            showWindowDelay -= 1;
        }
        if (showWindowDelay == 0) { // Visible main window here at start up
            _ = sdl.SDL_ShowWindow(window);
        }
    }
}

pub fn frame() void {
    // const width = sapp.width();
    // const height = sapp.height();

    // Get current window size.
    // const ratio: f32 = @divExact(@as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)));
    // tracy.frameMark("yo yo");

    if (true) {
        ecs.progress();
        ecs.render();
        // const render_pass = ecs.reg.singletons().get(data.RenderPass);

        // sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
        // ecs.render(&state.pass_action);
        // simgui.render();
        // sg.endPass();
        // sg.commit();
    }
}

pub fn shutdown() void {
    ecs.deinit();
    db_manager.deinit();
    // gfx.deinit();
    // sg.shutdown();
    tracy.cleanExit();

    _ = sdl.SDL_WaitForGPUIdle(gpu_device);
    // img_load.DestroyTexture(@ptrCast(gpu_device), @ptrCast(pTextureId));
    impl_sdl3.ImGui_ImplSDL3_Shutdown();
    impl_sdlgpu3.ImGui_ImplSDLGPU3_Shutdown();
    // ip.ImPlot_DestroyContext(null);
    ig.igDestroyContext(null);

    sdl.SDL_ReleaseWindowFromGPUDevice(gpu_device, window);
    sdl.SDL_DestroyGPUDevice(gpu_device);
    sdl.SDL_DestroyWindow(window);
    sdl.SDL_Quit();
}

// pub fn handleEvent(ev: [*c]const sapp.Event) void {
//     // var e = ev.*;
//
//     ecs.collect(ev.*);
//     // ecs.collectSokolEvent(e) catch unreachable; // TODO: improve, can fail memory allocation
//     //
//     // ecs.consumeEvent();
//     if (ev.*.type == .KEY_DOWN) {
//         switch (ev.*.key_code) {
//             .ESCAPE => sapp.quit(),
//             // .D => logger.toggle(),
//             // .W => logger.toggleEcs(),
//             else => {},
//         }
//     }
//
//     _ = simgui.handleEvent(ev.*);
// }

const Timing = struct {
    tick_acc: u32 = 0,
    tick: u32 = 0,
    fixed_framerate: FixedFramerate,
};

const FixedFramerate = struct {
    const This = @This();
    next_update_state: f64 = 0.0,
    tick_frame: bool = false,

    pub fn shouldTick(self: *This, time: f64) bool {
        if (time > self.timing.next_update_state) {
            self.timing.next_update_state = time + (1.0 / FRAMES_PER_SECOND);
            self.timing.tick_frame = true;
            return true;
        } else {
            self.timing.tick_frame = false;
            return false;
        }
    }
};

// pub fn timef() f32 {
//     return @floatCast(sokol.time.sec(sokol.time.now()));
// }

fn makeComboItems(comptime items: anytype) [*c]const u8 {
    comptime var buffer: []const u8 = "";

    inline for (items) |item| {
        buffer = buffer ++ item ++ "\x00";
    }

    buffer = buffer ++ "\x00";
    return buffer.ptr;
}
