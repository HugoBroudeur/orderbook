// This a Graphic Context, using SDL to handle the window and display
const std = @import("std");
const sdl = @import("sdl3");
const vk = @import("vulkan");

const GraphicsContext = @This();

const Window = @import("window.zig");
const Display = @import("display.zig");
const Framerate = @import("framerate.zig");

const SDL_INIT_FLAGS: sdl.InitFlags = .{ .video = true, .gamepad = true, .audio = true };

const required_layer_names = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
const required_device_extensions = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
    vk.extensions.khr_buffer_device_address.name,
    vk.extensions.khr_shader_draw_parameters.name,
    vk.extensions.khr_dynamic_rendering.name,
};

const required_extensions = [_]vk.ApiInfo{
    vk.extensions.ext_debug_utils,
    // the following extensions are to support vulkan in mac os
    // see https://github.com/glfw/glfw/issues/2335
    vk.extensions.khr_portability_enumeration,
    vk.extensions.khr_get_physical_device_properties_2,
};

// There are 3 levels of bindings in vulkan-zig:
/// - The Dispatch types (vk.BaseDispatch, vk.InstanceDispatch, vk.DeviceDispatch)
///   are "plain" structs which just contain the function pointers for a particular
///   object.
/// - The Wrapper types (vk.Basewrapper, vk.InstanceWrapper, vk.DeviceWrapper) contains
///   the Dispatch type, as well as Ziggified Vulkan functions - these return Zig errors,
///   etc.
/// - The Proxy types (vk.InstanceProxy, vk.DeviceProxy, vk.CommandBufferProxy,
///   vk.QueueProxy) contain a pointer to a Wrapper and also contain the object's handle.
///   Calling Ziggified functions on these types automatically passes the handle as
///   the first parameter of each function. Note that this type accepts a pointer to
///   a wrapper struct as there is a problem with LLVM where embedding function pointers
///   and object pointer in the same struct leads to missed optimizations. If the wrapper
///   member is a pointer, LLVM will try to optimize it as any other vtable.
/// The wrappers contain
const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const DeviceWrapper = vk.DeviceWrapper;

const Instance = vk.InstanceProxy;
const Device = vk.DeviceProxy;

allocator: std.mem.Allocator,

display: Display,
framerate: Framerate,
window: Window,

vkb: BaseWrapper,

instance: Instance,
debug_messenger: vk.DebugUtilsMessengerEXT,
surface: vk.SurfaceKHR,
physical_device: vk.PhysicalDevice,
props: vk.PhysicalDeviceProperties,
mem_props: vk.PhysicalDeviceMemoryProperties,

device: Device,
device_found: bool = false,
graphics_queue: Queue,
present_queue: Queue,
// memory: vk.DeviceMemory,

pub fn init(allocator: std.mem.Allocator) !GraphicsContext {
    var ctx: GraphicsContext = undefined;
    ctx.allocator = allocator;
    { // Init SDL, must be first
        sdl.init(SDL_INIT_FLAGS) catch |err| {
            std.log.err("Error: {?s}", .{sdl.errors.get()});
            return err;
        };
        sdl.log.setAllPriorities(.debug);
    }

    { // Create SDL Window + choose Display
        var display: Display = try .init();
        var window = Window.create(.{}) catch |err| {
            std.log.err("[App] Can't create the Window : {}", .{err});
            return err;
        };
        display.detectCurrentDisplay(&window);
        window.center(display);
        try window.setIcon("assets/favicon.ico");
        const framerate = Framerate.init(@intFromFloat(display.refresh_rate));

        ctx.display = display;
        ctx.window = window;
        ctx.framerate = framerate;
    }

    // ctx.vkb = BaseWrapper.load(c.glfwGetInstanceProcAddress);
    const a = try sdl.vulkan.getVkGetInstanceProcAddr();

    const VkGetInstanceProcAddr = *const fn (
        instance: vk.Instance,
        pName: [*:0]const u8,
    ) callconv(.c) ?*anyopaque;

    const vkGetInstanceProcAddr: VkGetInstanceProcAddr = @ptrCast(a);
    ctx.vkb = BaseWrapper.load(vkGetInstanceProcAddr);

    if (try checkLayerSupport(&ctx.vkb, ctx.allocator) == false) {
        return error.MissingLayer;
    }

    var extension_names: std.ArrayList([*:0]const u8) = .empty;
    defer extension_names.deinit(allocator);
    for (required_extensions) |extension| {
        try extension_names.append(allocator, extension.name);
        std.log.debug("[GraphicsContext] Loading Vulkan extension: {s}", .{extension.name});
    }

    const sdl_exts = try sdl.vulkan.getInstanceExtensions();
    try extension_names.appendSlice(allocator, sdl_exts);

    const instance = try ctx.vkb.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = ctx.window.title,
            .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
            .p_engine_name = ctx.window.title,
            .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
            .api_version = @bitCast(vk.API_VERSION_1_4),
        },
        .enabled_layer_count = required_layer_names.len,
        .pp_enabled_layer_names = @ptrCast(&required_layer_names),
        .enabled_extension_count = @intCast(extension_names.items.len),
        .pp_enabled_extension_names = extension_names.items.ptr,
        // enumerate_portability_bit_khr to support vulkan in mac os
        // see https://github.com/glfw/glfw/issues/2335
        .flags = .{ .enumerate_portability_bit_khr = true },
    }, null);

    const vki = try allocator.create(InstanceWrapper);
    errdefer allocator.destroy(vki);
    vki.* = InstanceWrapper.load(instance, ctx.vkb.dispatch.vkGetInstanceProcAddr.?);
    ctx.instance = Instance.init(instance, vki);
    errdefer ctx.instance.destroyInstance(null);

    ctx.debug_messenger = try ctx.instance.createDebugUtilsMessengerEXT(&.{
        .message_severity = .{
            //.verbose_bit_ext = true,
            //.info_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = &debugUtilsMessengerCallback,
        .p_user_data = null,
    }, null);

    ctx.surface = try ctx.createSurface(&ctx.instance);
    errdefer ctx.instance.destroySurfaceKHR(ctx.surface, null);

    const candidate = try pickPhysicalDevice(ctx.instance, allocator, ctx.surface);
    ctx.physical_device = candidate.pdev;
    ctx.props = candidate.props;

    const dev = try initializeCandidate(ctx.instance, candidate);

    const vkd = try allocator.create(DeviceWrapper);
    errdefer allocator.destroy(vkd);
    vkd.* = DeviceWrapper.load(dev, ctx.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    ctx.device = Device.init(dev, vkd);
    ctx.device_found = true;
    errdefer ctx.dev.destroyDevice(null);

    ctx.graphics_queue = Queue.init(ctx.device, candidate.queues.graphics_family);
    ctx.present_queue = Queue.init(ctx.device, candidate.queues.present_family);

    ctx.mem_props = ctx.instance.getPhysicalDeviceMemoryProperties(ctx.physical_device);

    return ctx;
}

pub fn deinit(self: *GraphicsContext) void {
    if (self.device_found) {
        self.device.deviceWaitIdle() catch |err| {
            std.log.err("[GraphicsContext.deinit] Error {}", .{err});
        };
        self.device.destroyDevice(null);
    }
    self.window.deinit();
    sdl.quit(SDL_INIT_FLAGS);
}

pub fn isWindowHandled(self: *GraphicsContext, window: ?sdl.video.Window) bool {
    if (window) |w| {
        if (w.getId() catch 0 == self.window.ptr.getId() catch 0) {
            return true;
        }
    }

    return false;
}

pub fn handleDisplayChanged(self: *GraphicsContext) void {
    self.display.detectCurrentDisplay(&self.window);
    self.framerate.setTargetFps(@intFromFloat(self.display.refresh_rate));
}

pub fn getWindowId(self: *GraphicsContext) u32 {
    return self.window.ptr.getId() catch 0;
}

pub fn startFramelimiter(self: *GraphicsContext, usage: bool) void {
    if (usage) {
        self.framerate.on();
    } else {
        self.framerate.off();
    }
}

fn checkLayerSupport(vkb: *const BaseWrapper, alloc: std.mem.Allocator) !bool {
    const available_layers = try vkb.enumerateInstanceLayerPropertiesAlloc(alloc);
    for (available_layers) |layer| {
        std.log.debug("[GraphicsContext] Avaiblable Layer: {s}", .{layer.layer_name});
    }
    defer alloc.free(available_layers);
    for (required_layer_names) |required_layer| {
        for (available_layers) |layer| {
            if (std.mem.eql(u8, std.mem.span(required_layer), std.mem.sliceTo(&layer.layer_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }
    return true;
}

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(device: Device, family: u32) Queue {
        return .{
            .handle = device.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

fn createSurface(self: *GraphicsContext, instance: *Instance) !vk.SurfaceKHR {
    const sdl_instance: sdl.vulkan.Instance = @ptrFromInt(@intFromEnum(instance.handle));
    const sdl_surface = try sdl.vulkan.Surface.init(self.window.ptr, sdl_instance, null);

    const surface: vk.SurfaceKHR = @enumFromInt(@intFromPtr(sdl_surface.surface.?));

    return surface;
}

fn initializeCandidate(instance: Instance, candidate: DeviceCandidate) !vk.Device {
    const priority = [_]f32{1};
    const qci = [_]vk.DeviceQueueCreateInfo{
        .{
            .queue_family_index = candidate.queues.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
        .{
            .queue_family_index = candidate.queues.present_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
    };

    const queue_count: u32 = if (candidate.queues.graphics_family == candidate.queues.present_family)
        1
    else
        2;

    for (required_device_extensions) |extension| {
        std.log.debug("[GraphicsContext] Loading Vulkan extension: {s}", .{extension});
    }
    return try instance.createDevice(candidate.pdev, &.{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
    }, null);
}

const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueAllocation,
};

const QueueAllocation = struct {
    graphics_family: u32,
    present_family: u32,
};

fn debugUtilsMessengerCallback(severity: vk.DebugUtilsMessageSeverityFlagsEXT, msg_type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(.c) vk.Bool32 {
    const severity_str = if (severity.verbose_bit_ext) "verbose" else if (severity.info_bit_ext) "info" else if (severity.warning_bit_ext) "warning" else if (severity.error_bit_ext) "error" else "unknown";

    const type_str = if (msg_type.general_bit_ext) "general" else if (msg_type.validation_bit_ext) "validation" else if (msg_type.performance_bit_ext) "performance" else if (msg_type.device_address_binding_bit_ext) "device addr" else "unknown";

    const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";
    std.debug.print("[{s}][{s}]. Message:\n  {s}\n", .{ severity_str, type_str, message });

    return .false;
}

fn pickPhysicalDevice(
    instance: Instance,
    allocator: std.mem.Allocator,
    surface: vk.SurfaceKHR,
) !DeviceCandidate {
    const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(pdevs);

    for (pdevs) |pdev| {
        if (try checkSuitable(instance, pdev, allocator, surface)) |candidate| {
            return candidate;
        }
    }

    return error.NoSuitableDevice;
}

fn checkSuitable(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    allocator: std.mem.Allocator,
    surface: vk.SurfaceKHR,
) !?DeviceCandidate {
    if (!try checkExtensionSupport(instance, pdev, allocator)) {
        return null;
    }

    if (!try checkSurfaceSupport(instance, pdev, surface)) {
        return null;
    }

    if (try allocateQueues(instance, pdev, allocator, surface)) |allocation| {
        const props = instance.getPhysicalDeviceProperties(pdev);
        return DeviceCandidate{
            .pdev = pdev,
            .props = props,
            .queues = allocation,
        };
    }

    return null;
}

fn allocateQueues(instance: Instance, pdev: vk.PhysicalDevice, allocator: std.mem.Allocator, surface: vk.SurfaceKHR) !?QueueAllocation {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (present_family == null and (try instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surface)) == .true) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        return QueueAllocation{
            .graphics_family = graphics_family.?,
            .present_family = present_family.?,
        };
    }

    return null;
}

fn checkSurfaceSupport(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
) !bool {
    var format_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);

    return format_count > 0 and present_mode_count > 0;
}

fn checkExtensionSupport(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    allocator: std.mem.Allocator,
) !bool {
    const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
    defer allocator.free(propsv);

    // for (propsv) |extension| {
    //     std.log.debug("[GraphicsContext] Avaiblable Extension: {s}", .{extension.extension_name});
    // }

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}

pub fn createMemoryAllocateInfo(self: *const GraphicsContext, memory_requirements: vk.MemoryRequirements, properties: vk.MemoryPropertyFlags) !vk.MemoryAllocateInfo {
    return vk.MemoryAllocateInfo{
        .allocation_size = memory_requirements.size,
        .memory_type_index = try self.findMemoryTypeIndex(memory_requirements, properties),
    };
}

pub fn findMemoryTypeIndex(self: *const GraphicsContext, memory_requirements: vk.MemoryRequirements, properties: vk.MemoryPropertyFlags) !u32 {
    var memory_index: u5 = 0;
    while (memory_index < self.mem_props.memory_type_count) : (memory_index += 1) {
        const memory_type_bit: u32 = (@as(u32, 1) << memory_index);
        const is_required_memory_type = memory_requirements.memory_type_bits & memory_type_bit != 0;
        const has_required_properties = self.mem_props.memory_types[memory_index].property_flags.contains(properties);

        if (is_required_memory_type and has_required_properties) {
            return memory_index;
        }
    }

    return error.NoSuitableMemoryType;
}
