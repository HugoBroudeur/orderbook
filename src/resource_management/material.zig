const std = @import("std");
const log = std.log.scoped(.resource_material);

const Config = @import("../config.zig");
const Engine = @import("../engine/vulkan/engine.zig");
const AssetManager = @import("manager.zig");
const Resource = @import("resource.zig").Resource;
const ResourceId = @import("resource.zig").ResourceId;
const Gltf = @import("zgltf").Gltf;

const materials = @import("../engine/graphics/materials.zig");
pub const MaterialInstance = materials.MaterialInstance;
pub const MaterialPass = materials.MaterialPass;
const MaterialConstants = materials.PBRMaterial.MaterialConstants;

/// Implementation of the Vulkan Material Resource that is managed by the Resource manager.
///
/// A Material owns no GPU buffer of its own: it registers a slot on the
/// shared bindless material buffer (engine.descriptor.pbr_material_buffer)
/// and uploads its constants at the offset that slot gives it. Everything
/// anything needs afterwards is `data` (pipeline + buffer slot + index).
pub const Material = struct {
    id: ResourceId,
    name: []const u8,
    source: Source,

    data: MaterialInstance = undefined,

    pub const Source = union(enum) {
        gltf_material: struct {
            gltf: *Gltf,
            material_idx: u32,
            /// glTF texture index -> bindless texture slot, resolved by the
            /// texture pass in loadGLTFAsset before any material loads.
            bindless_slots: []const u32,
        },
    };

    pub fn interface(self: *Material) Resource {
        return Resource.interface(self);
    }

    pub fn init(id: ResourceId, name: []const u8, source: Source) Material {
        return .{
            .id = id,
            .name = name,
            .source = source,
        };
    }

    pub fn getId(self: *const Material) ResourceId {
        return self.id;
    }

    pub fn load(self: *Material, mgr: *AssetManager) !void {
        const engine = mgr.engine;
        const s = self.source.gltf_material;
        const gltf_material = s.gltf.data.materials[s.material_idx];

        const constants: MaterialConstants = .{
            .color_factors = gltf_material.metallic_roughness.base_color_factor,
            .metal_rough_factors = .{ gltf_material.metallic_roughness.metallic_factor, gltf_material.metallic_roughness.roughness_factor, 0, 0 },
            .emissive_factor = .{ gltf_material.emissive_factor[0], gltf_material.emissive_factor[1], gltf_material.emissive_factor[2], gltf_material.emissive_strength },
            .transmission_factor = gltf_material.transmission_factor,
            .color_tex_id = resolveTexSlot(s.bindless_slots, gltf_material.metallic_roughness.base_color_texture),
            .metal_rough_tex_id = resolveTexSlot(s.bindless_slots, gltf_material.metallic_roughness.metallic_roughness_texture),
            .normal_tex_id = resolveTexSlot(s.bindless_slots, gltf_material.normal_texture),
            .occlusion_tex_id = resolveTexSlot(s.bindless_slots, gltf_material.occlusion_texture),
            .emissive_tex_id = resolveTexSlot(s.bindless_slots, gltf_material.emissive_texture),
            .transmission_tex_id = resolveTexSlot(s.bindless_slots, gltf_material.transmission_texture),
            .cube_tex_id = 0,
        };

        const pass_type: MaterialPass = if (gltf_material.alpha_mode == .blend) .Transparent else .MainColor;

        const material_idx = try engine.descriptor.registerMaterial();
        self.data = engine.pbr_material.createMaterialInstance(pass_type, material_idx, engine.descriptor.pbr_material_buffer_slot);

        if (Config.log.mesh) {
            log.info("[Material.load] '{s}' pass={} slot={d} color_tex={d}", .{ self.name, pass_type, material_idx, constants.color_tex_id });
        }

        try self.upload(engine, constants);
    }

    /// Copy the constants into the shared material buffer at the offset the
    /// registered slot id gives us. The registry owns capacity/growth;
    /// writing the bytes into a reserved slot is the resource's own job.
    fn upload(self: *Material, engine: *Engine, constants: MaterialConstants) !void {
        try engine.descriptor.pbr_material_buffer.copyInto(
            std.mem.asBytes(&constants),
            self.data.material_idx * @sizeOf(MaterialConstants),
        );
    }

    pub fn unload(self: *Material, mgr: *AssetManager) void {
        _ = self;
        _ = mgr;
        // The shared material buffer is a bump allocator: slots are not
        // reclaimed (same accepted limitation as bindless texture slots).
    }

    fn resolveTexSlot(bindless_slots: []const u32, tex_info: anytype) u32 {
        const info = tex_info orelse return 0;
        return bindless_slots[@intCast(info.index)];
    }
};
