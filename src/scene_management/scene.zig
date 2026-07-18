const std = @import("std");
const Uuid = @import("uuid");
const World = @import("../ecs/world.zig");

const Scene = @This();

name: []const u8,
guid: Uuid.Uuid,

reg: *World,

// skybox_guid: Uuid.Uuid,
// skybox_filepath: []const u8,
