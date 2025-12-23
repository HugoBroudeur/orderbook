const std = @import("std");
const ig = @import("cimgui");

pub const Theme = enum { custom, enemymouse, spectrum_light };

pub fn setStyle(theme: Theme) void {
    var style: *ig.ImGuiStyle = &ig.igGetStyle().*;

    switch (theme) {
        .custom => {
            style.Alpha = 0.83;
            style.WindowBorderSize = 0;
            // style.Alpha = 1.0;
            // style.WindowFillAlphaDefault = 0.83;
            // style.ChildWindowRounding = 3;
            style.WindowRounding = 3;
            style.GrabRounding = 1;
            style.GrabMinSize = 20;
            style.FrameRounding = 3;

            style.Colors[ig.ImGuiCol_Text] = ig.ImVec4{ .x = 0.0, .y = 1.0, .z = 1.0, .w = 1.0 };
            style.Colors[ig.ImGuiCol_TextDisabled] = ig.ImVec4{ .x = 0.00, .y = 0.40, .z = 0.41, .w = 1.00 };
            style.Colors[ig.ImGuiCol_WindowBg] = ig.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 1.00 };
            // style.Colors[ig.ImGuiCol_ChildWindowBg] = ig.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 0.00 };
            style.Colors[ig.ImGuiCol_Border] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.65 };
            style.Colors[ig.ImGuiCol_BorderShadow] = ig.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 0.00 };
            style.Colors[ig.ImGuiCol_FrameBg] = ig.ImVec4{ .x = 0.44, .y = 0.80, .z = 0.80, .w = 0.18 };
            style.Colors[ig.ImGuiCol_FrameBgHovered] = ig.ImVec4{ .x = 0.44, .y = 0.80, .z = 0.80, .w = 0.27 };
            style.Colors[ig.ImGuiCol_FrameBgActive] = ig.ImVec4{ .x = 0.44, .y = 0.81, .z = 0.86, .w = 0.66 };
            style.Colors[ig.ImGuiCol_TitleBg] = ig.ImVec4{ .x = 0.14, .y = 0.18, .z = 0.21, .w = 0.73 };
            style.Colors[ig.ImGuiCol_TitleBgCollapsed] = ig.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 0.54 };
            style.Colors[ig.ImGuiCol_TitleBgActive] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.27 };
            style.Colors[ig.ImGuiCol_MenuBarBg] = ig.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 0.20 };
            style.Colors[ig.ImGuiCol_ScrollbarBg] = ig.ImVec4{ .x = 0.22, .y = 0.29, .z = 0.30, .w = 0.71 };
            style.Colors[ig.ImGuiCol_ScrollbarGrab] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.44 };
            style.Colors[ig.ImGuiCol_ScrollbarGrabHovered] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.74 };
            style.Colors[ig.ImGuiCol_ScrollbarGrabActive] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 1.00 };
            // style.Colors[ig.ImGuiCol_ComboBg] = ig.ImVec4{ .x = 0.16, .y = 0.24, .z = 0.22, .w = 0.60 };
            style.Colors[ig.ImGuiCol_CheckMark] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.68 };
            style.Colors[ig.ImGuiCol_SliderGrab] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.36 };
            style.Colors[ig.ImGuiCol_SliderGrabActive] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.76 };
            style.Colors[ig.ImGuiCol_Button] = ig.ImVec4{ .x = 0.00, .y = 0.65, .z = 0.65, .w = 0.46 };
            style.Colors[ig.ImGuiCol_ButtonHovered] = ig.ImVec4{ .x = 0.01, .y = 1.00, .z = 1.00, .w = 0.43 };
            style.Colors[ig.ImGuiCol_ButtonActive] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.62 };
            style.Colors[ig.ImGuiCol_Header] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.33 };
            style.Colors[ig.ImGuiCol_HeaderHovered] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.42 };
            style.Colors[ig.ImGuiCol_HeaderActive] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.54 };
            // style.Colors[ig.ImGuiCol_Column] = ig.ImVec4{ .x = 0.00, .y = 0.50, .z = 0.50, .w = 0.33 };
            // style.Colors[ig.ImGuiCol_ColumnHovered] = ig.ImVec4{ .x = 0.00, .y = 0.50, .z = 0.50, .w = 0.47 };
            // style.Colors[ig.ImGuiCol_ColumnActive] = ig.ImVec4{ .x = 0.00, .y = 0.70, .z = 0.70, .w = 1.00 };
            style.Colors[ig.ImGuiCol_ResizeGrip] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.54 };
            style.Colors[ig.ImGuiCol_ResizeGripHovered] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.74 };
            style.Colors[ig.ImGuiCol_ResizeGripActive] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 1.00 };
            // style.Colors[ig.ImGuiCol_CloseButton] = ig.ImVec4{ .x = 0.00, .y = 0.78, .z = 0.78, .w = 0.35 };
            // style.Colors[ig.ImGuiCol_CloseButtonHovered] = ig.ImVec4{ .x = 0.00, .y = 0.78, .z = 0.78, .w = 0.47 };
            // style.Colors[ig.ImGuiCol_CloseButtonActive] = ig.ImVec4{ .x = 0.00, .y = 0.78, .z = 0.78, .w = 1.00 };
            style.Colors[ig.ImGuiCol_PlotLines] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 1.00 };
            style.Colors[ig.ImGuiCol_PlotLinesHovered] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 1.00 };
            style.Colors[ig.ImGuiCol_PlotHistogram] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 1.00 };
            style.Colors[ig.ImGuiCol_PlotHistogramHovered] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 1.00 };
            style.Colors[ig.ImGuiCol_TextSelectedBg] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.22 };
            // style.Colors[ig.ImGuiCol_TooltipBg] = ig.ImVec4{ .x = 0.00, .y = 0.13, .z = 0.13, .w = 0.90 };
            // style.Colors[ig.ImGuiCol_ModalWindowDarkening] = ig.ImVec4{ .x = 0.04, .y = 0.10, .z = 0.09, .w = 0.51 };
        },
        .enemymouse => {
            style.Alpha = 0.83;
            // style.Alpha = 1.0;
            // style.WindowFillAlphaDefault = 0.83;
            // style.ChildWindowRounding = 3;
            style.WindowRounding = 3;
            style.GrabRounding = 1;
            style.GrabMinSize = 20;
            style.FrameRounding = 3;

            style.Colors[ig.ImGuiCol_Text] = ig.ImVec4{ .x = 0.0, .y = 1.0, .z = 1.0, .w = 1.0 };
            style.Colors[ig.ImGuiCol_TextDisabled] = ig.ImVec4{ .x = 0.00, .y = 0.40, .z = 0.41, .w = 1.00 };
            style.Colors[ig.ImGuiCol_WindowBg] = ig.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 1.00 };
            // style.Colors[ig.ImGuiCol_ChildWindowBg] = ig.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 0.00 };
            style.Colors[ig.ImGuiCol_Border] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.65 };
            style.Colors[ig.ImGuiCol_BorderShadow] = ig.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 0.00 };
            style.Colors[ig.ImGuiCol_FrameBg] = ig.ImVec4{ .x = 0.44, .y = 0.80, .z = 0.80, .w = 0.18 };
            style.Colors[ig.ImGuiCol_FrameBgHovered] = ig.ImVec4{ .x = 0.44, .y = 0.80, .z = 0.80, .w = 0.27 };
            style.Colors[ig.ImGuiCol_FrameBgActive] = ig.ImVec4{ .x = 0.44, .y = 0.81, .z = 0.86, .w = 0.66 };
            style.Colors[ig.ImGuiCol_TitleBg] = ig.ImVec4{ .x = 0.14, .y = 0.18, .z = 0.21, .w = 0.73 };
            style.Colors[ig.ImGuiCol_TitleBgCollapsed] = ig.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 0.54 };
            style.Colors[ig.ImGuiCol_TitleBgActive] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.27 };
            style.Colors[ig.ImGuiCol_MenuBarBg] = ig.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 0.20 };
            style.Colors[ig.ImGuiCol_ScrollbarBg] = ig.ImVec4{ .x = 0.22, .y = 0.29, .z = 0.30, .w = 0.71 };
            style.Colors[ig.ImGuiCol_ScrollbarGrab] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.44 };
            style.Colors[ig.ImGuiCol_ScrollbarGrabHovered] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.74 };
            style.Colors[ig.ImGuiCol_ScrollbarGrabActive] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 1.00 };
            // style.Colors[ig.ImGuiCol_ComboBg] = ig.ImVec4{ .x = 0.16, .y = 0.24, .z = 0.22, .w = 0.60 };
            style.Colors[ig.ImGuiCol_CheckMark] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.68 };
            style.Colors[ig.ImGuiCol_SliderGrab] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.36 };
            style.Colors[ig.ImGuiCol_SliderGrabActive] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.76 };
            style.Colors[ig.ImGuiCol_Button] = ig.ImVec4{ .x = 0.00, .y = 0.65, .z = 0.65, .w = 0.46 };
            style.Colors[ig.ImGuiCol_ButtonHovered] = ig.ImVec4{ .x = 0.01, .y = 1.00, .z = 1.00, .w = 0.43 };
            style.Colors[ig.ImGuiCol_ButtonActive] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.62 };
            style.Colors[ig.ImGuiCol_Header] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.33 };
            style.Colors[ig.ImGuiCol_HeaderHovered] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.42 };
            style.Colors[ig.ImGuiCol_HeaderActive] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.54 };
            // style.Colors[ig.ImGuiCol_Column] = ig.ImVec4{ .x = 0.00, .y = 0.50, .z = 0.50, .w = 0.33 };
            // style.Colors[ig.ImGuiCol_ColumnHovered] = ig.ImVec4{ .x = 0.00, .y = 0.50, .z = 0.50, .w = 0.47 };
            // style.Colors[ig.ImGuiCol_ColumnActive] = ig.ImVec4{ .x = 0.00, .y = 0.70, .z = 0.70, .w = 1.00 };
            style.Colors[ig.ImGuiCol_ResizeGrip] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.54 };
            style.Colors[ig.ImGuiCol_ResizeGripHovered] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.74 };
            style.Colors[ig.ImGuiCol_ResizeGripActive] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 1.00 };
            // style.Colors[ig.ImGuiCol_CloseButton] = ig.ImVec4{ .x = 0.00, .y = 0.78, .z = 0.78, .w = 0.35 };
            // style.Colors[ig.ImGuiCol_CloseButtonHovered] = ig.ImVec4{ .x = 0.00, .y = 0.78, .z = 0.78, .w = 0.47 };
            // style.Colors[ig.ImGuiCol_CloseButtonActive] = ig.ImVec4{ .x = 0.00, .y = 0.78, .z = 0.78, .w = 1.00 };
            style.Colors[ig.ImGuiCol_PlotLines] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 1.00 };
            style.Colors[ig.ImGuiCol_PlotLinesHovered] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 1.00 };
            style.Colors[ig.ImGuiCol_PlotHistogram] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 1.00 };
            style.Colors[ig.ImGuiCol_PlotHistogramHovered] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 1.00 };
            style.Colors[ig.ImGuiCol_TextSelectedBg] = ig.ImVec4{ .x = 0.00, .y = 1.00, .z = 1.00, .w = 0.22 };
            // style.Colors[ig.ImGuiCol_TooltipBg] = ig.ImVec4{ .x = 0.00, .y = 0.13, .z = 0.13, .w = 0.90 };
            // style.Colors[ig.ImGuiCol_ModalWindowDarkening] = ig.ImVec4{ .x = 0.04, .y = 0.10, .z = 0.09, .w = 0.51 };
        },
        .spectrum_light => {
            style.GrabRounding = 4.0;

            var colors = &style.Colors;
            colors[ig.ImGuiCol_Text] = colorConvertU32ToFloat4(Spectrum.Light.GRAY800); // text on hovered controls is gray900
            colors[ig.ImGuiCol_TextDisabled] = colorConvertU32ToFloat4(Spectrum.Light.GRAY500);
            colors[ig.ImGuiCol_WindowBg] = colorConvertU32ToFloat4(Spectrum.Light.GRAY100);
            colors[ig.ImGuiCol_ChildBg] = ig.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 0.00 };
            colors[ig.ImGuiCol_PopupBg] = colorConvertU32ToFloat4(Spectrum.Light.GRAY50); // not sure about this. Note: applies to tooltips too.
            colors[ig.ImGuiCol_Border] = colorConvertU32ToFloat4(Spectrum.Light.GRAY300);
            colors[ig.ImGuiCol_BorderShadow] = colorConvertU32ToFloat4(Spectrum.Static.NONE); // We don't want shadows. Ever.
            colors[ig.ImGuiCol_FrameBg] = colorConvertU32ToFloat4(Spectrum.Light.GRAY75); // this isnt right, spectrum does not do this, but it's a good fallback
            colors[ig.ImGuiCol_FrameBgHovered] = colorConvertU32ToFloat4(Spectrum.Light.GRAY50);
            colors[ig.ImGuiCol_FrameBgActive] = colorConvertU32ToFloat4(Spectrum.Light.GRAY200);
            colors[ig.ImGuiCol_TitleBg] = colorConvertU32ToFloat4(Spectrum.Light.GRAY300); // those titlebar values are totally made up, spectrum does not have this.
            colors[ig.ImGuiCol_TitleBgActive] = colorConvertU32ToFloat4(Spectrum.Light.GRAY200);
            colors[ig.ImGuiCol_TitleBgCollapsed] = colorConvertU32ToFloat4(Spectrum.Light.GRAY400);
            colors[ig.ImGuiCol_MenuBarBg] = colorConvertU32ToFloat4(Spectrum.Light.GRAY100);
            colors[ig.ImGuiCol_ScrollbarBg] = colorConvertU32ToFloat4(Spectrum.Light.GRAY100); // same as regular background
            colors[ig.ImGuiCol_ScrollbarGrab] = colorConvertU32ToFloat4(Spectrum.Light.GRAY400);
            colors[ig.ImGuiCol_ScrollbarGrabHovered] = colorConvertU32ToFloat4(Spectrum.Light.GRAY600);
            colors[ig.ImGuiCol_ScrollbarGrabActive] = colorConvertU32ToFloat4(Spectrum.Light.GRAY700);
            colors[ig.ImGuiCol_CheckMark] = colorConvertU32ToFloat4(Spectrum.Light.BLUE500);
            colors[ig.ImGuiCol_SliderGrab] = colorConvertU32ToFloat4(Spectrum.Light.GRAY700);
            colors[ig.ImGuiCol_SliderGrabActive] = colorConvertU32ToFloat4(Spectrum.Light.GRAY800);
            colors[ig.ImGuiCol_Button] = colorConvertU32ToFloat4(Spectrum.Light.GRAY75); // match default button to Spectrum's 'Action Button'.
            colors[ig.ImGuiCol_ButtonHovered] = colorConvertU32ToFloat4(Spectrum.Light.GRAY50);
            colors[ig.ImGuiCol_ButtonActive] = colorConvertU32ToFloat4(Spectrum.Light.GRAY200);
            colors[ig.ImGuiCol_Header] = colorConvertU32ToFloat4(Spectrum.Light.BLUE400);
            colors[ig.ImGuiCol_HeaderHovered] = colorConvertU32ToFloat4(Spectrum.Light.BLUE500);
            colors[ig.ImGuiCol_HeaderActive] = colorConvertU32ToFloat4(Spectrum.Light.BLUE600);
            colors[ig.ImGuiCol_Separator] = colorConvertU32ToFloat4(Spectrum.Light.GRAY400);
            colors[ig.ImGuiCol_SeparatorHovered] = colorConvertU32ToFloat4(Spectrum.Light.GRAY600);
            colors[ig.ImGuiCol_SeparatorActive] = colorConvertU32ToFloat4(Spectrum.Light.GRAY700);
            colors[ig.ImGuiCol_ResizeGrip] = colorConvertU32ToFloat4(Spectrum.Light.GRAY400);
            colors[ig.ImGuiCol_ResizeGripHovered] = colorConvertU32ToFloat4(Spectrum.Light.GRAY600);
            colors[ig.ImGuiCol_ResizeGripActive] = colorConvertU32ToFloat4(Spectrum.Light.GRAY700);
            colors[ig.ImGuiCol_PlotLines] = colorConvertU32ToFloat4(Spectrum.Light.BLUE400);
            colors[ig.ImGuiCol_PlotLinesHovered] = colorConvertU32ToFloat4(Spectrum.Light.BLUE600);
            colors[ig.ImGuiCol_PlotHistogram] = colorConvertU32ToFloat4(Spectrum.Light.BLUE400);
            colors[ig.ImGuiCol_PlotHistogramHovered] = colorConvertU32ToFloat4(Spectrum.Light.BLUE600);
            colors[ig.ImGuiCol_TextSelectedBg] = colorConvertU32ToFloat4((Spectrum.Light.BLUE400 & 0x00FFFFFF) | 0x33000000);
            colors[ig.ImGuiCol_DragDropTarget] = ig.ImVec4{ .x = 1.00, .y = 1.00, .z = 0.00, .w = 0.90 };
            // colors[ig.ImGuiCol_NavHighlight] = colorConvertU32ToFloat4((Spectrum.Light.GRAY900 & 0x00FFFFFF) | 0x0A000000);
            colors[ig.ImGuiCol_NavWindowingHighlight] = ig.ImVec4{ .x = 1.00, .y = 1.00, .z = 1.00, .w = 0.70 };
            colors[ig.ImGuiCol_NavWindowingDimBg] = ig.ImVec4{ .x = 0.80, .y = 0.80, .z = 0.80, .w = 0.20 };
            colors[ig.ImGuiCol_ModalWindowDimBg] = ig.ImVec4{ .x = 0.20, .y = 0.20, .z = 0.20, .w = 0.35 };
        },
    }
}

/// Spectrum color helpers and constants translated from the original C++ header.
///
/// By default this file uses the light theme. To switch to the dark theme,
/// set `SPECTRUM_USE_LIGHT_THEME = false` below (or override it at edit time).
///
/// Notes:
///  * Colors are represented as 32-bit unsigned integers in the same packed
///    order used in the original header (alpha in the MSB).
///  * The `color` function follows the header's logic: add alpha 0xFF and
///    swap red/blue channels into the same layout as the C++ code.
///
/// Use from other modules:
///   const spec = @import("spectrum");
///   const white = spec.Static.WHITE;
///   const semi = spec.color_alpha(0x80, spec.Static.BLUE400);
///
pub const Spectrum = struct {
    // Toggle theme here. Set to `false` for dark theme.
    pub const SPECTRUM_USE_LIGHT_THEME: bool = true;

    // visual tweaks
    pub const CHECKBOX_BORDER_SIZE: f32 = 2.0;
    pub const CHECKBOX_ROUNDING: f32 = 2.0;

    /// Load font and set as default (declaration only — implement in your app).
    /// Equivalent signature to the C++ `void LoadFont(float size = 16.0f);`
    pub fn LoadFont(size: f32) void {
        // no-op placeholder: implement font loading in your application
        // e.g. call into ImGui or your font loader here
        _ = size;
    }

    /// Apply Spectrum style (declaration only — implement in your app).
    pub fn StyleColorsSpectrum() void {
        // no-op placeholder: implement style application in your app
    }

    // --- helpers translated from the unnamed namespace in the C++ header ---

    /// Convert RGB hex (0xRRGGBB) into the packed format used by the original header.
    /// The implementation matches the original `Color(unsigned int c)`:
    ///  - alpha set to 0xFF
    ///  - swap red and blue channels into a (A R G B) packed 32-bit value
    pub fn color(c: u32) u32 {
        const a: u32 = 0xFF;
        const r: u32 = (c >> 16) & 0xFF;
        const g: u32 = (c >> 8) & 0xFF;
        const b: u32 = (c >> 0) & 0xFF;
        return ((a & 0xFF) << 24) | ((r & 0xFF) << 0) | ((g & 0xFF) << 8) | ((b & 0xFF) << 16);
    }

    /// Apply an alpha (0..255) to an existing packed color `c`.
    pub fn color_alpha(alpha: u32, c: u32) u32 {
        return ((alpha & 0xFF) << 24) | (c & 0x00FF_FFFF);
    }

    // --- static colors (shared across themes) ---
    pub const Static = struct {
        pub const NONE: u32 = 0x00000000; // transparent
        pub const WHITE: u32 = Spectrum.color(0xFFFFFF);
        pub const BLACK: u32 = Spectrum.color(0x000000);
        pub const GRAY200: u32 = Spectrum.color(0xF4F4F4);
        pub const GRAY300: u32 = Spectrum.color(0xEAEAEA);
        pub const GRAY400: u32 = Spectrum.color(0xD3D3D3);
        pub const GRAY500: u32 = Spectrum.color(0xBCBCBC);
        pub const GRAY600: u32 = Spectrum.color(0x959595);
        pub const GRAY700: u32 = Spectrum.color(0x767676);
        pub const GRAY800: u32 = Spectrum.color(0x505050);
        pub const GRAY900: u32 = Spectrum.color(0x323232);
        pub const BLUE400: u32 = Spectrum.color(0x378EF0);
        pub const BLUE500: u32 = Spectrum.color(0x2680EB);
        pub const BLUE600: u32 = Spectrum.color(0x1473E6);
        pub const BLUE700: u32 = Spectrum.color(0x0D66D0);
        pub const RED400: u32 = Spectrum.color(0xEC5B62);
        pub const RED500: u32 = Spectrum.color(0xE34850);
        pub const RED600: u32 = Spectrum.color(0xD7373F);
        pub const RED700: u32 = Spectrum.color(0xC9252D);
        pub const ORANGE400: u32 = Spectrum.color(0xF29423);
        pub const ORANGE500: u32 = Spectrum.color(0xE68619);
        pub const ORANGE600: u32 = Spectrum.color(0xDA7B11);
        pub const ORANGE700: u32 = Spectrum.color(0xCB6F10);
        pub const GREEN400: u32 = Spectrum.color(0x33AB84);
        pub const GREEN500: u32 = Spectrum.color(0x2D9D78);
        pub const GREEN600: u32 = Spectrum.color(0x268E6C);
        pub const GREEN700: u32 = Spectrum.color(0x12805C);
    };

    pub const Light = struct {
        pub const GRAY50: u32 = Spectrum.color(0xFFFFFF);
        pub const GRAY75: u32 = Spectrum.color(0xFAFAFA);
        pub const GRAY100: u32 = Spectrum.color(0xF5F5F5);
        pub const GRAY200: u32 = Spectrum.color(0xEAEAEA);
        pub const GRAY300: u32 = Spectrum.color(0xE1E1E1);
        pub const GRAY400: u32 = Spectrum.color(0xCACACA);
        pub const GRAY500: u32 = Spectrum.color(0xB3B3B3);
        pub const GRAY600: u32 = Spectrum.color(0x8E8E8E);
        pub const GRAY700: u32 = Spectrum.color(0x707070);
        pub const GRAY800: u32 = Spectrum.color(0x4B4B4B);
        pub const GRAY900: u32 = Spectrum.color(0x2C2C2C);
        pub const BLUE400: u32 = Spectrum.color(0x2680EB);
        pub const BLUE500: u32 = Spectrum.color(0x1473E6);
        pub const BLUE600: u32 = Spectrum.color(0x0D66D0);
        pub const BLUE700: u32 = Spectrum.color(0x095ABA);
        pub const RED400: u32 = Spectrum.color(0xE34850);
        pub const RED500: u32 = Spectrum.color(0xD7373F);
        pub const RED600: u32 = Spectrum.color(0xC9252D);
        pub const RED700: u32 = Spectrum.color(0xBB121A);
        pub const ORANGE400: u32 = Spectrum.color(0xE68619);
        pub const ORANGE500: u32 = Spectrum.color(0xDA7B11);
        pub const ORANGE600: u32 = Spectrum.color(0xCB6F10);
        pub const ORANGE700: u32 = Spectrum.color(0xBD640D);
        pub const GREEN400: u32 = Spectrum.color(0x2D9D78);
        pub const GREEN500: u32 = Spectrum.color(0x268E6C);
        pub const GREEN600: u32 = Spectrum.color(0x12805C);
        pub const GREEN700: u32 = Spectrum.color(0x107154);
        pub const INDIGO400: u32 = Spectrum.color(0x6767EC);
        pub const INDIGO500: u32 = Spectrum.color(0x5C5CE0);
        pub const INDIGO600: u32 = Spectrum.color(0x5151D3);
        pub const INDIGO700: u32 = Spectrum.color(0x4646C6);
        pub const CELERY400: u32 = Spectrum.color(0x44B556);
        pub const CELERY500: u32 = Spectrum.color(0x3DA74E);
        pub const CELERY600: u32 = Spectrum.color(0x379947);
        pub const CELERY700: u32 = Spectrum.color(0x318B40);
        pub const MAGENTA400: u32 = Spectrum.color(0xD83790);
        pub const MAGENTA500: u32 = Spectrum.color(0xCE2783);
        pub const MAGENTA600: u32 = Spectrum.color(0xBC1C74);
        pub const MAGENTA700: u32 = Spectrum.color(0xAE0E66);
        pub const YELLOW400: u32 = Spectrum.color(0xDFBF00);
        pub const YELLOW500: u32 = Spectrum.color(0xD2B200);
        pub const YELLOW600: u32 = Spectrum.color(0xC4A600);
        pub const YELLOW700: u32 = Spectrum.color(0xB79900);
        pub const FUCHSIA400: u32 = Spectrum.color(0xC038CC);
        pub const FUCHSIA500: u32 = Spectrum.color(0xB130BD);
        pub const FUCHSIA600: u32 = Spectrum.color(0xA228AD);
        pub const FUCHSIA700: u32 = Spectrum.color(0x93219E);
        pub const SEAFOAM400: u32 = Spectrum.color(0x1B959A);
        pub const SEAFOAM500: u32 = Spectrum.color(0x16878C);
        pub const SEAFOAM600: u32 = Spectrum.color(0x0F797D);
        pub const SEAFOAM700: u32 = Spectrum.color(0x096C6F);
        pub const CHARTREUSE400: u32 = Spectrum.color(0x85D044);
        pub const CHARTREUSE500: u32 = Spectrum.color(0x7CC33F);
        pub const CHARTREUSE600: u32 = Spectrum.color(0x73B53A);
        pub const CHARTREUSE700: u32 = Spectrum.color(0x6AA834);
        pub const PURPLE400: u32 = Spectrum.color(0x9256D9);
        pub const PURPLE500: u32 = Spectrum.color(0x864CCC);
        pub const PURPLE600: u32 = Spectrum.color(0x7A42BF);
        pub const PURPLE700: u32 = Spectrum.color(0x6F38B1);
    };

    pub const Dark = struct {
        pub const GRAY50: u32 = Spectrum.color(0x252525);
        pub const GRAY75: u32 = Spectrum.color(0x2F2F2F);
        pub const GRAY100: u32 = Spectrum.color(0x323232);
        pub const GRAY200: u32 = Spectrum.color(0x393939);
        pub const GRAY300: u32 = Spectrum.color(0x3E3E3E);
        pub const GRAY400: u32 = Spectrum.color(0x4D4D4D);
        pub const GRAY500: u32 = Spectrum.color(0x5C5C5C);
        pub const GRAY600: u32 = Spectrum.color(0x7B7B7B);
        pub const GRAY700: u32 = Spectrum.color(0x999999);
        pub const GRAY800: u32 = Spectrum.color(0xCDCDCD);
        pub const GRAY900: u32 = Spectrum.color(0xFFFFFF);
        pub const BLUE400: u32 = Spectrum.color(0x2680EB);
        pub const BLUE500: u32 = Spectrum.color(0x378EF0);
        pub const BLUE600: u32 = Spectrum.color(0x4B9CF5);
        pub const BLUE700: u32 = Spectrum.color(0x5AA9FA);
        pub const RED400: u32 = Spectrum.color(0xE34850);
        pub const RED500: u32 = Spectrum.color(0xEC5B62);
        pub const RED600: u32 = Spectrum.color(0xF76D74);
        pub const RED700: u32 = Spectrum.color(0xFF7B82);
        pub const ORANGE400: u32 = Spectrum.color(0xE68619);
        pub const ORANGE500: u32 = Spectrum.color(0xF29423);
        pub const ORANGE600: u32 = Spectrum.color(0xF9A43F);
        pub const ORANGE700: u32 = Spectrum.color(0xFFB55B);
        pub const GREEN400: u32 = Spectrum.color(0x2D9D78);
        pub const GREEN500: u32 = Spectrum.color(0x33AB84);
        pub const GREEN600: u32 = Spectrum.color(0x39B990);
        pub const GREEN700: u32 = Spectrum.color(0x3FC89C);
        pub const INDIGO400: u32 = Spectrum.color(0x6767EC);
        pub const INDIGO500: u32 = Spectrum.color(0x7575F1);
        pub const INDIGO600: u32 = Spectrum.color(0x8282F6);
        pub const INDIGO700: u32 = Spectrum.color(0x9090FA);
        pub const CELERY400: u32 = Spectrum.color(0x44B556);
        pub const CELERY500: u32 = Spectrum.color(0x4BC35F);
        pub const CELERY600: u32 = Spectrum.color(0x51D267);
        pub const CELERY700: u32 = Spectrum.color(0x58E06F);
        pub const MAGENTA400: u32 = Spectrum.color(0xD83790);
        pub const MAGENTA500: u32 = Spectrum.color(0xE2499D);
        pub const MAGENTA600: u32 = Spectrum.color(0xEC5AAA);
        pub const MAGENTA700: u32 = Spectrum.color(0xF56BB7);
        pub const YELLOW400: u32 = Spectrum.color(0xDFBF00);
        pub const YELLOW500: u32 = Spectrum.color(0xEDCC00);
        pub const YELLOW600: u32 = Spectrum.color(0xFAD900);
        pub const YELLOW700: u32 = Spectrum.color(0xFFE22E);
        pub const FUCHSIA400: u32 = Spectrum.color(0xC038CC);
        pub const FUCHSIA500: u32 = Spectrum.color(0xCF3EDC);
        pub const FUCHSIA600: u32 = Spectrum.color(0xD951E5);
        pub const FUCHSIA700: u32 = Spectrum.color(0xE366EF);
        pub const SEAFOAM400: u32 = Spectrum.color(0x1B959A);
        pub const SEAFOAM500: u32 = Spectrum.color(0x20A3A8);
        pub const SEAFOAM600: u32 = Spectrum.color(0x23B2B8);
        pub const SEAFOAM700: u32 = Spectrum.color(0x26C0C7);
        pub const CHARTREUSE400: u32 = Spectrum.color(0x85D044);
        pub const CHARTREUSE500: u32 = Spectrum.color(0x8EDE49);
        pub const CHARTREUSE600: u32 = Spectrum.color(0x9BEC54);
        pub const CHARTREUSE700: u32 = Spectrum.color(0xA3F858);
        pub const PURPLE400: u32 = Spectrum.color(0x9256D9);
        pub const PURPLE500: u32 = Spectrum.color(0x9D64E1);
        pub const PURPLE600: u32 = Spectrum.color(0xA873E9);
        pub const PURPLE700: u32 = Spectrum.color(0xB483F0);
    };
};

fn colorConvertU32ToFloat4(color: u32) ig.ImVec4 {
    var f4: ig.ImVec4 = .{ .x = 0, .y = 0, .w = 0, .z = 0 };
    ig.igColorConvertU32ToFloat4(&f4, color);
    return f4;
}
