const std = @import("std");
const log = std.log.scoped(.scene_editor);
const zgui = @import("zgui");
const Uuid = @import("uuid");

const ProjectManager = @import("../project/manager.zig");
const SceneManager = @import("../engine/scene_manager.zig");
const World = @import("../ecs/world.zig");

// TODO, don't use the engine, instead emit an event to say something is loaded and the engine can consume it to create the GPU resource
const Engine = @import("../engine/vulkan/engine.zig");

const AssetExplorer = @This();

const asset_dirs = [_][]const u8{
    "assets/meshes",
};

pub const AssetKind = enum {
    mesh,
    sprite,
    sound,

    pub fn fromFileExtention(filename: []const u8) ?AssetKind {
        const ext = std.fs.path.extension(filename);

        if (std.mem.endsWith(u8, ext, ".gltf")) return .mesh;
        if (std.mem.endsWith(u8, ext, ".glb")) return .mesh;
        // if (std.mem.endsWith(u8, ext, ".png")) return .sprite;
        // if (std.mem.endsWith(u8, ext, ".wav")) return .sound;

        return null;
    }
};

const AssetEntry = struct {
    guid: ?Uuid.Uuid,
    name: [:0]const u8, // stem, dupe'd (matches AssetPool.loaded_gltf key)
    path: [:0]const u8, // full path, dupe'd
    kind: AssetKind,
};

allocator: std.mem.Allocator,
io: std.Io,
project_manager: *ProjectManager,
world: *World.Ecs.App,
engine: *Engine,

entries: std.ArrayList(AssetEntry) = .empty,
selected: ?usize = null,
icon_size: f32 = 64,
icon_spacing: f32 = 10,
needs_rescan: bool = true,

pub fn init(allocator: std.mem.Allocator, io: std.Io, project_manager: *ProjectManager, world: *World.Ecs.App, engine: *Engine) AssetExplorer {
    return .{
        .allocator = allocator,
        .io = io,
        .project_manager = project_manager,
        .world = world,
        .engine = engine,
    };
}

pub fn deinit(self: *AssetExplorer) void {
    // for (self.entries.items) |entry| {
    //     self.allocator.free(entry.name);
    //     self.allocator.free(entry.path);
    // }
    self.entries.deinit(self.allocator);
    self.selected = null;
}

pub fn display(self: *AssetExplorer) void {
    if (self.needs_rescan) {
        self.rescan() catch |err| log.err("[AssetExplorer.rescan] {}", .{err});
        self.needs_rescan = false;
    }

    zgui.setNextWindowSize(.{ .w = 480, .h = 360, .cond = .first_use_ever });
    if (zgui.begin("Asset Explorer", .{})) {
        // ── Toolbar ─────────────────────────────────────────────────────────
        if (zgui.button("Refresh", .{})) self.needs_rescan = true;
        zgui.sameLine(.{});
        zgui.setNextItemWidth(140);
        // No zgui binding to READ the mouse wheel (only addMouseWheelEvent),
        // so the demo's ctrl+wheel zoom becomes a slider.
        _ = zgui.sliderFloat("Icon size", .{ .v = &self.icon_size, .min = 32, .max = 192 });
        zgui.separator();

        self.drawGrid();
    }
    zgui.end();
}

fn rescan(self: *AssetExplorer) !void {
    self.entries.clearRetainingCapacity(); // free dupes

    for (asset_dirs) |dir_path| {
        const dir = std.Io.Dir.cwd().openDir(self.io, dir_path, .{ .iterate = true }) catch continue;
        var it = dir.iterate();
        while (try it.next(self.io)) |entry| {
            if (entry.kind != .file) continue;
            const kind = AssetKind.fromFileExtention(entry.name) orelse continue;
            try self.entries.append(self.allocator, .{
                .guid = null,
                .name = try self.allocator.dupeZ(u8, std.fs.path.stem(entry.name)),
                .path = try std.fs.path.joinZ(self.allocator, &.{ dir_path, entry.name }),
                .kind = kind,
            });
        }
    }
}

fn clearEntries(self: *AssetExplorer) void {
    for (self.entries.items) |entry| {
        self.allocator.free(entry.name);
        self.allocator.free(entry.path);
    }
    self.entries.clearRetainingCapacity();
    self.selected = null;
}

fn drawGrid(self: *AssetExplorer) void {
    const pool = &self.project_manager.asset_manager.pool;

    if (!zgui.beginChild("AssetGrid", .{})) {
        zgui.endChild();
        return;
    }
    defer zgui.endChild();

    // ── Layout: demo's UpdateLayoutSizes (stretch spacing, no scroll-x) ────
    const avail = zgui.getContentRegionAvail()[0];
    const item_size = @floor(self.icon_size);
    const label_height = zgui.getTextLineHeight() + 4;
    const tile_h = item_size + label_height;

    const column_count: usize = @max(
        @as(usize, @intFromFloat(avail / (item_size + self.icon_spacing))),
        1,
    );
    // Stretch: distribute the leftover width into the spacing.
    const spacing = if (column_count > 1)
        @floor(avail - item_size * @as(f32, @floatFromInt(column_count))) / @as(f32, @floatFromInt(column_count))
    else
        self.icon_spacing;

    const draw_list = zgui.getWindowDrawList();

    for (self.entries.items, 0..) |entry, i| {
        if (i % column_count != 0) zgui.sameLine(.{ .spacing = spacing });

        // Unique imgui ID per tile; the visible label is drawn by hand below.
        zgui.pushStrId(entry.path);
        defer zgui.popId();

        const tile_min = zgui.getCursorScreenPos();
        const icon_max = [2]f32{ tile_min[0] + item_size, tile_min[1] + item_size };

        // ── One selectable covers icon + label: click, double-click, ctx menu
        if (zgui.selectable("##tile", .{
            .selected = (self.selected == i),
            .w = item_size,
            .h = tile_h,
            .flags = .{ .allow_double_click = true },
        })) {
            self.selected = i;
            if (zgui.isMouseDoubleClicked(.left)) self.requestLoad(entry);
        }

        if (zgui.beginPopupContextItem()) {
            defer zgui.endPopup();
            if (zgui.menuItem("Load", .{})) self.requestLoad(entry);
            if (zgui.menuItem("Copy path", .{})) zgui.setClipboardText(entry.path);
        }

        // ── Tile decoration (drawlist) ──────────────────────────────────────
        const loaded = pool.loaded_gltf.contains(entry.name);

        const bg = zgui.colorConvertFloat4ToU32(switch (entry.kind) {
            .mesh => [4]f32{ 0.26, 0.32, 0.44, 1.0 },
            .sprite => [4]f32{ 0.26, 0.44, 0.32, 1.0 },
            .sound => [4]f32{ 0.44, 0.34, 0.26, 1.0 },
        });
        draw_list.addRectFilled(.{ .pmin = tile_min, .pmax = icon_max, .col = bg, .rounding = 4 });

        // Type overlay ("GLB"), bottom-right of the icon — demo's ShowTypeOverlay.
        const tag: [:0]const u8 = switch (entry.kind) {
            .mesh => "GLB",
            .sprite => "IMG",
            .sound => "SND",
        };
        const tag_size = zgui.calcTextSize(tag, .{});
        draw_list.addTextUnformatted(
            .{ icon_max[0] - tag_size[0] - 4, icon_max[1] - tag_size[1] - 2 },
            zgui.colorConvertFloat4ToU32(.{ 1, 1, 1, 0.7 }),
            tag,
        );

        // Loaded indicator: green dot, top-right corner of the icon.
        if (loaded) {
            draw_list.addCircleFilled(.{
                .p = .{ icon_max[0] - 7, tile_min[1] + 7 },
                .r = 4,
                .col = zgui.colorConvertFloat4ToU32(.{ 0.3, 0.9, 0.3, 1.0 }),
            });
        }

        // ── Name label under the icon, byte-truncated to the tile width ─────
        const label_col = zgui.colorConvertFloat4ToU32(.{ 1, 1, 1, 0.9 });
        var name: []const u8 = entry.name;
        while (name.len > 1 and zgui.calcTextSize(name, .{})[0] > item_size) {
            name = name[0 .. name.len - 1];
        }
        draw_list.addTextUnformatted(
            .{ tile_min[0], icon_max[1] + 2 },
            label_col,
            name,
        );
    }
}

fn requestLoad(self: *AssetExplorer, entry: AssetEntry) void {
    const guid = self.project_manager.asset_manager.importAsset(self.engine, entry.path) catch |err| {
        log.err("[AssetExplorer] import failed for {s}: {}", .{ entry.path, err });
        return;
    };

    const ptr = self.project_manager.asset_manager.getAsset(guid) orelse {
        log.err("[AssetExplorer] importAsset succeeded but no loaded asset found for {s} (GUID {})", .{ entry.path, guid });
        return;
    };

    self.emitEcsEvent(World.Components.AssetLoaded, .{ .name = entry.name, .ptr = ptr, .guid = guid }) catch |err| {
        log.err("No AssetLoaded emitted. Reason {}", .{err});
    };
}

fn emitEcsEvent(self: *AssetExplorer, comptime Event: type, value: Event) !void {
    const writer = try World.Ecs.EventWriter(Event).fromWorld(self.world);
    try writer.send(value);
}
