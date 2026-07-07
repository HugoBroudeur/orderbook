const std = @import("std");
const zgui = @import("zgui");
const vk = @import("vulkan");
const log = std.log.scoped(.render_layer);

const Event = @import("../events/event.zig");
const EcsEvent = @import("../framework/event_queue.zig").Event;
const GraphicsContext = @import("../core/graphics_context.zig");

const Layer = @import("../core/layer.zig");
const Engine = @import("../engine/vulkan/engine.zig");
const Framerate = @import("../core/framerate.zig");
const World = @import("../ecs/world.zig");
const ProjectManager = @import("../project/manager.zig");

const RenderLayer = @This();

label: []const u8 = "Render Layer",

allocator: std.mem.Allocator,
io: std.Io,
graphics_context: *GraphicsContext,
engine: Engine = undefined,
world: *World,
// draw_context: *Scene.DrawContext, // App-owned (Step 3)
framerate: *Framerate,
project_manager: *ProjectManager,

pub fn init(allocator: std.mem.Allocator, io: std.Io, graphics_context: *GraphicsContext, framerate: *Framerate, world: *World, project_manager: *ProjectManager) RenderLayer {
    return .{
        .allocator = allocator,
        .io = io,
        .graphics_context = graphics_context,
        .framerate = framerate,
        .world = world,
        .project_manager = project_manager,
    };
}

pub fn deinit(self: *RenderLayer) void {
    self.engine.ctx.device.deviceWaitIdle() catch {};
    self.engine.gui_render_fn = null;
    self.project_manager.asset_manager.deinit(&self.engine);
    zgui.backend.deinit();
    zgui.deinit();

    self.engine.deinit();
}

pub fn interface(self: *RenderLayer) Layer {
    return Layer.init(self);
}

pub fn getLabel(self: *RenderLayer) []const u8 {
    return self.label;
}

pub fn onAttach(self: *RenderLayer) !void {
    self.engine = try Engine.init(self.allocator, self.graphics_context, self.io);
    self.engine.setup() catch |err| {
        log.err("Can't setup the Vulkan Engine : {}", .{err});
        return err;
    };

    const size = try self.engine.ctx.window.ptr.getSize();
    if (self.world.app.getResource(World.Components.WindowState) catch null) |ws| {
        ws.width = @intCast(size[0]);
        ws.height = @intCast(size[1]);
    }

    try self.setupZgui();

    self.project_manager.asset_manager.processQueuedAssets(&self.engine);
}

pub fn onUpdate(self: *RenderLayer) void {
    const scene = self.project_manager.scene_manager.getCurrentScene() orelse {
        log.warn("No current scene — nothing to render", .{});
        return;
    };

    if (!self.framerate.shouldDraw()) return;

    // Don't render if window is minimised
    if (self.engine.ctx.window.getWidth() == 0 or self.engine.ctx.window.getHeight() == 0) return;

    self.world.app.runPar(World.Schedule.pre_render);
    self.world.app.flushCommands();
    self.world.app.run(World.Schedule.render);
    self.world.app.flushCommands();

    self.engine.render(scene, &self.project_manager.asset_manager.pool) catch |err| {
        log.err("Render failed: {}", .{err});
    };
}

pub fn onEvent(self: *RenderLayer, ev: Event) bool {
    _ = self; // autofix
    _ = ev; // autofix

    // switch (ev.ptr) {
    //     .quit => {
    //         const close_event: sdl.events.Event = .{ .quit = .{ .common = .{ .timestamp = 0 } } };
    //         sdl.events.push(close_event) catch {};
    //         return true;
    //     },
    //     .key_down => {
    //         switch (ev.ptr.key_down.key.?) {
    //             .escape => {
    //                 const close_event: sdl.events.Event = .{ .window_close_requested = .{ .id = self.engine.ctx.getWindowId(), .common = .{ .timestamp = 0 } } };
    //                 sdl.events.push(close_event) catch {};
    //                 return true;
    //             },
    //             else => {},
    //         }
    //     },
    //     else => {},
    // }

    // const queue = self.world.app.getResource(World.Components.RawInputQueue) catch null;
    // if (null != queue) {
    //     var event: EcsEvent = .{ .ptr = ev.ptr, .type = .keyboard_pressed };
    //     queue.?.pushEvent(&event);
    // }

    // return self.ecs_manager.handleEvent(ev);
    return false;
}

fn setupZgui(self: *RenderLayer) !void {
    // The ImGui context is created by EditorLayer.onAttach (which runs before
    // this layer attaches); here we only initialize the Vulkan/SDL backends.
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

fn guiRender(cmd: vk.CommandBuffer) void {
    zgui.backend.render(@ptrFromInt(@intFromEnum(cmd)));
}
