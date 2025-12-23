const std = @import("std");
const uuid = @import("../math/uuid.zig");
const vec = @import("../math/vec.zig");
const hex = @import("../math/hex.zig");
const shape = @import("../math/shape.zig");

const Mat4 = vec.Mat4;

pub const Graphics = @import("graphics.zig");

// ACSII Generator: https://patorjk.com/software/taag/#p=display&f=ANSI%20Shadow&t=Graphics

//  ██████╗ ██████╗ ██████╗ ███████╗
// ██╔════╝██╔═══██╗██╔══██╗██╔════╝
// ██║     ██║   ██║██████╔╝█████╗
// ██║     ██║   ██║██╔══██╗██╔══╝
// ╚██████╗╚██████╔╝██║  ██║███████╗
//  ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝

pub const EnvironmentInfo = struct {
    world_time: f64,
    window_width: i32 = 0,
    window_height: i32 = 0,
};

pub const ID = struct {
    id: uuid.Uuid = uuid.new(),
};

pub const GameObject = struct {
    pos: vec.Vec3 = vec.Vec3.zero(),
    is_visible: bool = false,
};

pub const Event = @import("events.zig");

pub const TickRate = struct {
    ratio: u32 = 1,
};

pub const Resource = struct {
    name: []const u8,
    type: ResourceTypes,
    qty_owned: u32 = 0,
    qty_max: u32 = 100,

    fn produce(self: *Resource, qty: u32) void {
        if (self.qty_owned + qty > self.qty_max) {
            self.qty_owned = self.qty_max;
            return;
        }

        self.qty_owned += qty;
    }

    fn consume(self: *Resource, qty: u32) Error!void {
        if (self.qty_owned - qty < 0) {
            return Error.NotEnoughResource;
        }
        self.qty_owned -= qty;
    }

    pub fn getName(self: Resource) []const u8 {
        return self.type.getName();
    }
};

pub const Generator = struct {
    ratio: u32 = 1,
    multiplier: i32 = 1,
};

pub const Converter = struct {
    inputs: []RecipeInput,
    outputs: []RecipeOutput,
    ratio: i32 = 1,
};

pub const RecipeInput = struct {
    asset: ResourceTypes,
    qty: u32 = 1,
};

pub const RecipeOutput = struct {
    asset: ResourceTypes,
    qty: u32 = 1,
};

pub const Error = error{
    NotEnoughResource,
    IsNotAResource,
};

pub const Locked = struct {};
pub const Unlocked = struct {};

// ██╗   ██╗██╗
// ██║   ██║██║
// ██║   ██║██║
// ██║   ██║██║
// ╚██████╔╝██║
//  ╚═════╝ ╚═╝

pub const Styles = @import("styles.zig");

pub const Button = struct {
    label: []const u8,
    is_pressed: bool = false,
};

pub const UIState = struct {
    show_first_window: bool = true,
    show_second_window: bool = true,
    current_theme: usize = 0,
    themes: [3][]const u8 = .{
        &@tagName(Styles.Theme.custom).*,
        &@tagName(Styles.Theme.enemymouse).*,
        &@tagName(Styles.Theme.spectrum_light).*,
    },
    window_width: i32 = 0,
    window_height: i32 = 0,
    is_demo_open: bool = true,
    progress: f32 = 0,
    progress_dir: f32 = 1,
    progress_bar_overlay: [32]u8 = undefined,
    is_buy_button_clicked: bool = false,

    current_tab: MainMenuTab = .HQ,

    // pass_action: *sg.PassAction = undefined,

    market_view_ui: struct {
        // Current Market ID selected for the trading view
        market_selected_id: usize = 0,
        // State to recorded if a market has been selected
        is_market_selected: bool = false,
        bid_selected: usize = 0,
        ask_selected: usize = 0,
        current_bidding_price: i32 = 0,
        current_asking_price: i32 = 0,
    } = .{},

    resource_view_ui: struct {
        selected_resource_to_add_id: u8 = 0,
        selected_resource_to_add: ResourceTypes = .{ .metal = .Iron },
        // resource_availables: std.EnumMap(MetalTypes, bool) = .initFull(false),
        // mt_availables: std.EnumMap(MetalTypes, bool) = .initFull(false),
    } = .{},
};

pub const MainMenuTab = enum {
    HQ,
    Market,
    Resources,
    Characters,
    Team,
    Adventures,
    Gambits,
};

pub const CurrentSelected = struct {
    id: usize,
    is_selected: bool,
};

//  ██████╗ ██████╗ ██████╗ ███████╗██████╗     ██████╗  ██████╗  ██████╗ ██╗  ██╗
// ██╔═══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗    ██╔══██╗██╔═══██╗██╔═══██╗██║ ██╔╝
// ██║   ██║██████╔╝██║  ██║█████╗  ██████╔╝    ██████╔╝██║   ██║██║   ██║█████╔╝
// ██║   ██║██╔══██╗██║  ██║██╔══╝  ██╔══██╗    ██╔══██╗██║   ██║██║   ██║██╔═██╗
// ╚██████╔╝██║  ██║██████╔╝███████╗██║  ██║    ██████╔╝╚██████╔╝╚██████╔╝██║  ██╗
//  ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═╝    ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝

pub const OrderBook = @import("game_orderbook.zig");

pub const Money = struct {
    pub const Sign = enum { positive, negative };

    value: u32 = 0,
    sign: Sign = .positive,

    pub fn init(value: u32) Money {
        return .{ .value = value };
    }

    pub fn fromI32(value: i32) Money {
        return .{ .value = @abs(value), .sign = Money.getSign(value) };
    }

    pub fn fromFloat(value: f32) Money {
        const v: u32 = @intFromFloat(value * 100);

        return .{ .value = v };
    }

    pub fn toFloat(money: Money) f32 {
        return @divTrunc(money.value, 100);
    }

    pub fn add(money: Money, a: Money) Money {
        const sum: i32 = if (money.sign == .positive) 1 else -1 * money.value + if (a.sign == .positive) 1 else -1 * a.value;
        const sign: Money.Sign = Money.getSign(sum);

        return .{ .value = @intCast(@abs(sum)), .sign = sign };
    }

    pub fn sub(money: Money, a: Money) Money {
        const diff: i32 = if (money.sign == .positive) 1 else -1 * money.value - if (a.sign == .positive) 1 else -1 * a.value;
        const sign: Money.Sign = Money.getSign(diff);

        return .{ .value = @intCast(@abs(diff)), .sign = sign };
    }

    pub fn isPositive(money: Money) bool {
        return money.sign == .positive;
    }

    pub fn isNegative(money: Money) bool {
        return money.sign == .negative;
    }

    fn getSign(x: i32) Sign {
        return if (x >> 31 == 0) .positive else .negative;
    }
};

pub const MarketTrading = struct {
    id: u32,
    book: OrderBook,
    name: []const u8,
    is_available: bool = false,

    pub fn setAvailability(self: *MarketTrading, available: bool) void {
        self.is_available = available;
    }

    pub fn isAvailable(self: *MarketTrading) bool {
        return self.is_available;
    }
};

pub const MarketAsset = struct {
    name: []const u8,
};

pub const MarketData = struct {
    last_order_id: u32 = 0,

    pub fn getNextId(self: *MarketData) u32 {
        self.last_order_id += 1;
        return self.last_order_id;
    }
};

// ███╗   ███╗ █████╗ ██████╗
// ████╗ ████║██╔══██╗██╔══██╗
// ██╔████╔██║███████║██████╔╝
// ██║╚██╔╝██║██╔══██║██╔═══╝
// ██║ ╚═╝ ██║██║  ██║██║
// ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝

pub const OverlayType = enum {
    objective,
    icy,
    difficult,
    hazardous,
    obstacle,
    trap,
    corridor,
};

pub const Coordinate = struct { x: i8, y: i8 };

pub const Overlay = struct {
    type: OverlayType,
};

// pub const Tile = struct {
//     coord: Coordinate,
//     overlay: Overlay,
// };
pub const Tile = struct {
    coord: Coordinate,
    overlay: []const u8,
};

pub const Map = struct {
    map_tiles_offset: []const MapTileOffset,
};

pub const MapTileOffset = struct {
    map_tile: MapTile,
    offset: Coordinate,
};

pub const MapTile = struct {
    tiles: []const Tile,
    name: []const u8,
};

pub const Scenario = struct {
    map: Map,
    name: []const u8,
    id: u8,
};

// ██╗███╗   ██╗██████╗ ██╗   ██╗████████╗███████╗
// ██║████╗  ██║██╔══██╗██║   ██║╚══██╔══╝██╔════╝
// ██║██╔██╗ ██║██████╔╝██║   ██║   ██║   ███████╗
// ██║██║╚██╗██║██╔═══╝ ██║   ██║   ██║   ╚════██║
// ██║██║ ╚████║██║     ╚██████╔╝   ██║   ███████║
// ╚═╝╚═╝  ╚═══╝╚═╝      ╚═════╝    ╚═╝   ╚══════╝

pub const InputEvent = packed struct {
    // code: sapp.Keycode,
    // status: sapp.EventType,
};

pub const InputsState = struct {
    // keys: std.EnumArray(sapp.Keycode, sapp.EventType),
    mouse: MouseState,
};

pub const MouseState = struct {
    cursor: vec.Vec2,
    speed: vec.Vec2,
    scroll: vec.Vec2,
    // buttons: std.EnumArray(sapp.Mousebutton, sapp.EventType),
};

// pub const InputKey = struct {
//     code: sapp.Keycode,
//     state: KeyState,
// };
//
// pub const ButtonState = struct {
//     code: sapp.Mousebutton,
//     state: KeyState,
// };

// pub const KeyState = enum {
//     released,
//     pressed,
// };

// pub const Event = struct {
//     frame_count: u64 = 0,
//     type: EventType = .INVALID,
//     key_code: Keycode = .INVALID,
//     char_code: u32 = 0,
//     key_repeat: bool = false,
//     modifiers: u32 = 0,
//     mouse_button: Mousebutton = .LEFT,
//     mouse_x: f32 = 0.0,
//     mouse_y: f32 = 0.0,
//     mouse_dx: f32 = 0.0,
//     mouse_dy: f32 = 0.0,
//     scroll_x: f32 = 0.0,
//     scroll_y: f32 = 0.0,
//     num_touches: i32 = 0,
//     touches: [8]Touchpoint = [_]Touchpoint{.{}} ** 8,
//     window_width: i32 = 0,
//     window_height: i32 = 0,
//     framebuffer_width: i32 = 0,
//     framebuffer_height: i32 = 0,
// };

// ██████╗ ██╗  ██╗██╗   ██╗███████╗██╗ ██████╗███████╗
// ██╔══██╗██║  ██║╚██╗ ██╔╝██╔════╝██║██╔════╝██╔════╝
// ██████╔╝███████║ ╚████╔╝ ███████╗██║██║     ███████╗
// ██╔═══╝ ██╔══██║  ╚██╔╝  ╚════██║██║██║     ╚════██║
// ██║     ██║  ██║   ██║   ███████║██║╚██████╗███████║
// ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝ ╚═════╝╚══════╝

//  ██████╗ █████╗ ███╗   ███╗███████╗██████╗  █████╗
// ██╔════╝██╔══██╗████╗ ████║██╔════╝██╔══██╗██╔══██╗
// ██║     ███████║██╔████╔██║█████╗  ██████╔╝███████║
// ██║     ██╔══██║██║╚██╔╝██║██╔══╝  ██╔══██╗██╔══██║
// ╚██████╗██║  ██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║
//  ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝

pub const Camera = struct {
    primary: bool = false,
    type: CameraType = .orthographic,
};

pub const CameraType = enum {
    perspective,
    orthographic,
};

pub const OrthographicCamera = CameraMaker(.orthographic);
pub const PerspectiveCamera = CameraMaker(.perspective);

fn CameraMaker(comptime T: CameraType) type {
    return struct {
        const Self = @This();
        type: CameraType = T,
        mvp: Mat4 = Mat4.identity(),
        projection_matrix: Mat4 = Mat4.identity(),
        view_matrix: Mat4 = Mat4.identity(),
        pos: vec.Vec3 = .{ .x = 0, .y = 1.5, .z = 6 },
        look_at: vec.Vec3 = vec.Vec3.zero(),
        direction: vec.Vec3 = vec.Vec3.up(),
        viewport: shape.IRect = shape.IRect.zero(),
        scissor: shape.IRect = .{ .x = 0, .y = 0, .h = 0, .w = 0 },

        pub fn setViewport(self: *Self, vp: shape.IRect) void {
            self.viewport = vp;
            self.offsetScissor(vp.x, vp.y);
            self.computeView();
            self.computeProj();
            self.computeMvp();
        }

        pub fn resetViewport(self: *Self, width: i32, height: i32) void {
            self.viewport = .{ .x = 0, .y = 0, .w = width, .h = height };
            self.resetProj();
            self.resetScissor();
        }

        fn resetProj(self: *Self) void {
            const ratio: f32 = if (self.viewport.h != 0) @as(f32, @floatFromInt(self.viewport.w)) / @as(f32, @floatFromInt(self.viewport.h)) else 1;
            const fov: f32 = std.math.degreesToRadians(70); // We assume the angle view from the eye to the monitor is 45 degrees
            self.projection_matrix = Mat4.proj(fov, ratio, 0.1, 100);
        }

        // fn computeProj(self: *Self, fov: f32, aspect_ratio:f32, near: f32, far: f32) void {
        fn computeProj(self: *Self) void {
            //TODO
            // const ratio: f32 = if (self.viewport.h != 0) @divExact(self.viewport.w, self.viewport.h) else 1;
            // const ratio: f32 = if (self.viewport.h != 0) @as(f32, @floatFromInt(self.viewport.w)) / @as(f32, @floatFromInt(self.viewport.h)) else 1;
            // const fov: f32 = std.math.degreesToRadians(45); // We assume the angle view from the eye to the monitor is 45 degrees
            // self.projection_matrix = Mat4.proj(fov, ratio, 0.1, 100);

            // self.proj = Mat4.proj(fov, ratio, 0.1, 100);
            self.resetProj();
        }

        /// The formula is:
        /// 1. Model: Scale * Rotation * Translation
        /// 2. View: 1) translate the world so that the camera is at the origin; 2) reorient the world so that the camera's forward axis points along Z, right axis points along X, and up axis points along Y. As before, you can come up with these individual transform equations pretty easily and then multiply them together, but it's more efficient to have one formula that builds the entire View Matrix.
        /// 3. Projection:
        ///    Rescale the horizontal space so that -1 is the camera's left edge, and +1 is the camera's right edge. Keep in mind that with a perspective projection, the "edges" are constantly widening as you move farther from the camera, so it's not a simple rescaling.
        ///    Rescale the vertical space so that so that -1 is the camera's bottom edge, and +1 is the camera's top edge (or vice-versa).
        ///    Rescale the depth (Z axis) so that 0 represents being right in front of the camera, and 1 represents the farthest distance that the camera can see. In some cases, it's not 0 to 1 but -1 to +1, like the other axes. Self transformation is usually *extremely* non-linear, with most of the floating-point precision wasted in the tiny space right in front of the camera. Self makes Z-fighting a common problem for far-away surfaces, due to the lack of precision. There has been some work on using a different depth equation to spread out the values more.
        fn computeMvp(self: *Self) void {

            // self.mvp = Mat4.mul(self.projection_matrix, Mat4.mul(self.view_matrix, self.model));
            self.mvp = Mat4.mul(self.projection_matrix, self.view_matrix);
            // log.debug("[Delil.Camera][DEBUG] computeMvp: MVP{}, Projection{},  View{}, Pos{}", .{ self.mvp, self.projection_matrix, self.view_matrix, self.pos });

            // self.mvp = vec.Mat2x3.mul_proj_transform(&self.proj, &self.transform);
        }

        fn computeView(self: *Self) void {
            self.view_matrix = Mat4.lookat(self.pos, self.look_at, self.direction);
        }

        pub fn offsetScissor(self: *Self, x: i32, y: i32) void {
            if (!(self.scissor.w < 0 and self.scissor.h < 0)) {
                self.scissor.x += x - self.viewport.x;
                self.scissor.y += y - self.viewport.y;
            }
        }

        fn resetScissor(self: *Self) void {
            self.scissor = .{ .x = 0, .y = 0, .w = -1, .h = -1 };
        }
    };
}

//  █████╗ ███████╗███████╗███████╗████████╗███████╗
// ██╔══██╗██╔════╝██╔════╝██╔════╝╚══██╔══╝██╔════╝
// ███████║███████╗███████╗█████╗     ██║   ███████╗
// ██╔══██║╚════██║╚════██║██╔══╝     ██║   ╚════██║
// ██║  ██║███████║███████║███████╗   ██║   ███████║
// ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝   ╚══════╝

pub const Tradable = struct {};

pub const Name = struct {
    short: [:0]u8, // dagger_1h
    full: [:0]u8, // Dagger
};

pub const MarketCategory = struct {
    id: usize,
    name: [:0]u8,
    // tag: MarketCategoryTag,
};

pub const SubMarketCategory = struct {
    id: usize,
    name: [:0]u8,
    market_category_id: usize, // ID MarketCategory
    // tag: SubMarketCategoryTag,
};

pub const MarketItem = struct {
    id: usize,
    full_name: [:0]u8,
    short_name: [:0]u8,
    market_sub_category_id: usize,
    description: [:0]u8,
};

pub const BasicResource = struct {
    tag: ResourceTypes,
};

pub const MarketCategoryTag = enum {
    Resources,
    Intermediates,
    Equipments,
    Vehicles,

    pub fn toName(self: MarketCategoryTag) []const u8 {
        return switch (self) {
            else => @tagName(self),
        };
    }
};

pub const SubMarketCategoryTag = enum {
    Metals,
    Ores,
    Woods,
    Electronics,
    MeleeWeapon1H,
    ArmorBody,
    VehiclesPart,

    pub fn toName(self: SubMarketCategoryTag) []const u8 {
        return switch (self) {
            .MeleeWeapon1H => "Melee Weapons - 1 Hand",
            .ArmorBody => "Armors - Body",
            .VehiclesPart => "Parts",
            else => @tagName(self),
        };
    }

    pub fn getCategoryTag(self: SubMarketCategoryTag) MarketCategoryTag {
        return switch (self) {
            .Metals, .Ores, .Woods => .Resources,
            .Electronics => .Intermediates,
            .ArmorBody, .MeleeWeapon1H => .Equipments,
            .VehiclesPart => .Vehicles,
        };
    }
};

pub const ResourceTypeTag = enum {
    metal,
    ore,
    wood,
};

pub const AssetTypeTag = enum {
    res_metal,
    res_ore,
    res_wood,
    manu_electronics,
    equipement_weapon_1h,
    equipement_armor_body,
    vehicles_part,

    pub fn toCategoryName(self: AssetTypeTag) []const u8 {
        var map: std.EnumMap(AssetTypeTag, []const u8) = .initFull("");

        map.put(AssetTypeTag.res_metal, "Resources");
        map.put(AssetTypeTag.res_ore, "Resources");
        map.put(AssetTypeTag.res_wood, "Resources");
        map.put(AssetTypeTag.manu_electronics, "Intermediates");
        map.put(AssetTypeTag.equipement_weapon_1h, "Equipments");
        map.put(AssetTypeTag.equipement_armor_body, "Equipments");
        map.put(AssetTypeTag.vehicles_part, "Vehicles");

        return map.get(self).?;
    }
};

pub const AssetTypes = union(AssetTypeTag) {
    res_metal: MetalTypes,
    res_ore: OreTypes,
    res_wood: WoodTypes,
    manu_electronics: ElectronicsTypes,
    equipement_weapon_1h: Weapon1HTypes,
    equipement_armor_body: BodyArmorTypes,
    vehicles_part: VehiclesPartTypes,

    pub fn getName(self: AssetTypes) []const u8 {
        return switch (self) {
            inline .res_metal => @tagName(self.res_metal),
            inline .res_ore => @tagName(self.res_ore),
            inline .res_wood => @tagName(self.res_wood),
            inline .manu_electronics => @tagName(self.manu_electronics),
            inline .equipement_weapon_1h => @tagName(self.equipement_weapon_1h),
            inline .equipement_armor_body => @tagName(self.equipement_armor_body),
            inline .vehicles_part => @tagName(self.vehicles_part),
        };
    }

    pub fn isEqualTo(self: AssetTypes, asset: AssetTypes) bool {
        return std.meta.eql(self, asset);
    }

    pub fn isResource(self: AssetTypes, res: ResourceTypes) bool {
        return self.isEqualTo(res.toAsset());
    }

    pub fn toResource(self: AssetTypes) Error!ResourceTypes {
        return switch (self) {
            AssetTypeTag.res_metal => ResourceTypes{ .metal = self.res_metal },
            AssetTypeTag.res_wood => ResourceTypes{ .wood = self.res_wood },
            AssetTypeTag.res_ore => ResourceTypes{ .ore = self.res_ore },
            else => Error.IsNotAResource,
        };
    }

    pub fn toCategoryName(self: AssetTypes) []const u8 {
        const tag = @as(AssetTypeTag, self);
        return tag.toCategoryName();
    }
};

pub const ResourceTypes = union(ResourceTypeTag) {
    // electronics: ElectronicsTypes,
    metal: MetalTypes,
    ore: OreTypes,
    wood: WoodTypes,

    pub fn getName(self: ResourceTypes) []const u8 {
        return switch (self) {
            inline .metal => @tagName(self.metal),
            inline .ore => @tagName(self.ore),
            inline .wood => @tagName(self.wood),
        };
        // return @tagName(std.meta.activeTag(self));
    }

    pub fn isEqualTo(self: ResourceTypes, res: ResourceTypes) bool {
        return std.meta.eql(self, res);
    }

    pub fn toAsset(self: ResourceTypes) AssetTypes {
        return switch (self) {
            ResourceTypeTag.metal => .{ .res_metal = self.metal },
            ResourceTypeTag.wood => .{ .res_wood = self.wood },
            ResourceTypeTag.ore => .{ .res_ore = self.ore },
        };
    }
};

pub const Weapon1HTypes = enum(u8) {
    Sword,
    Dagger,
    Knife,
    Stilleto,
    Flail,
    Gloves,
    Katana,
    Ninjeto,

    pub fn getName(self: Weapon1HTypes) []const u8 {
        return @tagName(self);
    }

    pub fn getSubCategoryTag() SubMarketCategoryTag {
        return .MeleeWeapon1H;
    }

    pub fn getCategoryTag() MarketCategoryTag {
        return .Equipements;
    }
};

pub const BodyArmorTypes = enum(u8) {
    Leather,
    Cloth,
    Heavy,

    pub fn getName(self: BodyArmorTypes) []const u8 {
        return @tagName(self);
    }

    pub fn getSubCategoryTag() SubMarketCategoryTag {
        return .ArmorBody;
    }

    pub fn getCategoryTag() MarketCategoryTag {
        return .Equipements;
    }
};

pub const VehiclesPartTypes = enum(u8) {
    Wheels,
    Breaks,

    pub fn getName(self: VehiclesPartTypes) []const u8 {
        return @tagName(self);
    }

    pub fn getSubCategoryTag() SubMarketCategoryTag {
        return .VehiclesPart;
    }

    pub fn getCategoryTag() MarketCategoryTag {
        return .Vehicles;
    }
};
pub const ElectronicsTypes = enum(u8) {
    NanoBattery,
    LogicChip,
    Microprocessor,
    PhotogenicSensor,
    QuantumChip,

    pub fn getName(self: ElectronicsTypes) []const u8 {
        return @tagName(self);
    }

    pub fn getSubCategoryTag() SubMarketCategoryTag {
        return .Electronics;
    }

    pub fn getCategoryTag() MarketCategoryTag {
        return .Intermediates;
    }
};
pub const OreTypes = enum(u8) {
    IronOre,
    CopperOre,
    TinOre,
    ZincOre,
    LeadOre,
    NickelOre,
    CobaltOre,
    SilverOre,
    GoldOre,
    Bauxite,
    UraniumOre,
    TitaniumOre,
    ChromiumOre,
    TungstenOre,
    ManganeseOre,
    PlatinumOres,
    VanadiumOre,
    LithiumOre,
    RareEarthOre,
    MercuryOre,

    pub fn getName(self: OreTypes) []const u8 {
        return @tagName(self);
    }

    pub fn getSubCategoryTag() SubMarketCategoryTag {
        return .Ores;
    }

    pub fn getCategoryTag() MarketCategoryTag {
        return .Resources;
    }
};

pub const WoodTypes = enum(u8) {
    Oak,
    Timber,
    Pine,
    Cedar,
    Birch,
    Maple,
    Ash,
    Teak,
    Walnut,
    Yew,
    Mahogany,
    Ebony,

    pub fn getName(self: WoodTypes) []const u8 {
        return @tagName(self);
    }

    pub fn getSubCategoryTag() SubMarketCategoryTag {
        return .Woods;
    }

    pub fn getCategoryTag() MarketCategoryTag {
        return .Resources;
    }
};

pub const MetalTypes = enum(u8) {
    Iron,
    Steel,
    Copper,
    Bronze,
    Brass,
    Aluminum,
    Titanium,
    Tungsten,
    Nickel,
    Cobalt,
    Chromium,
    Molybdenum,
    Vanadium,
    Magnesium,
    Silver,
    Gold,
    Platinum,
    Palladium,
    Lithium,
    Lead,
    Tin,
    Bismuth,
    Silicon,
    Zinc,
    Osmium,
    Iridium,
    Uramium,
    Ruthenium,

    pub fn getName(self: MetalTypes) []const u8 {
        return @tagName(self);
    }

    pub fn getSubCategoryTag() SubMarketCategoryTag {
        return .Metals;
    }

    pub fn getCategoryTag() MarketCategoryTag {
        return .Resources;
    }
};
