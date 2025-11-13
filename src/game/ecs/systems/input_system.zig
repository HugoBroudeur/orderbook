const std = @import("std");
const zecs = @import("zecs");
const data = @import("../data.zig");
// const logger = @import("../../debug/log.zig");
// const log = logger.ecs;
const Ecs = @import("../ecs.zig");
const System = @import("system.zig");
const sokol = @import("sokol");
const sapp = sokol.app;

// const Self = @This();
//
// pub fn setup(self: *Self, ecs: *Ecs) void {
//     _ = &self;
//     _ = &ecs;
// }
//
// pub fn handleInputs(reg: *zecs.Registry) void {
//     _ = &reg;
// }
//
// pub fn collectSokolEvent(self: *Self, event: sapp.Event) !void {
//     try self.events.append(event);
// }
//
// pub fn consumeEvent(self: *Self) void {
//     const event = self.events.pop();
//     if (event.?.type == .KEY_DOWN) {
//         switch (event.?.key_code) {
//             .ESCAPE => sapp.quit(),
//             // .D => ,
//             // .S => ,
//             // .R => ,
//             // .T => ,
//             .Z => logger.toggle(),
//             .W => logger.toggleEcs(),
//             else => {},
//         }
//     }
// }

pub const InputSystem = struct {
    events: std.ArrayList(sapp.Event) = undefined,

    pub fn create(allocator: std.mem.Allocator) InputSystem {
        return .{
            .events = .init(allocator),
        };
    }

    pub fn system(self: *InputSystem) System {
        return .{
            .ptr = self,
            .vtable = &.{
                .onSetup = onSetup,
                .onFrame = onFrame,
                .once = once,
            },
        };
    }

    fn onSetup(ctx: *anyopaque, reg: *zecs.Registry) void {
        const self: *InputSystem = @ptrCast(@alignCast(ctx));
        // _ = reg;
        _ = self;
        // const mouse_buttons: std.EnumArray(sapp.Mousebutton, sapp.EventType) = .initFill(.MOUSE_UP);

        const mouse_state: data.MouseState = .{
            .cursor = .zero(),
            .speed = .zero(),
            .scroll = .zero(),
            .buttons = .initFill(.MOUSE_UP),
        };

        // const keys: std.EnumArray(sapp.Keycode, sapp.EventType) = .initFill(.KEY_UP);

        const state: data.InputsState = .{
            .mouse = mouse_state,
            // .keys = keys,
            .keys = .initFill(.KEY_UP),
        };

        reg.singletons().add(data.InputEvent{ .code = .INVALID, .status = .INVALID });
        // reg.singletons().add(sapp.Event{});
        reg.singletons().add(state);
        // _ = reg.singletons().get(sapp.Event);

        // Camera
        // const camera = self.reg.create();
        // self.reg.add(camera, data.Camera{ .primary = true, .type = .perspective });
        // self.reg.add(camera, data.PerspectiveCamera{});
        //
        // for (0..5) |i| {
        //     const ob = self.reg.create();
        //     self.reg.add(ob, data.GameObject{ .pos = .{ .x = @as(f32, @floatFromInt(i)) / 10, .y = @as(f32, @floatFromInt(i)) / 10, .z = 0 } });
        // }

        // TODO: Load config for keybinds
    }

    fn onFrame(ctx: *anyopaque, reg: *zecs.Registry) void {
        const self: *InputSystem = @ptrCast(@alignCast(ctx));
        _ = reg;
        _ = self;

        // self.updateState(reg);
        // sapp.Event   }
    }

    fn once(ctx: *anyopaque, reg: *zecs.Registry) void {
        const self: *InputSystem = @ptrCast(@alignCast(ctx));

        self.handleCoreInputs(reg);
    }

    // pub fn collect(self: *InputSystem, event: sapp.Event) !void {
    //     try self.events.append(event);
    // }

    fn handleCoreInputs(self: *InputSystem, reg: *zecs.Registry) void {
        _ = &self;
        var i = reg.singletons().getConst(data.InputsState);
        // const it = i.keys.iterator();

        //         while (it.next()) |k| {
        //             switch (k.value) {
        // .pressed =>  {},
        // .released =>  {},
        //             }
        //         }

        if (i.keys.get(.ESCAPE) == .KEY_DOWN) {
            sapp.quit();
        }
        if (i.keys.get(.Z) == .KEY_DOWN) {
            // logger.toggle();
        }
        if (i.keys.get(.W) == .KEY_DOWN) {
            // logger.toggleEcs();
        }
        //
        // if (i.keys.get(.ESCAPE) == .pressed) {
        // if (event.?.type == .KEY_DOWN) {
        //     switch (event.?.key_code) {
        //         .ESCAPE => sapp.quit(),
        //         // .D => ,
        //         // .S => ,
        //         // .R => ,
        //         // .T => ,
        //         .Z => logger.toggle(),
        //         .W => logger.toggleEcs(),
        //         else => {},
        //     }
        // }
    }
};
