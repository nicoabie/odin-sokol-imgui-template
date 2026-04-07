set -e

echo "Building sokol_basisu libraries..."

build_lib_arm64_release() {
    dst=$1
    echo "  Building $dst (arm64 release)"
    clang++ -c -O2 -DNDEBUG -fPIC -arch arm64 -I../c -Ilibrary library/sokol_basisu.cpp -o sokol_basisu_tmp.o
    ar rcs "$dst" sokol_basisu_tmp.o
    rm sokol_basisu_tmp.o
}

build_lib_arm64_debug() {
    dst=$1
    echo "  Building $dst (arm64 debug)"
    clang++ -c -O2 -DNDEBUG -fPIC -arch arm64 -I../c -Ilibrary library/sokol_basisu.cpp -o sokol_basisu_tmp.o
    ar rcs "$dst" sokol_basisu_tmp.o
    rm sokol_basisu_tmp.o
}

echo "ARM64 + Metal + Release"
build_lib_arm64_release sokol_basisu_macos_arm64_metal_release.a

echo "ARM64 + Metal + Debug"
build_lib_arm64_debug sokol_basisu_macos_arm64_metal_debug.a

echo "Done. Libraries created:"
ls -la *.a
