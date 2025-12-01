const std = @import("std");
const components = @import("./components.zig");
const Styles = components.Styles;
const sqlite = @import("sqlite");

const sokol = @import("sokol");
const sg = sokol.gfx;

pub const State = struct {
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

    current_tab: components.MainMenuTab = .HQ,

    pass_action: *sg.PassAction = undefined,

    market_view_ui: struct {
        asset_selected: usize = 0,
        categories: std.EnumMap(components.MarketCategoryTag, components.Name) = .initFullWith(
            .{ .Resources = .{ .full = "Resources", .short = "resources" } },
            .{ .Intermediates = .{ .full = "Intermediates", .short = "intermediates" } },
            .{ .Intermediates = .{ .full = "Intermediates", .short = "intermediates" } },
            .{ .Intermediates = .{ .full = "Intermediates", .short = "intermediates" } },
        ),
    } = .{},

    resource_view_ui: struct {
        selected_resource_to_add_id: u8 = 0,
        selected_resource_to_add: components.ResourceTypes = .{ .metal = .Iron },
        // resource_availables: std.EnumMap(MetalTypes, bool) = .initFull(false),
        // mt_availables: std.EnumMap(MetalTypes, bool) = .initFull(false),
    } = .{},
};

pub const UiMarketCategery = struct { tag: components.MarketCategoryTag };
pub const MarketState = struct {
    db: *sqlite.Db,
    categories: [@typeInfo(components.MarketCategoryTag).@"enum".fields.len]struct {
        category: components.MarketCategory,
        children: [@typeInfo(components.SubMarketCategoryTag).@"enum".fields.len]struct {
            sub_category: components.SubMarketCategory,
            // tradables:
        },
    },
    // sub_categories: [@typeInfo(components.SubMarketCategoryTag).@"enum".fields.len]{components.SubMarketCategory,
    pub fn init(db: *sqlite.Db) MarketState {
        return .{ .db = db };
    }
};
