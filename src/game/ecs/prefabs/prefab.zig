pub fn setup_game(allocator: std.mem.Allocator, es: *Ecs.Entities, cb: *Ecs.CmdBuf) !void {
    // const pass_action: sg.PassAction = .{ .colors = blk: {
    //     var c: [8]sg.ColorAttachmentAction = @splat(std.mem.zeroes(sg.ColorAttachmentAction));
    //     c[0] = .{
    //         .load_action = .CLEAR,
    //         .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    //     };
    //     break :blk c;
    // } };

    // try seed_resources_and_books(allocator, cb);

    var category_map = create_market_category_entity_map(cb);
    var sub_category_map = create_market_sub_category_entity_map(cb, &category_map);

    // try create_tradables(cb, allocator, &sub_category_map);
    _ = allocator;
    _ = &sub_category_map;

    Ecs.create_single_component_entity(cb, Ecs.components.Event.UnlockAssetEvent, .{ .asset = .{ .res_metal = .Iron } });
    Ecs.create_single_component_entity(cb, Ecs.components.Event.UnlockAssetEvent, .{ .asset = .{ .res_ore = .IronOre } });

    Ecs.CmdBuf.Exec.immediate(es, cb);
}

fn create_market_categories(cb: *Ecs.CmdBuf, category: Ecs.components.MarketCategoryTag, sub_category: Ecs.components.SubMarketCategoryTag) Ecs.Entity {
    const entity: Ecs.Entity = .reserve(cb);
    _ = entity.add(cb, Ecs.components.MarketCategory, .{ .tag = category });
    _ = entity.add(cb, Ecs.components.SubMarketCategory, .{ .tag = sub_category });

    return entity;
}

fn create_market_category_entity_map(
    cb: *Ecs.CmdBuf,
) std.EnumMap(Ecs.components.MarketCategoryTag, ?Ecs.Entity) {
    var map: std.EnumMap(Ecs.components.MarketCategoryTag, ?Ecs.Entity) = .initFull(null);

    for (std.enums.values(Ecs.components.MarketCategoryTag)) |tag| {
        const entity: Ecs.Entity = .reserve(cb);
        // _ = entity.add(cb, Ecs.components.MarketCategory, .{ .tag = tag });
        map.put(tag, entity);
    }

    return map;
}

fn create_market_sub_category_entity_map(
    cb: *Ecs.CmdBuf,
    category_map: *std.EnumMap(Ecs.components.MarketCategoryTag, ?Ecs.Entity),
) std.EnumMap(Ecs.components.SubMarketCategoryTag, ?Ecs.Entity) {
    var map: std.EnumMap(Ecs.components.SubMarketCategoryTag, ?Ecs.Entity) = .initFull(null);

    for (std.enums.values(Ecs.components.SubMarketCategoryTag)) |tag| {
        const entity: Ecs.Entity = .reserve(cb);
        // _ = entity.add(cb, Ecs.components.SubMarketCategory, .{ .tag = tag });
        map.put(tag, entity);

        _ = Ecs.CmdBuf.ext(cb, Ecs.Node.SetParent, .{
            .child = entity,
            .parent = category_map.get(tag.getCategoryTag()).?.?.toOptional(),
        });
    }
    return map;
}

fn create_tradables(
    cb: *Ecs.CmdBuf,
    allocator: std.mem.Allocator,
    sub_category_map: *std.EnumMap(Ecs.components.SubMarketCategoryTag, ?Ecs.Entity),
) !void {
    // Ores
    for (std.enums.values(Ecs.components.OreTypes)) |tag| {
        // const book = try Ecs.components.OrderBook.init(allocator, 1);
        const entity: Ecs.Entity = .reserve(cb);
        _ = entity.add(cb, Ecs.components.Tradable, .{});
        _ = entity.add(cb, Ecs.components.Name, .{ .short = tag.getName(), .full = try toTitleCase(allocator, tag.getName()) });
        // _ = entity.add(cb, Ecs.components.MarketTrading, .{ .book = book });

        _ = Ecs.CmdBuf.ext(cb, Ecs.Node.SetParent, .{
            .child = entity,
            .parent = sub_category_map.get(.Ores).?.?.toOptional(),
        });
    }

    // Woods
    for (std.enums.values(Ecs.components.WoodTypes)) |tag| {
        // const book = try Ecs.components.OrderBook.init(allocator, 1);
        const entity: Ecs.Entity = .reserve(cb);
        _ = entity.add(cb, Ecs.components.Tradable, .{});
        _ = entity.add(cb, Ecs.components.Name, .{ .short = tag.getName(), .full = try toTitleCase(allocator, tag.getName()) });
        // _ = entity.add(cb, Ecs.components.MarketTrading, .{ .book = book });

        _ = Ecs.CmdBuf.ext(cb, Ecs.Node.SetParent, .{
            .child = entity,
            .parent = sub_category_map.get(.Woods).?.?.toOptional(),
        });
    }

    // Metals
    for (std.enums.values(Ecs.components.MetalTypes)) |tag| {
        // const book = try Ecs.components.OrderBook.init(allocator, 1);
        const entity: Ecs.Entity = .reserve(cb);
        _ = entity.add(cb, Ecs.components.Tradable, .{});
        _ = entity.add(cb, Ecs.components.Name, .{ .short = tag.getName(), .full = try toTitleCase(allocator, tag.getName()) });
        // _ = entity.add(cb, Ecs.components.MarketTrading, .{ .book = book });

        _ = Ecs.CmdBuf.ext(cb, Ecs.Node.SetParent, .{
            .child = entity,
            .parent = sub_category_map.get(.Metals).?.?.toOptional(),
        });
    }
}

// fn create_base_tradable_entity(allocator: std.mem.Allocator, cb: *Ecs.CmdBuf, category: Ecs.components.MarketCategoryTag, sub_category: Ecs.components.SubMarketCategoryTag) !Ecs.Entity {
//     const book = try Ecs.components.OrderBook.init(allocator, 1);
//     const entity: Ecs.Entity = .reserve(cb);
//     _ = entity.add(cb, Ecs.components.Tradable, .{});
//     // _ = entity.add(cb, Ecs.components.Name, .{ .short = asset.name, .full = try toTitleCase(allocator, asset.name) });
//     _ = entity.add(cb, Ecs.components.MarketTrading, .{ .book = book, .is_available = true });
//
//     return entity;
// }

fn seed_resources_and_books(allocator: std.mem.Allocator, cb: *Ecs.CmdBuf) !void {
    {
        var i: u8 = 0;
        var j: u8 = 0;

        for (std.enums.values(Ecs.components.MarketCategoryTag)) |tag| {
            // const asset_value = @unionInit(Ecs.components.AssetTypes, asset.name, @enumFromInt(asset.type));
            const e: Ecs.Entity = .reserve(cb);
            _ = e.add(cb, Ecs.components.MarketCategory, .{ .tag = tag });
        }

        cb.ext(Ecs.Node.SetParent, .{});
        inline for (@typeInfo(Ecs.components.AssetTypes).@"union".fields) |asset| {
            i += 1;
            inline for (@typeInfo(asset.type).@"enum".fields) |f| {
                j += 1;
                const value = @unionInit(Ecs.components.AssetTypes, asset.name, @enumFromInt(f.value));

                const book = try Ecs.components.OrderBook.init(allocator, 1);
                const entity: Ecs.Entity = .reserve(cb);
                _ = entity.add(cb, Ecs.components.Tradable, .{});
                _ = entity.add(cb, Ecs.components.Name, .{ .short = asset.name, .full = try toTitleCase(allocator, asset.name) });
                // _ = entity.add(cb, Ecs.components.MarketCategory, .{ .name = value.toCategoryName(), .ordinal = i });
                _ = entity.add(cb, Ecs.components.SubMarketCategoryTag, .{ .name = asset.name, .ordinal = j - i });
                _ = entity.add(cb, Ecs.components.MarketTrading, .{ .book = book, .asset = value });

                // _ = entity.add(cb, Ecs.components.CurrentSelected, .{ .id = i, .is_selected = false });
                // _ = entity.add(cb, Ecs.components.Locked, .{});

                // std.log.info("[PREFAB] {s} {s} {} {}", .{ asset.name, f.name, asset.type, value });
                switch (asset.type) {
                    Ecs.components.WoodTypes, Ecs.components.OreTypes, Ecs.components.MetalTypes => {
                        const res: Ecs.Entity = .reserve(cb);
                        _ = res.add(cb, Ecs.components.Resource, .{ .name = f.name, .type = value.toResource() catch unreachable });
                        _ = res.add(cb, Ecs.components.Locked, .{});
                    },
                    else => {},
                }
            }
        }
    }
}

/// Converts snake_case, kebab-case or camelCase into "Title Case"
pub fn toTitleCase(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, input.len);

    var i: usize = 0;
    while (i < input.len) {
        const c = input[i];

        // Case 1: word separators -> insert space
        if (c == '_' or c == '-') {
            try buf.append(allocator, ' ');
            i += 1;
            continue;
        }

        // Case 2: camelCase/PascalCase boundary (uppercase inside a word)
        if (std.ascii.isUpper(c) and buf.items.len != 0) {
            // Insert space before uppercase letter if previous was lowercase
            const prev = buf.items[buf.items.len - 1];
            if (std.ascii.isLower(prev)) {
                try buf.append(allocator, ' ');
            }
        }

        // Capitalize the first letter of each word
        if (buf.items.len == 0 or buf.items[buf.items.len - 1] == ' ') {
            try buf.append(allocator, std.ascii.toUpper(c));
        } else {
            try buf.append(allocator, std.ascii.toLower(c));
        }

        i += 1;
    }

    return buf.toOwnedSlice(allocator);
}

const std = @import("std");
const sdl = @import("sdl3");
const Ecs = @import("../ecs.zig");
