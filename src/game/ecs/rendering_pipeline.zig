const std = @import("std");
const f = @import("zflecs");

const RenderingPipeline = @This();

pub var BeginSokolPass: f.entity_t = undefined;
pub var BeginImguiPass: f.entity_t = undefined;
pub var RenderImguiPass: f.entity_t = undefined;
pub var EndImguiPass: f.entity_t = undefined;
pub var RenderSokolPass: f.entity_t = undefined;
pub var EndSokolPass: f.entity_t = undefined;

pub fn init(world: *f.world_t) void {
    BeginSokolPass = f.new_w_id(world, f.Phase);
    RenderSokolPass = f.new_w_id(world, f.Phase);
    BeginImguiPass = f.new_w_id(world, f.Phase);
    RenderImguiPass = f.new_w_id(world, f.Phase);
    EndImguiPass = f.new_w_id(world, f.Phase);
    EndSokolPass = f.new_w_id(world, f.Phase);

    f.add_pair(world, BeginSokolPass, f.DependsOn, f.OnStore);
    f.add_pair(world, BeginImguiPass, f.DependsOn, BeginSokolPass);
    f.add_pair(world, RenderImguiPass, f.DependsOn, BeginImguiPass);
    f.add_pair(world, EndImguiPass, f.DependsOn, RenderImguiPass);
    f.add_pair(world, RenderSokolPass, f.DependsOn, EndImguiPass);
    f.add_pair(world, EndSokolPass, f.DependsOn, RenderSokolPass);
}
