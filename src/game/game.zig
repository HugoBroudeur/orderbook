const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sglue = sokol.glue;
const slog = sokol.log;
const sapp = sokol.app;
// const use_docking = @import("build_options").docking;
const ig = @import("cimgui");
// // const Delil = @import("gfx/delil_imgui.zig");
// const Delilv2 = @import("gfx/delil_v2.zig");
// const Delil = @import("gfx/delil.zig");
// const delil_pass = @import("gfx/render_pass.zig");
const ui = @import("ui/ui.zig");
const Ecs = @import("ecs/ecs.zig");
// const shape = @import("math/shape.zig");
// const logger = @import("debug/log.zig");

const simgui = sokol.imgui;

const Game = @This();

const game_allocator: std.mem.Allocator = undefined;
var ecs: Ecs = undefined;

const state = struct {
    var pass_action: sg.PassAction = .{};
    var show_first_window: bool = true;
    var show_second_window: bool = true;
};

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

pub fn init(allocator: std.mem.Allocator) void {
    ecs = Ecs.init(allocator) catch |err| {
        std.log.err("Can't initiate Delil: {}", .{err});
        shutdown();
    };

    // return .{
    //     .allocator = allocator,
    //     .ecs = ecs,
    // };
}

// delil: delil.Context = undefined,
pub fn setup() void {
    errdefer shutdown();
    // self.delil = delil.state;

    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    sokol.time.setup();

    simgui.setup(.{
        .logger = .{ .func = slog.func },
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    };

    // if (gfx.init()) {} else |err| {
    //     std.log.err("Can't initiate Delil: {}", .{err});
    //     shutdown();
    //     return;
    // }

    // ui.init();
}

pub fn frame() void {
    // const width = sapp.width();
    // const height = sapp.height();

    var col = sg.Color{ .a = 1 };
    col.r = @abs(@cos(timef()));
    col.g = @abs(@sin(timef()));
    col.b = @abs(@tan(timef()));

    // Get current window size.
    // const ratio: f32 = @divExact(@as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)));

    // delil.state.begin(width, height) catch ;
    if (true) {
        ecs.progress();

        // call simgui.newFrame() before any ImGui calls
        simgui.newFrame(.{
            .width = sapp.width(),
            .height = sapp.height(),
            .delta_time = sapp.frameDuration(),
            .dpi_scale = sapp.dpiScale(),
        });

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

        //=== UI CODE STARTS HERE
        ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
        ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
        if (ig.igBegin("Hello Dear ImGui!", &state.show_first_window, ig.ImGuiWindowFlags_None)) {
            _ = ig.igColorEdit3("Background", &state.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);
            _ = ig.igText("Dear ImGui Version: %s", ig.IMGUI_VERSION);
        }
        ig.igEnd();

        ig.igSetNextWindowPos(.{ .x = 50, .y = 120 }, ig.ImGuiCond_Once);
        ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
        if (ig.igBegin("Another Window", &state.show_second_window, ig.ImGuiWindowFlags_None)) {
            _ = ig.igText("Sokol Backend: %s", backendName);
        }
        ig.igEnd();
        //=== UI CODE ENDS HERE

        // call simgui.render() inside a sokol-gfx pass
        sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
        // ecs.render(&state.pass_action);
        simgui.render();
        sg.endPass();
        sg.commit();

        // for (&gfx.passes) |*pass| {
        //     ecs.render(pass);
        //     // pass.draw(pass);
        //     if (gfx.begin(width, height)) {} else |err| {
        //         std.log.err("[DELIL]Can't draw DELIL frame: {}", .{err});
        //     }
        //
        //     // // Set frame buffer drawing region to (0,0,width,height).
        //     if (gfx.setViewport(.{ .x = 0, .y = 0, .w = width, .h = height })) {} else |err| {
        //         std.log.err("[DELIL]Can't draw DELIL hexagon: {}", .{err});
        //     }
        //     // // Set drawing coordinate space to (left=-ratio, right=ratio, top=1, bottom=-1).
        //     // gfx2.state.projection(-ratio, ratio, 1.0, -1.0);
        //     gfx.set_color(col);
        //     // gfx2.drawHexagon(.{ .x = 0, .y = 0 }) catch unreachable;
        //
        //     sg.beginPass(pass.pass);
        //     // sg.beginPass(.{ .swapchain = sglue.swapchain() });
        //     if (gfx.flush()) {} else |err| {
        //         std.log.err("[GAME]Can't flush DELIL: {}", .{err});
        //     }
        //
        //     if (gfx.end()) {} else |err| {
        //         std.log.err("[GAME]Can't end DELIL: {}", .{err});
        //     }
        //
        //     sg.endPass();
        //
        //     // sg.beginPass(.{ .swapchain = sglue.swapchain() });
        //     // ui.frame(pass.render_texture);
        //     // sg.endPass();
        // }
        // gfx.render(ecs.render_systems);
    }

    { // Render UI
    }
    sg.commit();
}

pub fn shutdown() void {
    ecs.deinit();
    // gfx.deinit();
    ui.shutdown();
    sg.shutdown();
}

pub fn handleEvent(ev: [*c]const sapp.Event) void {
    // var e = ev.*;

    // ecs.collect(ev.*);
    // ecs.collectSokolEvent(e) catch unreachable; // TODO: improve, can fail memory allocation
    //
    // ecs.consumeEvent();
    // if (ev.*.type == .KEY_DOWN) {
    //     switch (ev.*.key_code) {
    //         // .ESCAPE => sapp.quit(),
    //         .D => logger.toggle(),
    //         .W => logger.toggleEcs(),
    //         else => {},
    //     }
    // }

    ui.handleEvent(ev);
}

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

pub fn timef() f32 {
    return @floatCast(sokol.time.sec(sokol.time.now()));
}
