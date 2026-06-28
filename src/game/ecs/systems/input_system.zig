const sdl = @import("sdl3");

const Ecs = @import("../ecs.zig");
const EcsManager = @import("../../ecs_manager.zig");
const Event = @import("../../../events/event.zig");
const MouseState = @import("../components/components.zig").MouseState;
const System = @import("system.zig");

const InputSystem = @This();

ecs: *EcsManager,

pub fn interface(self: *InputSystem) System {
    return System.init(self);
}

pub fn init(ecs: *EcsManager) InputSystem {
    return .{ .ecs = ecs };
}

pub fn setup(self: *InputSystem) void {
    self.ecs.create_single_component_entity(Ecs.components.MouseState, .{});

    self.ecs.flush_cmd_buf();
}

pub fn update(self: *InputSystem) void {
    _ = self;
}

pub fn process(self: *InputSystem, event: Event) bool {
    switch (event.ptr) {
        .mouse_button_down => {
            const state = self.ecs.get_singleton(MouseState);
            state.locked = true;
            if (sdl.mouse.getFocus()) |win| {
                sdl.mouse.setWindowRelativeMode(win, true) catch {};
            }
            sdl.mouse.hide() catch {};
        },
        .mouse_button_up => {
            const state = self.ecs.get_singleton(MouseState);
            state.locked = false;
            if (sdl.mouse.getFocus()) |win| {
                sdl.mouse.setWindowRelativeMode(win, false) catch {};
            }
            sdl.mouse.show() catch {};
        },
        else => {
            return false;
        },
    }
    return true;
}

pub fn deinit(self: *InputSystem) void {
    _ = self;
}
