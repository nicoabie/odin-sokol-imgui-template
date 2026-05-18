# Game Template

My template for Odin, Sokol and imgui

warning, sokok-shdc is the mac version, [go here](https://github.com/floooh/sokol-tools-bin) to download one for your platform

build.odin does have a proc called `build_shaders`, feel free to duplicate that to also handle building other shader files

# Building

cd src/sokol
./build_clibs_macos.sh 

build sokol/basisu see readme

# Running 

RUN `odin run src/main.odin -file` from root