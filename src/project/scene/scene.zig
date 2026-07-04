const std = @import("std");
const Uuid = @import("uuid");
const World = @import("../../ecs/world.zig");

const Scene = @This();

name: []const u8,
guid: Uuid.Uuid,

reg: *World
