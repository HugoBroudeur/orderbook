const std = @import("std");
const Components = @import("components/components.zig");
const DbManager = @import("../db_manager.zig");
const MarketManager = @This();

allocator: std.mem.Allocator,
db_manager: *DbManager,
market_categories: std.AutoArrayHashMap(usize, Components.MarketCategory),
market_sub_categories: std.AutoArrayHashMap(usize, Components.SubMarketCategory),
market_items: std.AutoArrayHashMap(usize, Components.MarketItem),

pub fn init(allocator: std.mem.Allocator, db_manager: *DbManager) MarketManager {
    return .{
        .allocator = allocator,
        .db_manager = db_manager,
        .market_categories = .init(allocator),
        .market_sub_categories = .init(allocator),
        .market_items = .init(allocator),
    };
}

pub fn deinit(self: *MarketManager) void {
    self.market_categories.deinit();
    self.market_sub_categories.deinit();
    self.market_items.deinit();
}

pub fn on_load(self: *MarketManager) !void {
    try self.reset_items();
    try self.seed_market_category();
    try self.seed_market_sub_category();
    try self.seed_market_equipements();
    try self.seed_market_vehicles();
    try self.seed_market_intermediates();
    try self.seed_market_resources();
    try self.fetch_market_categories();
    try self.fetch_market_sub_categories();
    try self.fetch_market_items();
}

fn reset_items(self: *MarketManager) !void {
    try self.db_manager.db.exec("DELETE FROM item", .{}, .{});
}

fn fetch_market_categories(self: *MarketManager) !void {
    var tx = try self.db_manager.db.prepare("SELECT * FROM market_category");
    defer tx.deinit();

    const market_categories = try tx.all(Components.MarketCategory, self.allocator, .{}, .{});
    for (market_categories) |mc| {
        try self.market_categories.put(mc.id, mc);
    }
}

fn fetch_market_sub_categories(self: *MarketManager) !void {
    var tx = try self.db_manager.db.prepare("SELECT * FROM market_sub_category");
    defer tx.deinit();

    const market_sub_categories = try tx.all(Components.SubMarketCategory, self.allocator, .{}, .{});
    for (market_sub_categories) |msc| {
        try self.market_sub_categories.put(msc.id, msc);
    }
}

fn fetch_market_items(self: *MarketManager) !void {
    var tx = try self.db_manager.db.prepare("SELECT * FROM item");
    defer tx.deinit();

    const market_items = try tx.all(Components.MarketItem, self.allocator, .{}, .{});
    for (market_items) |im| {
        try self.market_items.put(im.id, im);
    }
}

fn seed_market_category(self: *MarketManager) !void {
    try self.db_manager.db.exec(
        \\  INSERT OR IGNORE INTO market_category(id, name) VALUES
        \\  (1, 'Equipements'),
        \\  (2, 'Vehicles'),
        \\  (3, 'Intermediates'),
        \\  (4, 'Resources')
    , .{}, .{});
}

fn seed_market_sub_category(self: *MarketManager) !void {
    try self.db_manager.db.exec(
        \\  INSERT OR IGNORE INTO market_sub_category(id, name, market_category_id) VALUES
        \\  (1, 'Melee Weapons - 1 Hand', 1),
        \\  (2, 'Armors - Body', 1),
        \\  (3, 'Vehicles - Part', 2),
        \\  (4, 'Electronics', 3),
        \\  (5, 'Ores', 4),
        \\  (6, 'Woods', 4),
        \\  (7, 'Metals', 4)
    , .{}, .{});
}

fn seed_market_equipements(self: *MarketManager) !void {
    try self.db_manager.db.exec(
        \\    INSERT INTO item (full_name, short_name, market_sub_category_id, description) VALUES
        \\    ('Sword', 'sword', 1, "A sword that slashes"),
        \\    ('Dagger', 'dagger',  1, "A dagger"),
        \\    ('Knife', 'knife',  1, NULL),
        \\    ('Stilleto', 'stilleto',  1, NULL),
        \\    ('Flail', 'flail',  1, NULL),
        \\    ('Gloves', 'gloves',  1, NULL),
        \\    ('Katana', 'katana',  1, NULL),
        \\    ('Ninjeto', 'ninjeto',  1, NULL)
    , .{}, .{});

    try self.db_manager.db.exec(
        \\    INSERT INTO item (full_name, short_name, market_sub_category_id, description) VALUES
        \\    ('Leather', 'leather', 2, NULL),
        \\    ('Cloth', 'cloth', 2, NULL),
        \\    ('Heavy', 'heavy', 2, NULL)
    , .{}, .{});
}

fn seed_market_vehicles(self: *MarketManager) !void {
    try self.db_manager.db.exec(
        \\    INSERT INTO item (full_name, short_name, market_sub_category_id, description) VALUES
        \\    ('Wheels', 'wheels', 3, NULL),
        \\    ('Breaks', 'breaks', 3, NULL)
    , .{}, .{});
}

fn seed_market_resources(self: *MarketManager) !void {
    try self.db_manager.db.exec(
        \\    INSERT INTO item (full_name, short_name, market_sub_category_id, description) VALUES
        \\    ('Iron Ore', 'iron-ore', 5, NULL),
        \\    ('Copper Ore', 'copper-ore', 5, NULL),
        \\    ('Tin Ore', 'tin-ore', 5, NULL),
        \\    ('Zinc Ore', 'zinc-ore', 5, NULL),
        \\    ('Lead Ore', 'lead-ore', 5, NULL),
        \\    ('Nickel Ore', 'nickel-ore', 5, NULL),
        \\    ('Cobalt Ore', 'cobalt-ore', 5, NULL),
        \\    ('Silver Ore', 'silver-ore', 5, NULL),
        \\    ('Gold Ore', 'gold-ore', 5, NULL),
        \\    ('Bauxite', 'bauxite', 5, NULL),
        \\    ('Uranium Ore', 'uranium-ore', 5, NULL),
        \\    ('Titanium Ore', 'titanium-ore', 5, NULL),
        \\    ('Chromium Ore', 'chromium-ore', 5, NULL),
        \\    ('Tungsten Ore', 'tungsten-ore', 5, NULL),
        \\    ('Manganese Ore', 'manganese-ore', 5, NULL),
        \\    ('Platinum Ore', 'platinum-ore', 5, NULL),
        \\    ('Vanadium Ore', 'vanadium-ore', 5, NULL),
        \\    ('Lithium Ore', 'lithium-ore', 5, NULL),
        \\    ('Rare Earth Ore', 'rare-earth-ore', 5, NULL),
        \\    ('Mercury Ore', 'mercury-ore', 5, NULL)
    , .{}, .{});

    try self.db_manager.db.exec(
        \\    INSERT INTO item (full_name, short_name, market_sub_category_id, description) VALUES
        \\    ('Oak', 'oak', 6, NULL),
        \\    ('Timber', 'timber', 6, NULL),
        \\    ('Pine', 'pine', 6, NULL),
        \\    ('Cedar', 'cedar', 6, NULL),
        \\    ('Birch', 'birch', 6, NULL),
        \\    ('Maple', 'maple', 6, NULL),
        \\    ('Ash', 'ash', 6, NULL),
        \\    ('Teak', 'teak', 6, NULL),
        \\    ('Walnut', 'walnut', 6, NULL),
        \\    ('Yew', 'yew', 6, NULL),
        \\    ('Mahogany', 'mahogany', 6, NULL),
        \\    ('Ebony', 'ebony', 6, NULL)
    , .{}, .{});

    try self.db_manager.db.exec(
        \\    INSERT INTO item (full_name, short_name, market_sub_category_id, description) VALUES
        \\    ('Iron', 'iron', 7, NULL),
        \\    ('Steel', 'steel', 7, NULL),
        \\    ('Copper', 'copper', 7, NULL),
        \\    ('Bronze', 'bronze', 7, NULL),
        \\    ('Brass', 'brass', 7, NULL),
        \\    ('Aluminum', 'aluminum', 7, NULL),
        \\    ('Titanium', 'titanium', 7, NULL),
        \\    ('Tungsten', 'tungsten', 7, NULL),
        \\    ('Nickel', 'nickel', 7, NULL),
        \\    ('Cobalt', 'cobalt', 7, NULL),
        \\    ('Chromium', 'chromium', 7, NULL),
        \\    ('Molybdenum', 'molybdenum', 7, NULL),
        \\    ('Vanadium', 'vanadium', 7, NULL),
        \\    ('Magnesium', 'magnesium', 7, NULL),
        \\    ('Silver', 'silver', 7, NULL),
        \\    ('Gold', 'gold', 7, NULL)
    , .{}, .{});

    try self.db_manager.db.exec(
        \\    INSERT INTO item (full_name, short_name, market_sub_category_id, description) VALUES
        \\    ('Platinum', 'platinum', 7, NULL),
        \\    ('Palladium', 'palladium', 7, NULL),
        \\    ('Lithium', 'lithium', 7, NULL),
        \\    ('Lead', 'lead', 7, NULL),
        \\    ('Tin', 'tin', 7, NULL),
        \\    ('Bismuth', 'bismuth', 7, NULL),
        \\    ('Silicon', 'silicon', 7, NULL),
        \\    ('Zinc', 'zinc', 7, NULL),
        \\    ('Osmium', 'osmium', 7, NULL),
        \\    ('Iridium', 'iridium', 7, NULL),
        \\    ('Uramium', 'uramium', 7, NULL),
        \\    ('Ruthenium', 'ruthenium', 7, NULL)
    , .{}, .{});
}

fn seed_market_intermediates(self: *MarketManager) !void {
    try self.db_manager.db.exec(
        \\    INSERT INTO item (full_name, short_name, market_sub_category_id, description) VALUES
        \\    ('Nano Battery', 'nano-battery', 4, NULL),
        \\    ('Logic Chip', 'logic-chip', 4, NULL),
        \\    ('Micro-processor', 'micro-processor', 4, NULL),
        \\    ('Photogenic Sensor', 'photogenic-sensor', 4, NULL),
        \\    ('Quantum Chip', 'quantum-chip', 4, NULL)
    , .{}, .{});
}
