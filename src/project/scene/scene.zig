const std = @import("std");
const Uuid = @import("uuid");

const Scene = @This();

name: []const u8,
guid: Uuid.Uuid,
