const std = @import("std");
const zgui = @import("zgui");
const sdl = @import("sdl3");

const World = @import("../ecs/world.zig");
const Components = World.Components;

const EcsExplorer = @This();

world: *World.Ecs.App,

const inspected_resources = .{
    .{ "Timers", Components.Timers },
    .{ "Window", Components.WindowState },
    .{ "Input", Components.InputState },
    .{ "Camera Speed", Components.CameraSpeed },
    .{ "Camera Sensitivity", Components.CameraSensitivity },
    .{ "Lights", Components.Lights },
    .{ "Render Camera", Components.RenderCamera },
};

const probed_components = .{
    .{ "Camera", Components.Camera },
    .{ "Transform", Components.Transform },
    .{ "Velocity", Components.Velocity },
    .{ "Rotated", Components.Rotated },
};

pub fn init(world: *World.Ecs.App) EcsExplorer {
    return .{ .world = world };
}

pub fn deinit(self: *EcsExplorer) void {
    _ = self;
}

pub fn display(self: *EcsExplorer) void {
    zgui.setNextWindowSize(.{ .w = 350, .h = 500, .cond = .first_use_ever });
    if (zgui.begin("ECS Explorer", .{})) {
        if (zgui.collapsingHeader("Resources", .{ .default_open = true }))
            self.showResources();
        if (zgui.collapsingHeader("Entities", .{ .default_open = true }))
            self.showEntities();
    }
    zgui.end();
}

fn showResources(self: *EcsExplorer) void {
    zgui.indent(.{ .indent_w = 12 });
    defer zgui.unindent(.{ .indent_w = 12 });

    inline for (inspected_resources) |entry| {
        const label, const T = entry;
        if (self.world.getResource(T) catch null) |res| {
            inspect(label, res);
        }
    }
}

fn inspect(comptime name: [:0]const u8, value: anytype) void {
    const T = @TypeOf(value.*); // value is always a pointer (*const T)

    // ── Overrides: types whose generic view is unreadable ──────────────────
    if (T == Components.KeyState) return showKeyState(value);
    if (T == Components.MouseState) return showMouseState(value);

    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            if (zgui.treeNodeStrId(name, "{s}", .{name})) {
                defer zgui.treePop();
                inline for (info.fields) |field| {
                    if (field.is_comptime) continue;
                    inspect(field.name ++ "", &@field(value.*, field.name));
                }
            }
        },
        .float => zgui.labelText(name, "{d:.3}", .{value.*}),
        .int => zgui.labelText(name, "{d}", .{value.*}),
        .bool => zgui.labelText(name, "{}", .{value.*}),
        .@"enum" => zgui.labelText(name, "{s}", .{@tagName(value.*)}),
        .array => |info| switch (@typeInfo(info.child)) {
            // [N]f32 / [N]i32 → one line: "(a, b, c, d)"
            .float, .int => {
                if (info.len <= 4) {
                    inspectVecLine(name, info.len, value);
                } else if (zgui.treeNodeStrId(name, "{s} [{d}]", .{ name, info.len })) {
                    defer zgui.treePop();
                    for (value.*, 0..) |*elem, i| {
                        zgui.text("[{d}] {d:.3}", .{ i, elem.* });
                    }
                }
            },
            // [4][4]f32 / [4]@Vector(4, f32) matrices → 4 rows
            .array, .vector => {
                if (zgui.treeNodeStrId(name, "{s}", .{name})) {
                    defer zgui.treePop();
                    for (value.*) |row| {
                        zgui.text("{d:8.3} {d:8.3} {d:8.3} {d:8.3}", .{ row[0], row[1], row[2], row[3] });
                    }
                }
            },
            else => inline for (value, 0..) |*elem, i| {
                inspect(std.fmt.comptimePrint("[{d}]", .{i}), elem);
            },
        },
        .vector => |info| { // zm.F32x4 fields, if any remain
            const arr: [info.len]info.child = value.*;
            inspectVecLine(name, info.len, &arr);
        },
        .optional => {
            if (value.*) |*inner| inspect(name, inner) else zgui.labelText(name, "null", .{});
        },
        else => zgui.labelText(name, "<{s}>", .{@typeName(T)}),
    }
}

fn showEntities(self: *EcsExplorer) void {
    zgui.indent(.{ .indent_w = 12 });
    defer zgui.unindent(.{ .indent_w = 12 });

    inline for (probed_components) |entry| {
        const label, const T = entry;
        showComponentGroup(self, label, T);
    }
}

fn showComponentGroup(self: *EcsExplorer, comptime label: [:0]const u8, comptime T: type) void {
    const q = World.Ecs.Query(struct {
        id: *const Components.ID,
        comp: *const T,
    }).fromWorld(self.world) catch return;

    var count: usize = 0;
    var counter = q.iter();
    while (counter.next()) |_| count += 1;

    if (!zgui.collapsingHeader(label, .{})) return;
    zgui.text("{d} entities", .{count});

    var it = q.iter();
    while (it.next()) |e| {
        // The same entity shows up under several component groups, so the
        // imgui ID must combine the group label with the guid.
        var id_buf: [128]u8 = undefined;
        const str_id = generateZguiId(&id_buf, "showComponentGroup", label, e.id.guid);
        if (zgui.treeNodeStrId(str_id, "Entity {x:0>8}", .{@as(u32, @truncate(e.id.guid))})) {
            defer zgui.treePop();
            inspect(label, e.comp);
        }
    }
}
fn inspectVecLine(name: [:0]const u8, comptime len: usize, value: anytype) void {
    var buf: [128]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    inline for (0..len) |i| {
        w.print("{s}{d:.3}", .{ if (i == 0) "(" else ", ", value[i] }) catch break;
    }
    w.writeAll(")") catch {};
    zgui.labelText(name, "{s}", .{w.buffered()});
}

fn showKeyState(k: *const Components.KeyState) void {
    if (!zgui.treeNodeStrId("key", "Keyboard", .{})) return;
    defer zgui.treePop();

    zgui.text("held:", .{});
    zgui.sameLine(.{});
    var any = false;
    for (std.enums.values(sdl.Scancode)) |sc| {
        if (!k.isHeld(sc)) continue;
        zgui.sameLine(.{});
        zgui.text("{s}", .{@tagName(sc)});
        any = true;
    }
    if (!any) {
        zgui.sameLine(.{});
        zgui.text("-", .{});
    }

    zgui.text("pressed: {d}  released: {d}", .{ k.pressed.count(), k.released.count() });
}

fn showMouseState(m: *const Components.MouseState) void {
    if (!zgui.treeNodeStrId("mouse", "Mouse", .{})) return;
    defer zgui.treePop();

    zgui.text("pos ({d:.0}, {d:.0})  delta ({d:.1}, {d:.1})", .{ m.pos[0], m.pos[1], m.delta[0], m.delta[1] });
    inline for (@typeInfo(Components.MouseState.Button).@"enum".fields) |f| {
        if (m.mouseHeld(@enumFromInt(f.value))) {
            zgui.sameLine(.{});
            zgui.text("[{s}]", .{f.name});
        }
    }
}

/// The returned slice points into `buf`, which the caller must keep alive
/// while the ID is in use.
fn generateZguiId(buf: []u8, comptime prefix: []const u8, comptime label: [:0]const u8, id: u128) [:0]const u8 {
    return std.fmt.bufPrintZ(buf, prefix ++ "_" ++ label ++ "_{x}", .{id}) catch prefix ++ "_" ++ label;
}
