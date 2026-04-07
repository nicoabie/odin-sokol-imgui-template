import sg "../gfx"

import "core:c"

_ :: c

SOKOL_DEBUG :: #config(SOKOL_DEBUG, ODIN_DEBUG)

DEBUG :: #config(SOKOL_LOG_DEBUG, SOKOL_DEBUG)
USE_GL :: #config(SOKOL_USE_GL, false)
USE_DLL :: #config(SOKOL_DLL, false)

when ODIN_OS == .Windows {
    when USE_DLL {
        when USE_GL {
            when DEBUG { foreign import lib { "../sokol_dll_windows_x64_gl_debug.lib" } }
            else       { foreign import lib { "../sokol_dll_windows_x64_gl_release.lib" } }
        } else {
            when DEBUG { foreign import lib { "../sokol_dll_windows_x64_d3d11_debug.lib" } }
            else       { foreign import lib { "../sokol_dll_windows_x64_d3d11_release.lib" } }
        }
    } else {
        when USE_GL {
            when DEBUG { foreign import lib { "sokol_basisu_windows_x64_gl_debug.lib" } }
            else       { foreign import lib { "sokol_basisu_windows_x64_gl_release.lib" } }
        } else {
            when DEBUG { foreign import lib { "sokol_basisu_windows_x64_d3d11_debug.lib" } }
            else       { foreign import lib { "sokol_basisu_windows_x64_d3d11_release.lib" } }
        }
    }
} else when ODIN_OS == .Darwin {
    when USE_DLL {
             when  USE_GL && ODIN_ARCH == .arm64 &&  DEBUG { foreign import lib { "../dylib/sokol_dylib_macos_arm64_gl_debug.dylib" } }
        else when  USE_GL && ODIN_ARCH == .arm64 && !DEBUG { foreign import lib { "../dylib/sokol_dylib_macos_arm64_gl_release.dylib" } }
        else when  USE_GL && ODIN_ARCH == .amd64 &&  DEBUG { foreign import lib { "../dylib/sokol_dylib_macos_x64_gl_debug.dylib" } }
        else when  USE_GL && ODIN_ARCH == .amd64 && !DEBUG { foreign import lib { "../dylib/sokol_dylib_macos_x64_gl_release.dylib" } }
        else when !USE_GL && ODIN_ARCH == .arm64 &&  DEBUG { foreign import lib { "../dylib/sokol_dylib_macos_arm64_metal_debug.dylib" } }
        else when !USE_GL && ODIN_ARCH == .arm64 && !DEBUG { foreign import lib { "../dylib/sokol_dylib_macos_arm64_metal_release.dylib" } }
        else when !USE_GL && ODIN_ARCH == .amd64 &&  DEBUG { foreign import lib { "../dylib/sokol_dylib_macos_x64_metal_debug.dylib" } }
        else when !USE_GL && ODIN_ARCH == .amd64 && !DEBUG { foreign import lib { "../dylib/sokol_dylib_macos_x64_metal_release.dylib" } }
    } else {
        when USE_GL {
            when ODIN_ARCH == .arm64 {
                when DEBUG { foreign import lib { "sokol_basisu_macos_arm64_gl_debug.a" } }
                else       { foreign import lib { "sokol_basisu_macos_arm64_gl_release.a" } }
            } else {
                when DEBUG { foreign import lib { "sokol_basisu_macos_x64_gl_debug.a" } }
                else       { foreign import lib { "sokol_basisu_macos_x64_gl_release.a" } }
            }
        } else {
            when ODIN_ARCH == .arm64 {
                when DEBUG { foreign import lib { "sokol_basisu_macos_arm64_metal_debug.a", "system:c++" } }
                else       { foreign import lib { "sokol_basisu_macos_arm64_metal_release.a", "system:c++" } }
            } else {
                when DEBUG { foreign import lib { "sokol_basisu_macos_x64_metal_debug.a" } }
                else       { foreign import lib { "sokol_basisu_macos_x64_metal_release.a" } }
            }
        }
    }
} else when ODIN_OS == .Linux {
    when USE_DLL {
        when DEBUG { foreign import lib { "sokol_basisu_linux_x64_gl_debug.so" } }
        else       { foreign import lib { "sokol_basisu_linux_x64_gl_release.so" } }
    } else {
        when DEBUG { foreign import lib { "sokol_basisu_linux_x64_gl_debug.a" } }
        else       { foreign import lib { "sokol_basisu_linux_x64_gl_release.a" } }
    }
} else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
    // Feed sokol_basisu_wasm_gl_debug.a or sokol_basisu_wasm_gl_release.a into emscripten compiler.
    foreign import lib { "env.o" }
} else {
    #panic("This OS is currently not supported")
}