package utils

import "../sgltf"
import "../sokol/fetch"
import sg "../sokol/gfx"
import "base:runtime"
import "core:fmt"
import "core:strings"
import "vendor:cgltf"


// statically allocated buffers for file downloads
SFETCH_NUM_CHANNELS :: 1
SFETCH_NUM_LANES :: 4

MAX_FILE_SIZE :: 64 * 1024 * 1024 // 64 MB should be enough for most glTF files and their resources, adjust as needed

sfetch_buffers: [SFETCH_NUM_CHANNELS][SFETCH_NUM_LANES][MAX_FILE_SIZE]u8

Image_Fetch_Userdata :: struct {
	image_index: i32,
	state:       ^Global_State,
}

send_image_request :: proc "c" (
	state: ^Global_State,
	image_index: i32,
	basepath: string,
	uri: cstring,
) {
	context = runtime.default_context()
	full_path := strings.concatenate([]string{basepath, string(uri)})
	user_data := Image_Fetch_Userdata {
		image_index = i32(image_index),
		state       = state,
	}
	req := fetch.sfetch_request_t {
		path      = strings.clone_to_cstring(full_path),
		callback  = gltf_image_fetch_callback,
		user_data = fetch.sfetch_range_t{&user_data, size_of(user_data)},
	}
	fetch.sfetch_send(&req)
}

gltf_image_fetch_callback :: proc "c" (response: ^fetch.sfetch_response_t) {
	context = runtime.default_context()
	if response.dispatched {
		buf := fetch.sfetch_range_t {
			ptr  = &sfetch_buffers[response.channel][response.lane],
			size = MAX_FILE_SIZE,
		}
		fetch.sfetch_bind_buffer(response.handle, buf)
	} else if response.fetched {
		user_data := cast(^Image_Fetch_Userdata)(response.user_data)
		sgltf.create_sg_image_samplers_for_gltf_image(
			user_data.image_index,
			sg.Range{ptr = response.data.ptr, size = uint(response.data.size)},
			&user_data.state.scene,
		)
	}
	if response.finished {
		if response.failed {
			user_data := cast(^Image_Fetch_Userdata)(response.user_data)
			fmt.println("Failed to fetch image at index %d", user_data.image_index)
			// state.failed = true
		}
	}
}


Buffer_Fetch_Userdata :: struct {
	buffer_index: i32,
	state:        ^Global_State,
}

send_buffer_request :: proc "c" (
	state: ^Global_State,
	buffer_index: i32,
	basepath: string,
	uri: cstring,
) {
	context = runtime.default_context()
	full_path := strings.concatenate([]string{basepath, string(uri)})
	user_data := Buffer_Fetch_Userdata {
		buffer_index = i32(buffer_index),
		state        = state,
	}
	req := fetch.sfetch_request_t {
		path      = strings.clone_to_cstring(full_path),
		callback  = gltf_buffer_fetch_callback,
		user_data = fetch.sfetch_range_t{&user_data, size_of(user_data)},
	}
	fetch.sfetch_send(&req)
}

gltf_buffer_fetch_callback :: proc "c" (response: ^fetch.sfetch_response_t) {
	context = runtime.default_context()
	if response.dispatched {
		buf := fetch.sfetch_range_t {
			ptr  = &sfetch_buffers[response.channel][response.lane],
			size = MAX_FILE_SIZE,
		}
		fetch.sfetch_bind_buffer(response.handle, buf)
	} else if response.fetched {
		user_data := cast(^Buffer_Fetch_Userdata)(response.user_data)

		sgltf.create_sg_buffers_for_gltf_buffer(
			user_data.buffer_index,
			sg.Range{ptr = response.data.ptr, size = uint(response.data.size)},
			&user_data.state.scene,
		)
	}
	if response.finished {
		if response.failed {
			user_data := cast(^Buffer_Fetch_Userdata)(response.user_data)
			fmt.println("Failed to fetch buffer at index %d", user_data.buffer_index)
			user_data.state.failed = true
		}
	}
}

Gltf_Fetch_Userdata :: struct {
	state:    ^Global_State,
	basepath: string,
}

send_gltf_request :: proc(state: ^Global_State, basepath: string, filename: string) {
	req := fetch.sfetch_request_t {
		path      = strings.clone_to_cstring(strings.concatenate([]string{basepath, filename})),
		callback  = gltf_fetch_callback,
		user_data = fetch.sfetch_range_t {
			&Gltf_Fetch_Userdata{state, basepath},
			size_of(Gltf_Fetch_Userdata),
		},
	}
	fetch.sfetch_send(&req)
}

gltf_fetch_callback :: proc "c" (response: ^fetch.sfetch_response_t) {
	context = runtime.default_context()
	if response.dispatched {
		buf := fetch.sfetch_range_t {
			ptr  = &sfetch_buffers[response.channel][response.lane],
			size = MAX_FILE_SIZE,
		}
		fetch.sfetch_bind_buffer(response.handle, buf)
	} else if response.fetched {
		user_data := cast(^Gltf_Fetch_Userdata)(response.user_data)
		basepath := user_data.basepath
		state := user_data.state

		options := cgltf.options{}
		gltf_data, result := cgltf.parse(
			options,
			cast([^]u8)(response.data.ptr),
			uint(response.data.size),
		)
		defer cgltf.free(gltf_data)
		if result != .success {
			fmt.println("Failed to parse glTF file, error code:", result)
			state.failed = true
			return
		}

		if gltf_data.file_type == .glb {
			if (cgltf.load_buffers(options, gltf_data, strings.clone_to_cstring(basepath)) !=
				   .success) {
				fmt.println("Failed to load glTF buffers")
				state.failed = true
				return
			}
		}

		parse_buffers_result := sgltf.gltf_parse_buffers(gltf_data, &state.scene)
		if parse_buffers_result != .Success {
			fmt.println("Failed to parse buffers, error code:", parse_buffers_result)
			state.failed = true
		}
		for i in 0 ..< len(gltf_data.buffers) {
			gltf_buf := &gltf_data.buffers[i]
			if gltf_buf.uri != nil && (cast([^]u8)(gltf_buf.uri))[0] != 0 {
				send_buffer_request(state, i32(i), basepath, gltf_buf.uri)
			} else if gltf_data.file_type == .glb {
				// For GLB files, the buffer data is already loaded in memory, so we can create the sg_buffers directly
				sgltf.create_sg_buffers_for_gltf_buffer(
					i32(i),
					sg.Range{ptr = gltf_buf.data, size = uint(gltf_buf.size)},
					&state.scene,
				)
			}
		}

		parse_images_result := sgltf.gltf_parse_images(gltf_data, &state.scene)
		if parse_images_result != .Success {
			fmt.println("Failed to parse images, error code:", parse_images_result)
			state.failed = true
		}
		for i in 0 ..< len(gltf_data.images) {
			gltf_img := &gltf_data.images[i]
			if gltf_img.uri != nil && (cast([^]u8)(gltf_img.uri))[0] != 0 {
				send_image_request(state, i32(i), basepath, gltf_img.uri)
			} else if gltf_data.file_type == .glb {
				sgltf.create_sg_image_samplers_for_gltf_image(
					i32(i),
					sg.Range{ptr = cast(rawptr)(uintptr(gltf_img.buffer_view.buffer.data) + uintptr(gltf_img.buffer_view.offset)), size = uint(gltf_img.buffer_view.size)},
					&state.scene,
				)
			}
		}

		parse_materials_result := sgltf.gltf_parse_materials(gltf_data, &state.scene)
		if parse_materials_result != .Success {
			fmt.println("Failed to parse materials, error code:", parse_materials_result)
			state.failed = true
		}

		parse_meshes_result := sgltf.gltf_parse_meshes(gltf_data, &state.scene, &state.pip_cache)
		if parse_meshes_result != .Success {
			fmt.println("Failed to parse meshes, error code:", parse_meshes_result)
			state.failed = true
		}

		parse_nodes_result := sgltf.gltf_parse_nodes(gltf_data, &state.scene)
		if parse_nodes_result != .Success {
			fmt.println("Failed to parse nodes, error code:", parse_nodes_result)
			state.failed = true
		}
	}
	if response.finished {
		if response.failed {
			fmt.println("Failed to fetch glTF file")
			user_data := cast(^Gltf_Fetch_Userdata)(response.user_data)
			state := user_data.state
			state.failed = true
		}
	}
}
