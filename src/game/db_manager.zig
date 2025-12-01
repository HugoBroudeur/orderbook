const ENV = @import("../config.zig");
const Sqlite = @import("sqlite");

const DbManager = @This();

pub const DbError = error{
    NotInitiated,
};

db: Sqlite.Db,
is_init: bool = false,

pub fn init(config: ENV) !DbManager {
    const db = try Sqlite.Db.init(.{
        .mode = Sqlite.Db.Mode{ .File = config.sqlite_game_db_path },
        .open_flags = .{ .write = true },
    });

    return .{
        .db = db,
        .is_init = true,
    };
}

pub fn deinit(self: *DbManager) void {
    self.db.deinit();
    self.is_init = false;
}

pub fn seed_game_db(self: *DbManager) !void {
    if (!self.is_init) {
        return DbError.NotInitiated;
    }

    try self.create_tables();
}

fn create_tables(self: *DbManager) !void {
    try self.db.exec(
        // \\    PRAGMA foreign_keys = ON;
        \\
        \\
        \\------------------------------------------------------------
        \\-- MARKET STRUCTURE
        \\------------------------------------------------------------
        \\
        \\CREATE TABLE IF NOT EXISTS market_category (
        \\    id              INTEGER PRIMARY KEY,
        \\    name            TEXT NOT NULL UNIQUE
        \\);
        \\
        \\CREATE TABLE IF NOT EXISTS market_sub_category (
        \\    id                  INTEGER PRIMARY KEY,
        \\    name                TEXT NOT NULL,
        \\    market_category_id  INTEGER NOT NULL,
        // \\    FOREIGN KEY (market_category_id) REFERENCES market_category(id)
        \\);
        \\
        \\CREATE TABLE IF NOT EXISTS item (
        \\    id                      INTEGER PRIMARY KEY,
        \\    full_name               TEXT NOT NULL,
        \\    short_name              TEXT NOT NULL,
        \\    orderbook_id            INTEGER,
        \\    market_sub_category_id  INTEGER,
        \\    description             TEXT,
        // \\    FOREIGN KEY (market_sub_category_id) REFERENCES market_sub_category(id),
        // \\    FOREIGN KEY (orderbook_id) REFERENCES orderbook(id)
        \\);
        \\
        \\------------------------------------------------------------
        \\-- ORDERBOOK (simple reference)
        \\------------------------------------------------------------
        \\
        \\CREATE TABLE IF NOT EXISTS orderbook (
        \\    id INTEGER PRIMARY KEY
        \\);
        \\
        \\------------------------------------------------------------
        \\-- ITEM TAGS
        \\------------------------------------------------------------
        \\
        \\CREATE TABLE IF NOT EXISTS tag (
        \\    id          INTEGER PRIMARY KEY,
        \\    full_name   TEXT NOT NULL,
        \\    short_name  TEXT NOT NULL
        \\);
        \\
        \\CREATE TABLE IF NOT EXISTS item_tag (
        \\    item_id     INTEGER NOT NULL,
        \\    tag_id      INTEGER NOT NULL,
        \\    PRIMARY KEY (item_id, tag_id),
        // \\    FOREIGN KEY (item_id) REFERENCES item(id),
        // \\    FOREIGN KEY (tag_id)  REFERENCES tag(id)
        \\);
        \\
        \\------------------------------------------------------------
        \\-- CONVERTERS (production chains)
        \\------------------------------------------------------------
        \\
        \\CREATE TABLE IF NOT EXISTS converter_ratio (
        \\    id          INTEGER PRIMARY KEY,
        \\    name        TEXT NOT NULL,        -- e.g. "smelting efficiency"
        \\    speed_rate  REAL NOT NULL         -- multiplier
        \\);
        \\
        \\-- io_type: 0=input, 1=output
        \\CREATE TABLE IF NOT EXISTS converter (
        \\    id                  INTEGER PRIMARY KEY,
        \\    converter_ratio_id  INTEGER NOT NULL,
        \\    ratio               REAL NOT NULL,  -- e.g. 2.5 units per second
        \\    item_id             INTEGER NOT NULL,
        \\    io_type             INTEGER NOT NULL,
        // \\    FOREIGN KEY (converter_ratio_id) REFERENCES converter_ratio(id),
        // \\    FOREIGN KEY (item_id) REFERENCES item(id)
        \\);
        \\
        \\------------------------------------------------------------
        \\-- SKILLS & PROGRESSION
        \\------------------------------------------------------------
        \\
        \\CREATE TABLE IF NOT EXISTS skill_progression (
        \\    id          INTEGER PRIMARY KEY,
        \\    name        TEXT NOT NULL,     -- very easy / easy / medium / hard
        \\    ratio       REAL NOT NULL,
        \\    base_xp     INTEGER NOT NULL
        \\);
        \\
        \\CREATE TABLE IF NOT EXISTS skill (
        \\    id                      INTEGER PRIMARY KEY,
        \\    full_name               TEXT NOT NULL,
        \\    short_name              TEXT NOT NULL,
        \\    description             TEXT,
        \\    skill_progression_id    INTEGER NOT NULL,
        // \\    FOREIGN KEY (skill_progression_id) REFERENCES skill_progression(id)
        \\);
        \\
        \\------------------------------------------------------------
        \\-- TRAITS & EFFECTS
        \\------------------------------------------------------------
        \\
        \\CREATE TABLE IF NOT EXISTS trait_effect (
        \\    id          INTEGER PRIMARY KEY,
        \\    name        TEXT NOT NULL,
        \\    skill_id    INTEGER,
        \\    modifier    REAL NOT NULL,
        // \\    FOREIGN KEY (skill_id) REFERENCES skill(id)
        \\);
        \\
        \\CREATE TABLE IF NOT EXISTS trait (
        \\    id                  INTEGER PRIMARY KEY,
        \\    name                TEXT NOT NULL,
        \\    description         TEXT,
        \\    positive_effect_id  INTEGER,
        \\    negative_effect_id  INTEGER,
        // \\    FOREIGN KEY (positive_effect_id) REFERENCES trait_effect(id),
        // \\    FOREIGN KEY (negative_effect_id) REFERENCES trait_effect(id)
        \\);
        \\
        \\------------------------------------------------------------
        \\-- GAMBIT SYSTEM (AI combat scripting)
        \\------------------------------------------------------------
        \\
        \\CREATE TABLE IF NOT EXISTS stat_type (
        \\    id          INTEGER PRIMARY KEY,
        \\    name        TEXT NOT NULL UNIQUE
        \\);
        \\
        \\CREATE TABLE IF NOT EXISTS gambit_condition (
        \\    id              INTEGER PRIMARY KEY,
        \\    full_name       TEXT NOT NULL,
        \\    short_name      TEXT NOT NULL,
        \\    threshold       REAL NOT NULL,
        \\    sign            TEXT NOT NULL,          -- >, <, ==, etc.
        \\    stat_type_id    INTEGER NOT NULL,
        // \\    FOREIGN KEY (stat_type_id) REFERENCES stat_type(id)
        \\);
        \\
        \\-- enemy/ally: 0=enemy,1=ally
        \\CREATE TABLE IF NOT EXISTS gambit_target (
        \\    id              INTEGER PRIMARY KEY,
        \\    full_name       TEXT NOT NULL,
        \\    short_name      TEXT NOT NULL,
        \\    target_side     INTEGER NOT NULL,   -- enemy/ally
        \\    distance        REAL NOT NULL,
        \\    stat_type_id    INTEGER NOT NULL,
        // \\    FOREIGN KEY (stat_type_id) REFERENCES stat_type(id)
        \\);
        \\
        \\CREATE TABLE IF NOT EXISTS gambit (
        \\    id                  INTEGER PRIMARY KEY,
        \\    full_name           TEXT NOT NULL,
        \\    short_name          TEXT NOT NULL,
        \\    description         TEXT,
        \\    gambit_condition_id INTEGER NOT NULL,
        \\    gambit_target_id    INTEGER NOT NULL,
        // \\    FOREIGN KEY (gambit_condition_id) REFERENCES gambit_condition(id),
        // \\    FOREIGN KEY (gambit_target_id) REFERENCES gambit_target(id)
        \\);
        \\
        \\------------------------------------------------------------
        \\-- PLAYER DATA
        \\------------------------------------------------------------
        \\
        \\CREATE TABLE IF NOT EXISTS player (
        \\    id INTEGER PRIMARY KEY
        \\);
        \\
        \\-- INVENTORY
        \\CREATE TABLE IF NOT EXISTS inventory (
        \\    player_id   INTEGER NOT NULL,
        \\    item_id     INTEGER NOT NULL,
        \\    quantity    INTEGER NOT NULL,
        \\    PRIMARY KEY (player_id, item_id),
        // \\    FOREIGN KEY (player_id) REFERENCES player(id),
        // \\    FOREIGN KEY (item_id)   REFERENCES item(id)
        \\);
        \\
        \\-- PLAYER BUILDINGS
        \\CREATE TABLE IF NOT EXISTS player_building (
        \\    id          INTEGER PRIMARY KEY,
        \\    player_id   INTEGER NOT NULL,
        \\    building_type TEXT NOT NULL,
        // \\    FOREIGN KEY (player_id) REFERENCES player(id)
        \\);
        \\
        \\-- PLAYER TECHNOLOGIES
        \\CREATE TABLE IF NOT EXISTS player_technology (
        \\    player_id       INTEGER NOT NULL,
        \\    technology_name TEXT NOT NULL,
        \\    PRIMARY KEY (player_id, technology_name),
        // \\    FOREIGN KEY (player_id) REFERENCES player(id)
        \\);
        \\
        \\-- PLAYER TRAITS
        \\CREATE TABLE IF NOT EXISTS player_trait (
        \\    player_id   INTEGER NOT NULL,
        \\    trait_id    INTEGER NOT NULL,
        \\    PRIMARY KEY (player_id, trait_id),
        // \\    FOREIGN KEY (player_id) REFERENCES player(id),
        // \\    FOREIGN KEY (trait_id)  REFERENCES trait(id)
        \\);
        \\
        \\-- PLAYER SKILLS
        \\CREATE TABLE IF NOT EXISTS player_skill (
        \\    player_id       INTEGER NOT NULL,
        \\    skill_id        INTEGER NOT NULL,
        \\    level           INTEGER NOT NULL,
        \\    current_xp      INTEGER NOT NULL,
        \\    next_level_xp   INTEGER NOT NULL,
        \\    PRIMARY KEY (player_id, skill_id),
        // \\    FOREIGN KEY (player_id) REFERENCES player(id),
        // \\    FOREIGN KEY (skill_id)  REFERENCES skill(id)
        \\);
    , .{}, .{});
}
