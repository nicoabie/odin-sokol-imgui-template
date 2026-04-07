# sokol_basisu

Wrapper for [Basis Universal](https://github.com/BinomialLLC/basis_universal) transcoder with [sokol_gfx](https://github.com/floooh/sokol) integration.

## Prerequisites

- macOS (arm64)
- Xcode/Command Line Tools (clang++)
- sokol headers in `../c/` (sokol_gfx.h)

## Building

```bash
cd /path/to/odin-sokol-imgui-template/src/sokol/basisu
chmod +x build_macos.sh
./build_macos.sh
```

## Odin Bindings

Generate bindings using [odin-bindgen](https://github.com/GalacticBlocks/odin-bindgen) pointing to `bindgen.sjson`
