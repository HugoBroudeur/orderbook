// Event is a SDL implementation

const std = @import("std");
const sdl = @import("sdl3");

pub const Mouse = @import("mouse.event.zig");
pub const Application = @import("application.event.zig");

const Event = @This();

// pub const EventType = enum {
//     None,
//     WindowClose,
//     WindowResize,
//     WindowFocus,
//     WindowLostFocus,
//     WindowMoved,
//     AppTick,
//     AppUpdate,
//     AppRender,
//     KeyPressed,
//     KeyReleased,
//     MouseButtonPressed,
//     MouseButtonReleased,
//     MouseMoved,
//     MouseScrolled,
// };
pub const EventCategory = enum { none, application, input, keyboard, gamepad, joystick, finger, mouse, mouse_button, file, audio, pen, gpu, camera };
pub const EventCategoryType = union(EventCategory) {
    none: Application,
    application: Application,
    input: Application,
    keyboard: Application,
    gamepad: Application,
    joystick: Application,
    finger: Application,
    mouse: Mouse,
    mouse_button: Mouse,
    file: Application,
    audio: Application,
    pen: Application,
    gpu: Application,
    camera: Application,
};
// pub const EventCategoryType = packed struct { none: bool = false, application: bool = false, input: bool = false, keyboard: bool = false, mouse: bool = false, mouse_button: bool = false };

ptr: sdl.events.Event,
// category: EventCategoryType,
category: EventCategory,
handled: bool = false,

pub fn getName(self: Event) [:0]const u8 {
    return "[Event] " ++ @tagName(self.sdl_ptr);
}

pub fn getEventCategory(self: *Event) EventCategory {
    return scope(self.ptr);
    // return std.meta.activeTag(self.ptr);
}

pub fn isInCategory(self: *Event, category: EventCategory) bool {
    return @field(self.category, @tagName(category));
}

pub const Scope = enum { app, terminal };

// pub fn scope(event: Event) EventCategory {
pub fn scope(event: sdl.events.Event) EventCategory {
    @setEvalBranchQuota(10000);
    return switch (event) {
        .quit, .terminating, .low_memory, .will_enter_background, .did_enter_background, .will_enter_foreground, .did_enter_foreground, .locale_changed, .system_theme_changed, .display_orientation, .display_added, .display_removed, .display_moved, .display_desktop_mode_changed, .display_current_mode_changed, .display_content_scale_changed, .window_shown, .window_hidden, .window_exposed, .window_moved, .window_resized, .window_pixel_size_changed, .window_metal_view_resized, .window_minimized, .window_maximized, .window_restored, .window_mouse_enter, .window_mouse_leave, .window_focus_gained, .window_focus_lost, .window_close_requested, .window_hit_test, .window_icc_profile_changed, .window_display_changed, .window_display_scale_changed, .window_safe_area_changed, .window_occluded, .window_enter_fullscreen, .window_leave_fullscreen, .window_destroyed, .window_hdr_state_changed => .application,
        .key_down, .key_up, .text_editing, .text_input, .keymap_changed, .keyboard_added, .keyboard_removed, .text_editing_candidates => .keyboard,
        .mouse_button_down, .mouse_button_up, .mouse_wheel => .mouse_button,
        .mouse_motion, .mouse_added, .mouse_removed => .mouse,
        .joystick_axis_motion, .joystick_ball_motion, .joystick_hat_motion, .joystick_button_down, .joystick_button_up, .joystick_added, .joystick_removed, .joystick_battery_updated, .joystick_update_complete => .joystick,
        .gamepad_axis_motion, .gamepad_button_down, .gamepad_button_up, .gamepad_added, .gamepad_removed, .gamepad_remapped, .gamepad_touchpad_down, .gamepad_touchpad_motion, .gamepad_touchpad_up, .gamepad_sensor_update, .gamepad_update_complete, .gamepad_steam_handle_updated => .gamepad,
        .finger_down, .finger_up, .finger_motion, .finger_canceled => .finger,
        .drop_file, .drop_text, .drop_begin, .drop_complete, .drop_position => .file,
        .audio_device_added, .audio_device_removed, .audio_device_format_changed => .audio,
        .pen_proximity_in, .pen_proximity_out, .pen_down, .pen_up, .pen_button_down, .pen_button_up, .pen_motion, .pen_axis => .pen,
        .camera_device_added, .camera_device_removed, .camera_device_approved, .camera_device_denied => .camera,
        .render_targets_reset, .render_device_reset, .render_device_lost => .gpu,
        else => .none,
    };
}

pub fn scoped(self: Event, comptime s: EventCategory) ?CategoryEvent(s) {
    switch (self.ptr) {
        inline else => |v, tag| {
            // Use comptime to prune out invalid actions
            if (comptime scope(@unionInit(
                sdl.events.Event,
                @tagName(tag),
                undefined,
            )) != s) return null;

            // Initialize our app action
            return @unionInit(
                CategoryEvent(s),
                @tagName(tag),
                v,
            );
        },
    }
}

pub fn create(ptr: sdl.events.Event) Event {
    // const category: EventCategoryType = switch (std.meta.activeTag(ptr)) {
    //     .quit => .{ .application = true },
    //     .terminating => .{ .application = true },
    //     .low_memory => .{ .application = true },
    //     .will_enter_background => .{ .application = true },
    //     .did_enter_background => .{ .application = true },
    //     .will_enter_foreground => .{ .application = true },
    //     .did_enter_foreground => .{ .application = true },
    //     .locale_changed => .{ .application = true },
    //     .system_theme_changed => .{ .application = true },
    //     .display_orientation => .{ .application = true },
    //     .display_added => .{ .application = true },
    //     .display_removed => .{ .application = true },
    //     .display_moved => .{ .application = true },
    //     .display_desktop_mode_changed => .{ .application = true },
    //     .display_current_mode_changed => .{ .application = true },
    //     .display_content_scale_changed => .{ .application = true },
    //     .window_shown => .{ .application = true },
    //     .window_hidden => .{ .application = true },
    //     .window_exposed => .{ .application = true },
    //     .window_moved => .{ .application = true },
    //     .window_resized => .{ .application = true },
    //     .window_pixel_size_changed => .{ .application = true },
    //     .window_metal_view_resized => .{ .application = true },
    //     .window_minimized => .{ .application = true },
    //     .window_maximized => .{ .application = true },
    //     .window_restored => .{ .application = true },
    //     .window_mouse_enter => .{ .application = true },
    //     .window_mouse_leave => .{ .application = true },
    //     .window_focus_gained => .{ .application = true },
    //     .window_focus_lost => .{ .application = true },
    //     .window_close_requested => .{ .application = true },
    //     .window_hit_test => .{ .application = true },
    //     .window_icc_profile_changed => .{ .application = true },
    //     .window_display_changed => .{ .application = true },
    //     .window_display_scale_changed => .{ .application = true },
    //     .window_safe_area_changed => .{ .application = true },
    //     .window_occluded => .{ .application = true },
    //     .window_enter_fullscreen => .{ .application = true },
    //     .window_leave_fullscreen => .{ .application = true },
    //     .window_destroyed => .{ .application = true },
    //     .window_hdr_state_changed => .{ .application = true },
    //     .key_down => .{ .keyboard = true },
    //     .key_up => .{ .keyboard = true },
    //     .text_editing => .{ .keyboard = true },
    //     .text_input => .{ .keyboard = true },
    //     .keymap_changed => .{ .keyboard = true },
    //     .keyboard_added => .{ .keyboard = true },
    //     .keyboard_removed => .{ .keyboard = true },
    //     .text_editing_candidates => .{ .keyboard = true },
    //     .mouse_motion => .{ .mouse = true },
    //     .mouse_button_down => .{ .mouse_button = true },
    //     .mouse_button_up => .{ .mouse_button = true },
    //     .mouse_wheel => .{ .mouse_button = true },
    //     .mouse_added => .{ .mouse = true },
    //     .mouse_removed => .{ .mouse = true },
    //     .joystick_axis_motion => .{ .input = true },
    //     .joystick_ball_motion => .{ .input = true },
    //     .joystick_hat_motion => .{ .input = true },
    //     .joystick_button_down => .{ .input = true },
    //     .joystick_button_up => .{ .input = true },
    //     .joystick_added => .{ .input = true },
    //     .joystick_removed => .{ .input = true },
    //     .joystick_battery_updated => .{ .input = true },
    //     .joystick_update_complete => .{ .input = true },
    //     .gamepad_axis_motion => .{ .input = true },
    //     .gamepad_button_down => .{ .input = true },
    //     .gamepad_button_up => .{ .input = true },
    //     .gamepad_added => .{ .input = true },
    //     .gamepad_removed => .{ .input = true },
    //     .gamepad_remapped => .{ .input = true },
    //     .gamepad_touchpad_down => .{ .input = true },
    //     .gamepad_touchpad_motion => .{ .input = true },
    //     .gamepad_touchpad_up => .{ .input = true },
    //     .gamepad_sensor_update => .{ .input = true },
    //     .gamepad_update_complete => .{ .input = true },
    //     .gamepad_steam_handle_updated => .{ .input = true },
    //     .finger_down => .{ .input = true },
    //     .finger_up => .{ .input = true },
    //     .finger_motion => .{ .input = true },
    //     .finger_canceled => .{ .input = true },
    //     .clipboard_update => .{ .application = true },
    //     .drop_file => .{ .application = true },
    //     .drop_text => .{ .application = true },
    //     .drop_begin => .{ .application = true },
    //     .drop_complete => .{ .application = true },
    //     .drop_position => .{ .application = true },
    //     .audio_device_added => .{ .application = true },
    //     .audio_device_removed => .{ .application = true },
    //     .audio_device_format_changed => .{ .application = true },
    //     .sensor_update => .{ .application = true },
    //     .pen_proximity_in => .{ .input = true },
    //     .pen_proximity_out => .{ .input = true },
    //     .pen_down => .{ .input = true },
    //     .pen_up => .{ .input = true },
    //     .pen_button_down => .{ .input = true },
    //     .pen_button_up => .{ .input = true },
    //     .pen_motion => .{ .input = true },
    //     .pen_axis => .{ .input = true },
    //     .camera_device_added => .{ .application = true },
    //     .camera_device_removed => .{ .application = true },
    //     .camera_device_approved => .{ .application = true },
    //     .camera_device_denied => .{ .application = true },
    //     .render_targets_reset => .{ .application = true },
    //     .render_device_reset => .{ .application = true },
    //     .render_device_lost => .{ .application = true },
    //     .private0 => .{ .none = true },
    //     .private1 => .{ .none = true },
    //     .private2 => .{ .none = true },
    //     .private3 => .{ .none = true },
    //     .poll_sentinal => .{ .none = true },
    //     .user => .{ .none = true },
    //     .padding => .{ .none = true },
    //     .unknown => .{ .none = true },
    // };
    return .{ .ptr = ptr, .category = scope(ptr) };
}

// pub const EventFn = *const fn (*EventCategoryType) bool;

pub fn EventFn(comptime T: type) type {
    return *const fn (*T) bool; // Returns true if event was handled/consumed
}

pub const Dispatcher = struct {
    event_ptr: *Event,

    pub fn init(event_ptr: *Event) Dispatcher {
        return .{ .event_ptr = event_ptr };
    }

    pub fn dispatch(self: *Dispatcher, comptime T: type, impl_fn: EventFn(T)) bool {
        if (self.event_ptr.getEventCategory() == std.meta.activeTag(T)) {
            self.event_ptr.handled = impl_fn(self.event_ptr);
            return true;
        }
        return false;
    }
};

/// Returns a union type that only contains actions that are scoped to
/// the given scope.
pub fn CategoryEvent(comptime s: EventCategory) type {
    const all_fields = @typeInfo(sdl.events.Event).@"union".fields;

    // Find all fields that are scoped to s
    var i: usize = 0;
    var fields: [all_fields.len]std.builtin.Type.UnionField = undefined;
    for (all_fields) |field| {
        const event = @unionInit(sdl.events.Event, field.name, undefined);
        if (scope(event) == s) {
            fields[i] = field;
            i += 1;
        }
    }

    // Build our union
    return @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = null,
        .fields = fields[0..i],
        .decls = &.{},
    } });
}

// pub fn performKeyboardEvent(event: CategoryEvent(.keyboard)) void {
//     const e: *Event = @ptrCast(@alignCast(&event));
//     std.log.debug("[Event.performKeyboardEvent] {}", .{e});
//     // switch (event) {}
// }
