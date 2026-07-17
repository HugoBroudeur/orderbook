## Librairies

### C librairies (must be installed on the machine)

SDL3
SDL3_ttf

## Prerequisite

On Open Suse

```bash
sudo zypper install SDL3-devel SDL3_ttf-devel SDL3_image-devel
sudo zypper install vulkan-tools vulkan-validationlayer
sudo zypper install slangc
sudo zypper install spirv-tools
```

For Fish
Export the Vulkan validation layer for debugging
```bash
# In ~/.config/fish/config.fish
set -gx VK_LAYER_PATH "/usr/share/vulkan/explicit_layer.d"
```

## Rendering (PBR)

Source of inspiration for the rendering process: [Google Filament — PBR documentation](https://google.github.io/filament/Filament.md.html).

Any work on shader formulas, lighting, the material system, or the imaging pipeline should reference this document.

## Architecture

The engine architecture follows the patterns described in [Vulkan Tutorial — Building a Simple Engine: Architectural Patterns](https://docs.vulkan.org/tutorial/latest/Building_a_Simple_Engine/Engine_Architecture/02_architectural_patterns.html).

