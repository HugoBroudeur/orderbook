const std = @import("std");
const zm = @import("zmath");
const sdl = @import("sdl3");
const zgui = @import("zgui");

const Commands = @import("../engine/command.zig");

const World = @import("world.zig");
const Components = World.Components;
const Schedule = World.Schedule;
const Gamestate = World.Gamestate;

const Query = World.Ecs.Query;
const QueryF = World.Ecs.QueryF;
const With = World.Ecs.Filter.With;

const Uuid = @import("uuid");

pub const Plugins = struct {
    pub const Startup = struct {
        pub fn plugin(world: *World.Ecs.App) !void {
            try world.addResource(Components.Timers{});
            try world.addResource(Components.Stats.init());
            { // Input states
                try world.addResource(Components.WindowState{});
                try world.addResource(Components.InputState{});
                // try world.addResource(Components.CameraInput{});
            }
            try world.addResource(Components.CameraSpeed{});
            try world.addResource(Components.CameraSensitivity{});
            try world.addResource(Components.Lights{});
            try world.addResource(Components.RenderCamera{ .kind = .perspective });
            world.flushCommands();

            try world.addSystemEx(Schedule.init, &dummy, World.Ecs.OnEnter(Gamestate.boot));
            try world.addSystemEx(Schedule.init, &spawnCamera, World.Ecs.OnEnter(Gamestate.boot));

            try world.addSystem(Schedule.pre_update, World.Ecs.Chain(.{
                // The order matter !!
                &updateTimers,
                &updateInputState,
                &cameraInput,

                &transformVelocity,
                &transformRotated,
            }));

            try world.addSystem(Schedule.pre_render, &updateRenderCamera);
            // try world.addSystem(Schedule.render, &render);

            try world.addPlugin(World.Ecs.StatePlugin(World.Gamestate.boot, World.Schedule.init));
            try world.addPlugin(World.Ecs.StatePlugin(World.Gamestate.main, World.Schedule.pre_update));
            // try world.addPlugin(World.Ecs.StatePlugin(World.Gamestate.menu, World.Schedule.pre_update));
            try world.addPlugin(World.Ecs.StatePlugin(World.Gamestate.loading, World.Schedule.cleanup));
            // try world.addPlugin(World.Ecs.EventPlugin(Components.CameraMovedEvent, Schedule.cleanup));
        }
    };
};

/// DEBUG SYSTEM
fn dummy(
    cmd: World.Ecs.Commands,
) !void {
    _ = try cmd.spawn(.{
        Components.ID{ .guid = 1 },
        Components.Transform{ .translation = .{ .x = 1 } },
    });
    _ = try cmd.spawn(.{
        Components.ID{ .guid = 2 },
        Components.Transform{ .rotation = .{ 1, 2, 3, 4 } },
    });
    _ = try cmd.spawn(.{
        Components.ID{ .guid = 3 },
        Components.Transform{ .scale = .{ .x = 1 } },
    });
}

fn updateTimers(
    timers: World.Ecs.ResMut(Components.Timers),
) !void {
    const now = sdl.timer.getMillisecondsSinceInit();
    // First frame: world_time is 0, keep dt at 0 rather than "time since app start".
    timers.inner.dt = if (timers.inner.world_time == 0) 0 else now - timers.inner.world_time;
    timers.inner.world_time = now;
}

fn updateInputState(
    queue: World.Ecs.ResMut(Components.RawInputQueue),
    input: World.Ecs.ResMut(Components.InputState),
    window: World.Ecs.ResMut(Components.WindowState),
) !void {
    // Clear per-frame state (pressed/released/mouse delta) before draining.
    input.inner.reset();

    while (queue.inner.getEvent()) |ev| {
        if (ev.ptr) |ptr| {
            switch (ptr) {
                .key_down => |k| input.inner.key.onKeyDown(k.scancode.?),
                .key_up => |k| input.inner.key.onKeyUp(k.scancode.?),
                .mouse_button_down => |m| input.inner.mouse.onMouseDown(@enumFromInt(@as(u3, @intCast(@intFromEnum(m.button))) - 1)),
                .mouse_button_up => |m| input.inner.mouse.onMouseUp(@enumFromInt(@as(u3, @intCast(@intFromEnum(m.button))) - 1)),
                .mouse_motion => |m| input.inner.mouse.onMouseMotion(m.x, m.y, m.x_rel, m.y_rel),
                .window_resized => |w| {
                    window.inner.width = @intCast(w.width);
                    window.inner.height = @intCast(w.height);
                },
                else => {},
            }
        }
    }
}

fn spawnCamera(
    alloc: World.Ecs.Alloc,
    cmd: World.Ecs.Commands,
) !void {
    _ = try cmd.spawn(.{
        Components.ID{ .guid = Uuid.v4.new(alloc.io) },
        Components.Camera{
            .kind = .perspective,
            .near = 0.1,
            .far = 10000,
            .fov = 70,
        },
        Components.CameraActive{},
        // Transform is authoritative: camera world pos derives from it at render prep.
        Components.Transform{ .translation = .{ .z = 5 } },
        Components.Rotated{},
        Components.Velocity{},
    });
}

fn transformVelocity(
    query: Query(struct {
        t: *Components.Transform,
        v: *const Components.Velocity,
    }),
) !void {
    var it = query.iter();
    while (it.next()) |entry| {
        var t = &entry.t.translation;
        const v = entry.v;

        // Velocity is expressed in the entity's local frame (z = forward
        // along -Z, x = strafe, y = up). Rotate it by the current orientation
        // so translation advances along the entity's own axes.
        const rot: zm.F32x4 = entry.t.rotation;
        const delta = zm.rotate(rot, zm.f32x4(v.x, v.y, -v.z, 0));

        t.x = t.x + delta[0];
        t.y = t.y + delta[1];
        t.z = t.z + delta[2];
    }
}

fn transformRotated(
    query: Query(struct {
        t: *Components.Transform,
        r: *const Components.Rotated,
    }),
) !void {
    var it = query.iter();
    while (it.next()) |entry| {
        const current: zm.F32x4 = entry.t.rotation;
        const delta: zm.F32x4 = entry.r.delta;
        // Row-vector convention: the first-applied factor acts in the
        // entity's local frame.
        entry.t.rotation = zm.normalize4(zm.qmul(delta, current));
    }
}

fn cameraInput(
    input: World.Ecs.Res(Components.InputState),
    sp: World.Ecs.Res(Components.CameraSpeed),
    se: World.Ecs.Res(Components.CameraSensitivity),
    query: QueryF(struct {
        t: *const Components.Transform,
        r: *Components.Rotated,
        v: *Components.Velocity,
    }, With(Components.CameraActive)),
    timers: World.Ecs.Res(Components.Timers),
) !void {
    const dt = timers.inner.dt;
    const speed = @as(f32, @floatFromInt(dt)) * sp.inner.speed;

    var dx = input.inner.mouse.delta[0];
    var dy = input.inner.mouse.delta[1];
    var vel: Components.Velocity = .{};

    switch (input.inner.mouse.mouseHeld(.left)) {
        true => {
            vel = .{
                .z = if (input.inner.key.isHeld(.d)) speed else if (input.inner.key.isHeld(.t)) -speed else 0,
                .x = if (input.inner.key.isHeld(.s)) speed else if (input.inner.key.isHeld(.r)) -speed else 0,
                .y = if (input.inner.key.isHeld(.space)) speed else if (input.inner.key.isHeld(.left_shift)) -speed else 0,
            };

            if (sdl.mouse.getFocus()) |win| {
                sdl.mouse.setWindowRelativeMode(win, true) catch {};
            }
            sdl.mouse.hide() catch {};
        },
        false => {
            dx = 0;
            dy = 0;
            if (sdl.mouse.getFocus()) |win| {
                sdl.mouse.setWindowRelativeMode(win, false) catch {};
            }
            sdl.mouse.show() catch {};
        },
    }

    const delta_yaw = dx / se.inner.sensitivity * se.inner.inverted_multiplier;
    const delta_pitch = dy / se.inner.sensitivity * se.inner.inverted_multiplier;

    var it = query.iter();
    while (it.next()) |entry| {
        entry.v.* = vel;

        // Yaw must stay about the WORLD up axis or roll accumulates. The
        // delta is local-only, so express world-up in the camera's local
        // frame first; rotating about that local axis == rotating about
        // world up.
        const current: zm.F32x4 = entry.t.rotation;
        const up_local = zm.rotate(zm.inverse(current), zm.f32x4(0, 1, 0, 0));

        const pitch_q = zm.quatFromAxisAngle(zm.f32x4(1, 0, 0, 0), delta_pitch);
        const yaw_q = zm.quatFromAxisAngle(up_local, delta_yaw);

        entry.r.* = .{ .delta = zm.qmul(pitch_q, yaw_q) };
    }
}

fn updateRenderCamera(
    window: World.Ecs.Res(Components.WindowState),
    query: QueryF(struct {
        c: *Components.Camera,
        t: *const Components.Transform,
    }, With(Components.CameraActive)),
    render_camera: World.Ecs.ResMut(Components.RenderCamera),
) !void {
    var it = query.iter();
    // Will use the last Active camera as the "main" camera
    while (it.next()) |entry| {
        const camera = entry.c;
        const transform = entry.t;

        // World-space camera state is derived here, at render prep — update
        // systems only ever touch the local Transform.
        camera.setViewport(.{
            .x = 0,
            .y = 0,
            .width = window.inner.width,
            .heigth = window.inner.height,
        });
        camera.setLookQuat(transform.rotation);
        camera.pos = .{ transform.translation.x, transform.translation.y, transform.translation.z, 1 };

        render_camera.inner.* = camera.*;
    }
}
