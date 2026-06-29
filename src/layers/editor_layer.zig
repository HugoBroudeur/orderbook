const std = @import("std");
const assert = std.debug.assert;
const zgui = @import("zgui");
const vk = @import("vulkan");

const Event = @import("../events/event.zig");

const Config = @import("../config.zig");
const Layer = @import("../core/layer.zig");
const Engine = @import("../engine/vulkan/engine.zig");
const GraphicsContext = @import("../core/graphics_context.zig");
const SceneEditor = @import("../editor/scene_editor.zig");

const EditorLayer = @This();

allocator: std.mem.Allocator,
io: std.Io,
label: []const u8 = "Editor Layer",
config: Config,
engine: *Engine,

scene_editor: SceneEditor = undefined,

pub fn init(allocator: std.mem.Allocator, io: std.Io, config: Config, engine: *Engine) EditorLayer {
    return .{
        .allocator = allocator,
        .config = config,
        .engine = engine,
        .io = io,
    };
}

pub fn deinit(self: *EditorLayer) void {
    self.engine.ctx.device.deviceWaitIdle() catch {};
    self.engine.gui_render_fn = null;
    zgui.backend.deinit();
    zgui.deinit();
    self.scene_editor.deinit();
}

pub fn interface(self: *EditorLayer) Layer {
    return Layer.init(self);
}

pub fn getLabel(self: *EditorLayer) []const u8 {
    return self.label;
}

fn guiRender(cmd: vk.CommandBuffer) void {
    zgui.backend.render(@ptrFromInt(@intFromEnum(cmd)));
}

pub fn onAttach(self: *EditorLayer) !void {
    self.scene_editor = SceneEditor.init(self.allocator, self.engine);

    const settings_file_path = "config/cimgui.ini";

    const fonts: []const [:0]const u8 = &.{
        "assets/fonts/SNPro/SNPro-Regular.ttf",
        "assets/fonts/ferrum.otf",
    };
    const font_size: f32 = 18;

    zgui.init(self.allocator);
    zgui.io.setIniFilename(settings_file_path);

    for (fonts) |font| {
        _ = zgui.io.addFontFromFile(font, font_size);
    }

    const swapchain = &self.engine.swapchain;
    const image_count: u32 = @intCast(swapchain.frames.len);

    const color_fmt: c_int = @intFromEnum(swapchain.surface_format.format);

    const init_info = zgui.backend.ImGui_ImplVulkan_InitInfo{
        .api_version = self.engine.ctx.api_version.toU32(),
        .instance = @ptrFromInt(@intFromEnum(self.engine.ctx.instance.handle)),
        .physical_device = @ptrFromInt(@intFromEnum(self.engine.ctx.physical_device)),
        .device = @ptrFromInt(@intFromEnum(self.engine.ctx.device.handle)),
        .queue_family = self.engine.ctx.graphics_queue.family,
        .queue = @ptrFromInt(@intFromEnum(self.engine.ctx.graphics_queue.handle)),

        // Let imgui allocate its own descriptor pool for the font texture.
        .descriptor_pool = null,
        .descriptor_pool_size = 8,

        // No render pass — we use VK_KHR_dynamic_rendering.
        .render_pass = null,
        .min_image_count = image_count,
        .image_count = image_count,

        .use_dynamic_rendering = true,
        .pipeline_rendering_create_info = .{
            .s_type = @intFromEnum(vk.StructureType.pipeline_rendering_create_info_khr),
            .color_attachment_count = 1,
            .p_color_attachment_formats = @ptrCast(&color_fmt),
        },
    };

    if (!zgui.backend.loadFunctions(
        self.engine.ctx.api_version.toU32(),
        GraphicsContext.vkImguiLoader,
        @constCast(self.engine.ctx),
    )) return error.ImguiVulkanLoadFailed;

    zgui.backend.init(
        init_info,
        self.engine.ctx.window.ptr.value,
    );

    self.engine.gui_render_fn = guiRender;
}

pub fn onUpdate(self: *EditorLayer) void {
    zgui.backend.newFrame(@intCast(self.engine.ctx.window.getWidth()), @intCast(self.engine.ctx.window.getHeight()));

    var show_demo: bool = true;
    zgui.showDemoWindow(&show_demo);

    self.scene_editor.display();
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
