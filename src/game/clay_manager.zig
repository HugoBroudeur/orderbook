const std = @import("std");
const sdl = @import("sdl3");
const clay = @import("zclay");
const FontManager = @import("font_manager.zig");

pub const RendererData = struct {
    // renderer: *sdl.SDL_Renderer,
    text_engine: *sdl.ttf.GpuTextEngine,
    font: FontManager.Font,
};

// Global for convenience. Even in 4K this is enough for smooth curves
var NUM_CIRCLE_SEGMENTS: i32 = 16;
var current_clipping_rectangle: sdl.rect.IRect = undefined;

// All rendering is performed by a single SDL call
pub fn renderFillRoundedRect(
    renderer_data: *RendererData,
    rect: sdl.SDL_FRect,
    corner_radius: f32,
    _color: clay.Clay_Color,
) void {
    const color = sdl.SDL_FColor{
        .r = @as(f32, @floatFromInt(_color.r)) / 255.0,
        .g = @as(f32, @floatFromInt(_color.g)) / 255.0,
        .b = @as(f32, @floatFromInt(_color.b)) / 255.0,
        .a = @as(f32, @floatFromInt(_color.a)) / 255.0,
    };

    const min_radius = @min(rect.w, rect.h) / 2.0;
    const clamped_radius = @min(corner_radius, min_radius);

    const num_circle_segments = @max(NUM_CIRCLE_SEGMENTS, @as(i32, @intFromFloat(clamped_radius * 0.5)));

    const total_vertices: usize = 4 + (4 * @as(usize, @intCast(num_circle_segments * 2))) + 2 * 4;
    const total_indices: usize = 6 + (4 * @as(usize, @intCast(num_circle_segments * 3))) + 6 * 4;

    var vertices: [total_vertices]sdl.SDL_Vertex = undefined; // Assuming max size
    var indices: [total_indices]i32 = undefined; // Assuming max size
    var vertex_count: usize = 0;
    var index_count: usize = 0;

    // Define center rectangle
    vertices[vertex_count] = sdl.SDL_Vertex{
        .position = .{ .x = rect.x + clamped_radius, .y = rect.y + clamped_radius },
        .color = color,
        .tex_coord = .{ .x = 0, .y = 0 },
    };
    vertex_count += 1;

    vertices[vertex_count] = sdl.SDL_Vertex{
        .position = .{ .x = rect.x + rect.w - clamped_radius, .y = rect.y + clamped_radius },
        .color = color,
        .tex_coord = .{ .x = 1, .y = 0 },
    };
    vertex_count += 1;

    vertices[vertex_count] = sdl.SDL_Vertex{
        .position = .{ .x = rect.x + rect.w - clamped_radius, .y = rect.y + rect.h - clamped_radius },
        .color = color,
        .tex_coord = .{ .x = 1, .y = 1 },
    };
    vertex_count += 1;

    vertices[vertex_count] = sdl.SDL_Vertex{
        .position = .{ .x = rect.x + clamped_radius, .y = rect.y + rect.h - clamped_radius },
        .color = color,
        .tex_coord = .{ .x = 0, .y = 1 },
    };
    vertex_count += 1;

    indices[index_count] = 0;
    index_count += 1;
    indices[index_count] = 1;
    index_count += 1;
    indices[index_count] = 3;
    index_count += 1;
    indices[index_count] = 1;
    index_count += 1;
    indices[index_count] = 2;
    index_count += 1;
    indices[index_count] = 3;
    index_count += 1;

    // Define rounded corners as triangle fans
    const step = (std.math.pi / 2.0) / @as(f32, @floatFromInt(num_circle_segments));
    var i: i32 = 0;
    while (i < num_circle_segments) : (i += 1) {
        const angle1 = @as(f32, @floatFromInt(i)) * step;
        const angle2 = (@as(f32, @floatFromInt(i)) + 1.0) * step;

        var j: i32 = 0;
        while (j < 4) : (j += 1) {
            var cx: f32 = undefined;
            var cy: f32 = undefined;
            var sign_x: f32 = undefined;
            var sign_y: f32 = undefined;

            switch (j) {
                0 => { // Top-left
                    cx = rect.x + clamped_radius;
                    cy = rect.y + clamped_radius;
                    sign_x = -1;
                    sign_y = -1;
                },
                1 => { // Top-right
                    cx = rect.x + rect.w - clamped_radius;
                    cy = rect.y + clamped_radius;
                    sign_x = 1;
                    sign_y = -1;
                },
                2 => { // Bottom-right
                    cx = rect.x + rect.w - clamped_radius;
                    cy = rect.y + rect.h - clamped_radius;
                    sign_x = 1;
                    sign_y = 1;
                },
                3 => { // Bottom-left
                    cx = rect.x + clamped_radius;
                    cy = rect.y + rect.h - clamped_radius;
                    sign_x = -1;
                    sign_y = 1;
                },
                else => return,
            }

            vertices[vertex_count] = sdl.SDL_Vertex{
                .position = .{
                    .x = cx + @cos(angle1) * clamped_radius * sign_x,
                    .y = cy + @sin(angle1) * clamped_radius * sign_y,
                },
                .color = color,
                .tex_coord = .{ .x = 0, .y = 0 },
            };
            vertex_count += 1;

            vertices[vertex_count] = sdl.SDL_Vertex{
                .position = .{
                    .x = cx + @cos(angle2) * clamped_radius * sign_x,
                    .y = cy + @sin(angle2) * clamped_radius * sign_y,
                },
                .color = color,
                .tex_coord = .{ .x = 0, .y = 0 },
            };
            vertex_count += 1;

            indices[index_count] = j;
            index_count += 1;
            indices[index_count] = @intCast(vertex_count - 2);
            index_count += 1;
            indices[index_count] = @intCast(vertex_count - 1);
            index_count += 1;
        }
    }

    // Define edge rectangles
    // Top edge
    vertices[vertex_count] = sdl.SDL_Vertex{
        .position = .{ .x = rect.x + clamped_radius, .y = rect.y },
        .color = color,
        .tex_coord = .{ .x = 0, .y = 0 },
    };
    vertex_count += 1;

    vertices[vertex_count] = sdl.SDL_Vertex{
        .position = .{ .x = rect.x + rect.w - clamped_radius, .y = rect.y },
        .color = color,
        .tex_coord = .{ .x = 1, .y = 0 },
    };
    vertex_count += 1;

    indices[index_count] = 0;
    index_count += 1;
    indices[index_count] = @intCast(vertex_count - 2);
    index_count += 1;
    indices[index_count] = @intCast(vertex_count - 1);
    index_count += 1;
    indices[index_count] = 1;
    index_count += 1;
    indices[index_count] = 0;
    index_count += 1;
    indices[index_count] = @intCast(vertex_count - 1);
    index_count += 1;

    // Right edge
    vertices[vertex_count] = sdl.SDL_Vertex{
        .position = .{ .x = rect.x + rect.w, .y = rect.y + clamped_radius },
        .color = color,
        .tex_coord = .{ .x = 1, .y = 0 },
    };
    vertex_count += 1;

    vertices[vertex_count] = sdl.SDL_Vertex{
        .position = .{ .x = rect.x + rect.w, .y = rect.y + rect.h - clamped_radius },
        .color = color,
        .tex_coord = .{ .x = 1, .y = 1 },
    };
    vertex_count += 1;

    indices[index_count] = 1;
    index_count += 1;
    indices[index_count] = @intCast(vertex_count - 2);
    index_count += 1;
    indices[index_count] = @intCast(vertex_count - 1);
    index_count += 1;
    indices[index_count] = 2;
    index_count += 1;
    indices[index_count] = 1;
    index_count += 1;
    indices[index_count] = @intCast(vertex_count - 1);
    index_count += 1;

    // Bottom edge
    vertices[vertex_count] = sdl.SDL_Vertex{
        .position = .{ .x = rect.x + rect.w - clamped_radius, .y = rect.y + rect.h },
        .color = color,
        .tex_coord = .{ .x = 1, .y = 1 },
    };
    vertex_count += 1;

    vertices[vertex_count] = sdl.SDL_Vertex{
        .position = .{ .x = rect.x + clamped_radius, .y = rect.y + rect.h },
        .color = color,
        .tex_coord = .{ .x = 0, .y = 1 },
    };
    vertex_count += 1;

    indices[index_count] = 2;
    index_count += 1;
    indices[index_count] = @intCast(vertex_count - 2);
    index_count += 1;
    indices[index_count] = @intCast(vertex_count - 1);
    index_count += 1;
    indices[index_count] = 3;
    index_count += 1;
    indices[index_count] = 2;
    index_count += 1;
    indices[index_count] = @intCast(vertex_count - 1);
    index_count += 1;

    // Left edge
    vertices[vertex_count] = sdl.SDL_Vertex{
        .position = .{ .x = rect.x, .y = rect.y + rect.h - clamped_radius },
        .color = color,
        .tex_coord = .{ .x = 0, .y = 1 },
    };
    vertex_count += 1;

    vertices[vertex_count] = sdl.SDL_Vertex{
        .position = .{ .x = rect.x, .y = rect.y + clamped_radius },
        .color = color,
        .tex_coord = .{ .x = 0, .y = 0 },
    };
    vertex_count += 1;

    indices[index_count] = 3;
    index_count += 1;
    indices[index_count] = @intCast(vertex_count - 2);
    index_count += 1;
    indices[index_count] = @intCast(vertex_count - 1);
    index_count += 1;
    indices[index_count] = 0;
    index_count += 1;
    indices[index_count] = 3;
    index_count += 1;
    indices[index_count] = @intCast(vertex_count - 1);
    index_count += 1;

    // Render everything
    _ = sdl.SDL_RenderGeometry(
        renderer_data.renderer,
        null,
        &vertices,
        @intCast(vertex_count),
        &indices,
        @intCast(index_count),
    );
}

pub fn renderArc(
    renderer_data: *RendererData,
    center: sdl.SDL_FPoint,
    radius: f32,
    start_angle: f32,
    end_angle: f32,
    thickness: f32,
    color: clay.Clay_Color,
) void {
    _ = sdl.SDL_SetRenderDrawColor(renderer_data.renderer, color.r, color.g, color.b, color.a);

    const rad_start = start_angle * (std.math.pi / 180.0);
    const rad_end = end_angle * (std.math.pi / 180.0);

    const num_circle_segments = @max(NUM_CIRCLE_SEGMENTS, @as(i32, @intFromFloat(radius * 1.5)));

    const angle_step = (rad_end - rad_start) / @as(f32, @floatFromInt(num_circle_segments));
    const thickness_step: f32 = 0.4;

    var t: f32 = thickness_step;
    while (t < thickness - thickness_step) : (t += thickness_step) {
        var points: [512]sdl.SDL_FPoint = undefined; // Assuming max size
        const clamped_radius = @max(radius - t, 1.0);

        var i: i32 = 0;
        while (i <= num_circle_segments) : (i += 1) {
            const angle = rad_start + @as(f32, @floatFromInt(i)) * angle_step;
            points[@intCast(i)] = sdl.SDL_FPoint{
                .x = @round(center.x + @cos(angle) * clamped_radius),
                .y = @round(center.y + @sin(angle) * clamped_radius),
            };
        }
        _ = sdl.SDL_RenderLines(renderer_data.renderer, &points, num_circle_segments + 1);
    }
}

pub fn renderCommands(
    renderer_data: *RendererData,
    cmds: []clay.RenderCommand,
) void {
    for (cmds) |cmd| {
        const bounding_box = cmd.boundingBox;
        const rect = sdl.SDL_FRect{
            .x = @floatFromInt(@as(i32, @intFromFloat(bounding_box.x))),
            .y = @floatFromInt(@as(i32, @intFromFloat(bounding_box.y))),
            .w = @floatFromInt(@as(i32, @intFromFloat(bounding_box.width))),
            .h = @floatFromInt(@as(i32, @intFromFloat(bounding_box.height))),
        };

        switch (cmd.command_type) {
            .rectangle => {
                const config = &cmd.renderData.rectangle;
                _ = sdl.SDL_SetRenderDrawBlendMode(renderer_data.renderer, sdl.SDL_BLENDMODE_BLEND);
                _ = sdl.SDL_SetRenderDrawColor(
                    renderer_data.renderer,
                    config.backgroundColor.r,
                    config.backgroundColor.g,
                    config.backgroundColor.b,
                    config.backgroundColor.a,
                );
                if (config.cornerRadius.topLeft > 0) {
                    renderFillRoundedRect(renderer_data, rect, config.cornerRadius.topLeft, config.backgroundColor);
                } else {
                    _ = sdl.SDL_RenderFillRect(renderer_data.renderer, &rect);
                }
            },
            .text => {
                const config = &cmd.renderData.text;
                const font = renderer_data.font[config.fontId];
                _ = sdl.TTF_SetFontSize(font, config.fontSize);
                const text = sdl.TTF_CreateText(
                    renderer_data.text_engine,
                    font,
                    config.stringContents.chars,
                    config.stringContents.length,
                );
                _ = sdl.TTF_SetTextColor(text, config.textColor.r, config.textColor.g, config.textColor.b, config.textColor.a);
                _ = sdl.TTF_DrawRendererText(text, rect.x, rect.y);
                sdl.TTF_DestroyText(text);
            },
            .border => {
                const config = &cmd.renderData.border;

                const min_radius = @min(rect.w, rect.h) / 2.0;
                const clamped_radii = clay.Clay_CornerRadius{
                    .topLeft = @min(config.cornerRadius.topLeft, min_radius),
                    .topRight = @min(config.cornerRadius.topRight, min_radius),
                    .bottomLeft = @min(config.cornerRadius.bottomLeft, min_radius),
                    .bottomRight = @min(config.cornerRadius.bottomRight, min_radius),
                };

                // Edges
                _ = sdl.SDL_SetRenderDrawColor(renderer_data.renderer, config.color.r, config.color.g, config.color.b, config.color.a);

                if (config.width.left > 0) {
                    const starting_y = rect.y + clamped_radii.topLeft;
                    const length = rect.h - clamped_radii.topLeft - clamped_radii.bottomLeft;
                    const line = sdl.SDL_FRect{
                        .x = rect.x - 1,
                        .y = starting_y,
                        .w = @floatFromInt(config.width.left),
                        .h = length,
                    };
                    _ = sdl.SDL_RenderFillRect(renderer_data.renderer, &line);
                }

                if (config.width.right > 0) {
                    const starting_x = rect.x + rect.w - @as(f32, @floatFromInt(config.width.right)) + 1;
                    const starting_y = rect.y + clamped_radii.topRight;
                    const length = rect.h - clamped_radii.topRight - clamped_radii.bottomRight;
                    const line = sdl.SDL_FRect{
                        .x = starting_x,
                        .y = starting_y,
                        .w = @floatFromInt(config.width.right),
                        .h = length,
                    };
                    _ = sdl.SDL_RenderFillRect(renderer_data.renderer, &line);
                }

                if (config.width.top > 0) {
                    const starting_x = rect.x + clamped_radii.topLeft;
                    const length = rect.w - clamped_radii.topLeft - clamped_radii.topRight;
                    const line = sdl.SDL_FRect{
                        .x = starting_x,
                        .y = rect.y - 1,
                        .w = length,
                        .h = @floatFromInt(config.width.top),
                    };
                    _ = sdl.SDL_RenderFillRect(renderer_data.renderer, &line);
                }

                if (config.width.bottom > 0) {
                    const starting_x = rect.x + clamped_radii.bottomLeft;
                    const starting_y = rect.y + rect.h - @as(f32, @floatFromInt(config.width.bottom)) + 1;
                    const length = rect.w - clamped_radii.bottomLeft - clamped_radii.bottomRight;
                    const line = sdl.SDL_FRect{
                        .x = starting_x,
                        .y = starting_y,
                        .w = length,
                        .h = @floatFromInt(config.width.bottom),
                    };
                    _ = sdl.SDL_SetRenderDrawColor(renderer_data.renderer, config.color.r, config.color.g, config.color.b, config.color.a);
                    _ = sdl.SDL_RenderFillRect(renderer_data.renderer, &line);
                }

                // Corners
                if (config.cornerRadius.topLeft > 0) {
                    const center_x = rect.x + clamped_radii.topLeft - 1;
                    const center_y = rect.y + clamped_radii.topLeft - 1;
                    renderArc(
                        renderer_data,
                        sdl.SDL_FPoint{ .x = center_x, .y = center_y },
                        clamped_radii.topLeft,
                        180.0,
                        270.0,
                        @floatFromInt(config.width.top),
                        config.color,
                    );
                }

                if (config.cornerRadius.topRight > 0) {
                    const center_x = rect.x + rect.w - clamped_radii.topRight;
                    const center_y = rect.y + clamped_radii.topRight - 1;
                    renderArc(
                        renderer_data,
                        sdl.SDL_FPoint{ .x = center_x, .y = center_y },
                        clamped_radii.topRight,
                        270.0,
                        360.0,
                        @floatFromInt(config.width.top),
                        config.color,
                    );
                }

                if (config.cornerRadius.bottomLeft > 0) {
                    const center_x = rect.x + clamped_radii.bottomLeft - 1;
                    const center_y = rect.y + rect.h - clamped_radii.bottomLeft;
                    renderArc(
                        renderer_data,
                        sdl.SDL_FPoint{ .x = center_x, .y = center_y },
                        clamped_radii.bottomLeft,
                        90.0,
                        180.0,
                        @floatFromInt(config.width.bottom),
                        config.color,
                    );
                }

                if (config.cornerRadius.bottomRight > 0) {
                    const center_x = rect.x + rect.w - clamped_radii.bottomRight;
                    const center_y = rect.y + rect.h - clamped_radii.bottomRight;
                    renderArc(
                        renderer_data,
                        sdl.SDL_FPoint{ .x = center_x, .y = center_y },
                        clamped_radii.bottomRight,
                        0.0,
                        90.0,
                        @floatFromInt(config.width.bottom),
                        config.color,
                    );
                }
            },
            .scissor_start => {
                const bounding = cmd.boundingBox;
                current_clipping_rectangle = sdl.SDL_Rect{
                    .x = @intFromFloat(bounding.x),
                    .y = @intFromFloat(bounding.y),
                    .w = @intFromFloat(bounding.width),
                    .h = @intFromFloat(bounding.height),
                };
                _ = sdl.SDL_SetRenderClipRect(renderer_data.renderer, &current_clipping_rectangle);
            },
            .scissor_end => {
                _ = sdl.SDL_SetRenderClipRect(renderer_data.renderer, null);
            },
            .image => {
                const texture: *sdl.SDL_Texture = @ptrCast(@alignCast(cmd.renderData.image.imageData));
                const dest = sdl.SDL_FRect{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
                _ = sdl.SDL_RenderTexture(renderer_data.renderer, texture, null, &dest);
            },
            else => {
                sdl.SDL_Log("Unknown render command type: %d", cmd.commandType);
            },
        }
    }
}
