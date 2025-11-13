// Interface definition for a system, using Vtable
const zecs = @import("zecs");
const std = @import("std");

const System = @This();

ptr: *anyopaque,
vtable: *const VTable,

// pub const VTable = struct {
/// Return a pointer to `len` bytes with specified `alignment`, or return
/// `null` indicating the allocation failed.
///
/// `ret_addr` is optionally provided as the first return address of the
/// allocation call stack. If the value is `0` it means no return address
/// has been provided.
// alloc: *const fn (*anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8,
pub const VTable = struct {
    // onSetup: *const fn (self: *System, reg: *zecs.Registry) void,
    // onFrame: *const fn (self: *System, reg: *zecs.Registry) void,
    onSetup: *const fn (*anyopaque, reg: *zecs.Registry) void = default,
    onFrame: *const fn (*anyopaque, reg: *zecs.Registry) void = default,
    // onRender: *const fn (*anyopaque, reg: *zecs.Registry, previous_pass: *delil_pass.RenderPass) *delil_pass.RenderPass = default_render,
    onRender: *const fn (*anyopaque, reg: *zecs.Registry) void = default_render,
    once: *const fn (*anyopaque, reg: *zecs.Registry) void = default,
};

pub fn onSetup(self: *System, reg: *zecs.Registry) void {
    return self.vtable.onSetup(self, reg);
}

pub fn onFrame(self: *System, reg: *zecs.Registry) void {
    return self.vtable.onFrame(self, reg);
}

pub fn once(self: *System, reg: *zecs.Registry) void {
    return self.vtable.once(self, reg);
}

// pub fn onRender(self: *System, reg: *zecs.Registry, previous_pass: *delil_pass.RenderPass) *delil_pass.RenderPass {
//     return self.vtable.onRender(self, reg, previous_pass);
// }

pub fn onRender(self: *System, reg: *zecs.Registry) void {
    return self.vtable.onRender(self, reg);
}

fn default(ctx: *anyopaque, reg: *zecs.Registry) void {
    _ = &ctx;
    _ = &reg;
}

// fn default_render(ctx: *anyopaque, reg: *zecs.Registry, previous_pass: *delil_pass.RenderPass) *delil_pass.RenderPass {
//     _ = &ctx;
//     _ = &reg;
//     return previous_pass;
// }

fn default_render(ctx: *anyopaque, reg: *zecs.Registry) void {
    _ = &ctx;
    _ = &reg;
}

// Implementation look like:
// const MySystem = struct {
//     pub fn system(self: *MySystem) System {
//         return .{
//             .ptr = self,
//             .vtable = &.{
//                 .register = register,
//                 .do = do,
//             },
//         };
//     }
//
//     fn register(ctx: *anyopaque, reg: *zecs.Registry) void {
//         const self: *MySystem = @ptrCast(@alignCast(ctx));
//         _ = reg;
//         _ = self;
//     }
//
//     fn do(ctx: *anyopaque, reg: *zecs.Registry) void {
//         const self: *MySystem = @ptrCast(@alignCast(ctx));
//         _ = reg;
//         _ = self;
//     }
// };
