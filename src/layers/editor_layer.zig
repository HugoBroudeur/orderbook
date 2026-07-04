const std = @import("std");
const assert = std.debug.assert;
const zgui = @import("zgui");

const Event = @import("../events/event.zig");

const ProjectManager = @import("../project/manager.zig");
const Config = @import("../config.zig");
const Layer = @import("../core/layer.zig");
const Engine = @import("../engine/vulkan/engine.zig");
const GraphicsContext = @import("../core/graphics_context.zig");
const SceneEditor = @import("../editor/scene_editor.zig");
const EcsExplorer = @import("../editor/ecs_explorer.zig");
const World = @import("../ecs/world.zig");

const EditorLayer = @This();

allocator: std.mem.Allocator,
io: std.Io,
label: []const u8 = "Editor Layer",
config: Config,
world: *World,
project_manager: *ProjectManager,

scene_editor: SceneEditor = undefined,
ecs_explorer: EcsExplorer = undefined,

pub fn init(allocator: std.mem.Allocator, io: std.Io, config: Config, project_manager: *ProjectManager, world: *World) EditorLayer {
    return .{
        .allocator = allocator,
        .config = config,
        .io = io,
        .project_manager = project_manager,
        .world = world,
    };
}

pub fn deinit(self: *EditorLayer) void {
    self.scene_editor.deinit();
    self.ecs_explorer.deinit();
}

pub fn interface(self: *EditorLayer) Layer {
    return Layer.init(self);
}

pub fn getLabel(self: *EditorLayer) []const u8 {
    return self.label;
}

pub fn onAttach(self: *EditorLayer) !void {
    // Creates the ImGui context. The Vulkan/SDL backends are initialized later
    // by RenderLayer.onAttach (it needs the engine), and RenderLayer.deinit
    // tears both down — do not call zgui.deinit here.
    zgui.init(self.allocator);

    self.scene_editor = SceneEditor.init(self.allocator, self.project_manager, self.world.app);
    self.ecs_explorer = EcsExplorer.init(self.world.app);

    const setting_path = try std.mem.concatWithSentinel(self.allocator, u8, &.{
        self.project_manager.project_folder,
        "/",
        "zgui.ini",
    }, 0);

    const fonts: []const [:0]const u8 = &.{
        "assets/fonts/SNPro/SNPro-Regular.ttf",
        "assets/fonts/ferrum.otf",
    };
    const font_size: f32 = 18;

    zgui.io.setConfigFlags(.{ .dock_enable = true });
    zgui.io.setIniFilename(setting_path);

    for (fonts) |font| {
        _ = zgui.io.addFontFromFile(font, font_size);
    }
}

pub fn onUpdate(self: *EditorLayer) void {
    if (self.world.app.getResource(World.Components.WindowState) catch null) |window_state| {
        zgui.backend.newFrame(@intCast(window_state.width), @intCast(window_state.height));

        const viewport = zgui.getMainViewport();
        _ = zgui.dockSpaceOverViewport(0, viewport, .{ .passthru_central_node = true }); // Enable docking on window edge

        var show_demo: bool = true;
        zgui.showDemoWindow(&show_demo);

        self.scene_editor.display();
        self.ecs_explorer.display();

        zgui.endFrame();
    }
}

pub fn onEvent(self: *EditorLayer, ev: Event) bool {
    _ = self;

    _ = zgui.backend.processEvent(@ptrCast(&ev.ptr.toSdl()));

    // Only block propagation when ImGui actually owns the input.
    return switch (ev.ptr) {
        .mouse_button_down,
        .mouse_button_up,
        .mouse_motion,
        .mouse_wheel,
        => zgui.io.getWantCaptureMouse(),

        .key_down,
        .key_up,
        .text_input,
        => zgui.io.getWantCaptureKeyboard(),

        else => false,
    };
}
