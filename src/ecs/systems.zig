const std = @import("std");
const log = std.log.scoped(.ecs_systems);
const zm = @import("zmath");
const sdl = @import("sdl3");
const zgui = @import("zgui");

const World = @import("world.zig");
const Components = World.Components;
const Schedule = World.Schedule;
const Gamestate = World.Gamestate;

const Query = World.Ecs.Query;
const QueryF = World.Ecs.QueryF;
const With = World.Ecs.Filter.With;
const ResMut = World.Ecs.ResMut;
const Res = World.Ecs.Res;
const Commands = World.Ecs.Commands;
const EventReader = World.Ecs.EventReader;
const EventWriter = World.Ecs.EventWriter;

const Uuid = @import("uuid");

pub const Plugins = struct {
    pub const Startup = struct {
        pub fn plugin(world: *World.Ecs.App) !void {
            // Create resources
            try world.addResource(Components.Timers{});
            try world.addResource(Components.Stats.init());
            try world.addResource(Components.WindowState{});
            try world.addResource(Components.InputState{});
            try world.addResource(Components.CameraSpeed{});
            try world.addResource(Components.CameraSensitivity{});
            try world.addResource(Components.Lights{});
            try world.addResource(Components.RenderCamera{ .kind = .perspective });
            try world.addResource(Components.DrawContextQueue.init(world.memtator.parent));
            world.flushCommands();

            // Register States
            try world.addPlugin(World.Ecs.StatePlugin(World.Gamestate.boot, World.Schedule.cleanup));

            // Register Events
            try world.addPlugin(World.Ecs.EventPlugin(Components.PendingSceneEvent, Schedule.post_update));
            try world.addPlugin(World.Ecs.EventPlugin(Components.LoadedSceneEvent, Schedule.cleanup));
            try world.addPlugin(World.Ecs.EventPlugin(Components.AssetLoaded, Schedule.cleanup));
            try world.addPlugin(World.Ecs.EventPlugin(Components.SkyboxRenamed, Schedule.cleanup));

            // Pre update systems
            try world.addSystem(Schedule.pre_update, World.Ecs.Chain(.{
                &updateTimers,
                &updateInputState,
                &cameraInput,
            }));
            try world.addSystemEx(Schedule.pre_update, &debugGamestate, World.Ecs.OnTransition(Gamestate));

            try world.addSystemEx(Schedule.pre_update, World.Ecs.Chain(.{
                &instantiateScene,
                &finalizeSceneLoad,
            }), World.Ecs.InState(Gamestate.loading));

            try world.addSystemEx(Schedule.pre_update, &spawnCamera, World.Ecs.OnEnter(Gamestate.main));

            // Update systems
            try world.addSystem(Schedule.update, World.Ecs.Chain(.{
                &transformVelocity,
                &transformRotated,
            }));

            // Pre Render Systems
            try world.addSystem(Schedule.pre_render, World.Ecs.Chain(.{
                &onAssetLoaded,
            }));

            try world.addSystem(Schedule.pre_render, &updateRenderCamera);

            // Render Systems
            try world.addSystem(Schedule.render, &drawScene);

            // Shutdown Systems
            try world.addSystemEx(Schedule.cleanup, &shutdown, World.Ecs.OnEnter(Gamestate.shutdown));
        }
    };
};

/// DEBUG: logs every Gamestate change exactly once.
/// Self-deduplicating because knoedel's OnTransition filter never updates its
/// observer (unlike OnEnter/OnExit) and therefore fires every frame after the
/// first transition — see state.zig OnTransition, missing
/// `local.last_transition = s.last_transition`.
var debug_last_transition: ?struct { from: Gamestate, to: Gamestate } = null;

fn debugGamestate(
    state: Res(World.Ecs.State(Gamestate)),
) !void {
    const t = state.inner.last_transition;
    if (debug_last_transition) |last| {
        if (last.from == t.from and last.to == t.to) return;
    }
    debug_last_transition = .{ .from = t.from, .to = t.to };
    log.debug("[Gamestate] {s} -> {s}", .{ @tagName(t.from), @tagName(t.to) });
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
    existing: QueryF(struct { c: *const Components.Camera }, With(Components.CameraActive)),
    alloc: World.Ecs.Alloc,
    cmd: Commands,
) !void {
    var it = existing.iter();
    if (it.next() != null) return; // scene brought its own camera

    _ = try cmd.spawn(.{
        Components.ID{ .guid = Uuid.v4.new(alloc.io) },
        Components.Camera{
            .kind = .perspective,
            .near = 0.1,
            .far = 10000,
            .fov = 70,
        },
        Components.CameraActive{ .is_active = true },
        Components.TransformComponent{ .translation = .{ .z = 5 } },
        Components.Rotated{},
        Components.Velocity{},
        World.Ecs.StateScoped(World.Gamestate){ .state = .main },
    });
}

fn transformVelocity(
    query: Query(struct {
        t: *Components.TransformComponent,
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
        t: *Components.TransformComponent,
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
        t: *const Components.TransformComponent,
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
        t: *const Components.TransformComponent,
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

fn drawScene(
    query: Query(struct {
        m: *Components.Model,
        t: *const Components.TransformComponent,
    }),
    draw_context: ResMut(Components.DrawContextQueue),
    // skybox: Res(Components.Skybox),
    stats: ResMut(Components.Stats),
) !void {
    var it = query.iter();
    stats.inner.startClock(.scene_build);

    // Clear queues
    draw_context.inner.reset();

    // draw_context.inner.skybox =

    while (it.next()) |entry| {
        var top_matrix = entry.t.toMatrix();
        try entry.m.ptr.draw(&top_matrix, draw_context.inner);
    }

    stats.inner.tickClock(.scene_build);
}

fn instantiateScene(
    cmd: Commands,
    reader: EventReader(Components.PendingSceneEvent),
    writer: EventWriter(Components.LoadedSceneEvent),
    // lights: ResMut(Components.Lights),
    game_state: ResMut(World.Ecs.State(Gamestate)),
    assets: Res(World.Components.AssetManagerHandle),
) !void {
    for (reader.events) |ev| {
        const data = ev.scene_manager.getCurrentSceneData() orelse {
            log.err("PendingSceneEvent for unprepared scene {}", .{ev.scene_guid});
            continue;
        };

        inline for (World.SavedConfig.SavedResourceList) |R| {
            if (@field(data.resources, World.simpleTypeName(R))) |val| {
                (try ev.scene_manager.world.app.getResource(R)).* = val;
            }
        }

        for (data.entities) |e| {
            const entity = try cmd.spawn(.{Components.ID{ .guid = e.entity_guid }});

            inline for (World.SavedConfig.SavedComponentList) |C| {
                if (@field(e.components, World.simpleTypeName(C))) |val| {
                    try cmd.insert(entity, .{val});
                }
            }

            if (e.gltf_uuid) |guid| {
                if (assets.inner.ptr.getAsset(guid)) |ptr| {
                    const meta = assets.inner.ptr.pool.asset_metadata.get(guid);
                    try cmd.insert(entity, .{
                        Components.Model{
                            .guid = guid,
                            .name = if (meta) |m| m.name else "",
                            .ptr = ptr,
                        },
                    });
                } else {
                    log.warn("Scene entity {} references unknown/unloaded GLTF asset {} — was the project's asset pool loaded?", .{ e.entity_guid, guid });
                }
            }
        }

        try writer.send(.{ .scene_guid = ev.scene_guid });

        game_state.inner.set(.main);
    }
}

fn finalizeSceneLoad(
    reader: World.Ecs.EventReader(Components.LoadedSceneEvent),
) !void {
    for (reader.events) |event| {
        log.info("Event scene loaded in ECS: {}", .{event.scene_guid});
    }
}

fn onAssetLoaded(
    alloc: World.Ecs.Alloc,
    cmd: World.Ecs.Commands,
    reader: World.Ecs.EventReader(Components.AssetLoaded),
) !void {
    for (reader.events) |event| {
        const guid = Uuid.v4.new(alloc.io);
        _ = try cmd.spawn(.{
            Components.ID{ .guid = guid },
            Components.Model{ .ptr = event.ptr, .name = event.name, .guid = guid },
            Components.TransformComponent{},
        });

        log.info("Add GLTF Mesh in ECS: {s}", .{event.name});
    }
}

fn onSkyboxRenamed(
    alloc: World.Ecs.Alloc,
    cmd: World.Ecs.Commands,
    reader: World.Ecs.EventReader(Components.SkyboxRenamed),
    skybox: ResMut(Components.Skybox),
) !void {
    _ = alloc; // autofix
    _ = cmd; // autofix
    for (reader.events) |event| {

        // asset loader has a cube_image cache, it attempts to load the image if not exists
        // return guid

        // engine has a string hash map name/Skybox (same as pbr_material)
        // upload data to GPU via the engine/graphic/skybox.zig

        skybox.inner.name = event.name;
        // skybox.inner.guid = guid;

        log.info("Add GLTF Mesh in ECS: {s}", .{event.name});
    }
}

/// This system free GPU/CPU memory when the app shutdown, the library does not seem to do that
/// So it needs to be manually done here
fn shutdown(
    alloc: World.Ecs.Alloc,
    draw_context: ResMut(Components.DrawContextQueue),
) !void {
    draw_context.inner.deinit(alloc.gpa);

    log.info("Shutdown ECS", .{});
}
