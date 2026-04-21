package odin_gltf_sokol

import "core:log"
import "core:fmt"
import "core:c"
import "core:strings"
import "base:runtime"
import "core:math"
import "core:math/linalg"
import "core:image"
import "vendor:cgltf"
import sg "../sokol/gfx"
import sapp "../sokol/app"
import sglue "../sokol/glue"
import slog "../sokol/log"
import fetch "../sokol/fetch"
import basisu "../sokol/basisu/"
import sgltf "gltf-sokol"

Gltf_Input :: struct {
	filepath: string,
	basepath: string,
	shader_desc_fn: proc "c"(backend: sg.Backend) -> sg.Shader_Desc,
}

gltf_input : Gltf_Input = {
	filepath = "Ferrari.gltf",
	basepath = "/Users/nico/Development/delve-framework/assets/meshes/multiple-materials/ferrari/",
	shader_desc_fn = acc_shader_desc,
}

// gltf_input : Gltf_Input = {
// 	filepath = "DamagedHelmet.gltf",
// 	basepath = "/Users/nico/Development/sokol-samples/sapp/data/gltf/DamagedHelmet/",
// 	shader_desc_fn = metallic_shader_desc,
// }

//  gltf_filepath :: "Ferrari.gltf"
// gltf_basepath :: "/Users/nico/Development/delve-framework/assets/meshes/multiple-materials/ferrari/"
// gltf_filepath :: "ferrari.gltf"
// gltf_basepath :: "/Users/nico/Development/odin-sokol-imgui-template/src/odin-gltf-sokol/models/ferrari/"
// gltf_filepath :: "DamagedHelmet.gltf"
// gltf_basepath :: "/Users/nico/Development/sokol-samples/sapp/data/gltf/DamagedHelmet/"
// gltf_filepath :: "Box With Spaces.gltf"
// gltf_basepath :: "/Users/nico/Development/odin-sokol-imgui-template/src/odin-gltf-sokol/models/"

// TODO Galli: maybe I can use /Users/nico/Development/sokol-samples/sapp/offscreen-sapp.c to render to an image and save that for comparisson in tests

// statically allocated buffers for file downloads
SFETCH_NUM_CHANNELS :: 1
SFETCH_NUM_LANES :: 4

MAX_FILE_SIZE :: 32 * 1024 * 1024

sfetch_buffers: [SFETCH_NUM_CHANNELS][SFETCH_NUM_LANES][MAX_FILE_SIZE]u8

state: struct {
	failed:             bool,
	pass_action_ok:     sg.Pass_Action,
	pass_action_failed: sg.Pass_Action,
	smp:                sg.Sampler,
	scene:              sgltf.Scene,
	rx, ry:             f32,
	root_transform:     sgltf.Matrix,
	pip_cache: sgltf.Pipeline_Cache,
	placeholders: struct {
		white:  sg.View,
		normal: sg.View,
		black:  sg.View,
		smp:    sg.Sampler,
	},
	point_light: Light_Params,
}

Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32

camera: Camera

Camera :: struct {
	latitude:  f32,
	longitude: f32,
	distance:  f32,
	eye_pos:   Vec3,
	target:    Vec3,
	up:       Vec3,
	view:     sgltf.Matrix,
	proj:     sgltf.Matrix,
	view_proj: sgltf.Matrix,
}

cam_init :: proc "c" (cam: ^Camera, desc: struct {latitude, longitude, distance: f32}) {
	cam.latitude = desc.latitude
	cam.longitude = desc.longitude
	cam.distance = desc.distance
	cam.eye_pos = {0, 0, 0}
	cam.target = {0, 0, 0}
	cam.up = {0, 1, 0}
}

cam_update :: proc "c" (cam: ^Camera, fb_width, fb_height: i32) {
	lat := cam.latitude * math.PI / 180.0
	lon := cam.longitude * math.PI / 180.0

	cam.eye_pos.x = cam.target.x + cam.distance * math.cos(lat) * math.sin(lon)
	cam.eye_pos.y = cam.target.y + cam.distance * math.sin(lat)
	cam.eye_pos.z = cam.target.z + cam.distance * math.cos(lat) * math.cos(lon)

	aspect := cast(f32)fb_width / cast(f32)fb_height
	cam.proj = linalg.matrix4_perspective_f32(math.PI / 4.0, aspect, 0.01, 100.0)
	cam.view = linalg.matrix4_look_at_f32(cam.eye_pos, cam.target, cam.up)
	cam.view_proj = cam.proj * cam.view
}

// TODO handle events for camera control (mouse drag for rotation, scroll for zoom)
cam_handle_event :: proc "c" (cam: ^Camera, ev: ^sapp.Event) {
	// #partial switch ev.type {
	// case .MOUSE_DOWN:
	// 	if ev.mouse_button == .LEFT {
	// 		switch ev.modifiers {
	// 		case .SHIFT:
	// 			cam.distance = clamp(cam.distance + cast(f32)ev.scroll_y * 0.5, 0.5, 100.0)
	// 		case:
	// 			old_lon := cam.longitude
	// 			old_lat := cam.latitude
	// 			// In real implementation, track mouse drag for rotation
	// 		}
	// 	}
	// case .MOUSE_SCROLL:
	// 	cam.distance = clamp(cam.distance - cast(f32)ev.scroll_y * 0.1, 0.5, 100.0)
	// }
}

init :: proc "c" () {
	context = runtime.default_context()
	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
		sampler_pool_size = 256,
		buffer_pool_size = 512,
		image_pool_size = 256,
	})

	cam_init(&camera, {
		latitude = 25.0,
		longitude = 0.0,
		distance = 8.5,
	})

	// setup sokol-fetch with 2 channels and 6 lanes per channel,
    // we'll use one channel for mesh data and the other for textures
    fetch.sfetch_setup(&(fetch.sfetch_desc_t){
		max_requests = 128,
        num_channels = SFETCH_NUM_CHANNELS,
        num_lanes = SFETCH_NUM_LANES,
		logger = { func = slog.func },
    })

	state.pass_action_ok = {
		colors = {
			0 = { load_action = .CLEAR, clear_value = {r = 0.0, g = 0.569, b = 0.918, a = 1.0}},
		},
	}
	state.pass_action_failed = {
		colors = {
			0 = { load_action = .CLEAR, clear_value = {r = 1.0, g = 0.0, b = 0.0, a = 1.0}},
		},
	}

	fmt.println("Backend:", sg.query_backend())

	state.scene.shader = sg.make_shader(gltf_input.shader_desc_fn(sg.query_backend()))

	state.point_light = Light_Params {
		light_pos = {10.0, 10.0, 10.0},
		light_range = 200.0,
		light_color = {1.0, 1.0, 1.0},
		light_intensity = 700.0,
	}

	white_pixels: [64]u32
	for i in 0..<64 {
		white_pixels[i] = 0xFFFFFFFF
	}
	state.placeholders.white = sg.make_view(sg.View_Desc{
		texture = {
			image = sg.make_image(sg.Image_Desc{
				width = 8,
				height = 8,
				pixel_format = .RGBA8,
				data = {mip_levels = {0 = {ptr = &white_pixels, size = size_of(white_pixels)}}},
			}),
		},
	})

	normal_pixels: [64]u32
	for i in 0..<64 {
		normal_pixels[i] = 0xFF0000FF
	}
	state.placeholders.normal = sg.make_view(sg.View_Desc{
		texture = {
			image = sg.make_image(sg.Image_Desc{
				width = 8,
				height = 8,
				pixel_format = .RGBA8,
				data = {mip_levels = {0 = {ptr = &normal_pixels, size = size_of(normal_pixels)}}},
			}),
		},
	})

	black_pixels: [64]u32
	for i in 0..<64 {
		black_pixels[i] = 0xFF000000
	}
	state.placeholders.black = sg.make_view(sg.View_Desc{
		texture = {
			image = sg.make_image(sg.Image_Desc{
				width = 8,
				height = 8,
				pixel_format = .RGBA8,
				data = {mip_levels = {0 = {ptr = &black_pixels, size = size_of(black_pixels)}}},
			}),
		},
	})

	state.placeholders.smp = sg.make_sampler(sg.Sampler_Desc{
		min_filter = .NEAREST,
		mag_filter = .NEAREST,
	})

	basisu.setup()

	fmt.println("Loading glTF file: ", gltf_input.filepath)

	full_path := strings.concatenate([]string{gltf_input.basepath, string(gltf_input.filepath)})
	req := fetch.sfetch_request_t{
		path = strings.clone_to_cstring(full_path),
		callback = gltf_fetch_callback,
	}
	fetch.sfetch_send(&req)
}

gltf_parse :: proc "c" (file_data: fetch.sfetch_range_t) {
	context = runtime.default_context()
	options := cgltf.options {}
	gltf_data, result := cgltf.parse(options, cast([^]u8)(file_data.ptr), uint(file_data.size))
	if result != .success {
		fmt.println("Failed to parse glTF file, error code:", result)
		state.failed = true
		return
	}
	defer cgltf.free(gltf_data)

	parse_buffers_result := sgltf.gltf_parse_buffers(gltf_data, &state.scene)
	if parse_buffers_result != .Success {
		fmt.println("Failed to parse buffers, error code:", parse_buffers_result)
		state.failed = true
	}
	for i in 0..<len(gltf_data.buffers) {
		gltf_buf := &gltf_data.buffers[i]
		if gltf_buf.uri != nil && (cast([^]u8)(gltf_buf.uri))[0] != 0 {
			send_buffer_request(i32(i), gltf_buf.uri)
		}
	}

	parse_images_result := sgltf.gltf_parse_images(gltf_data, &state.scene)
	if parse_images_result != .Success {
		fmt.println("Failed to parse images, error code:", parse_images_result)
		state.failed = true
	}
	for i in 0..<len(gltf_data.images) {
		gltf_img := &gltf_data.images[i]
		if gltf_img.uri != nil && (cast([^]u8)(gltf_img.uri))[0] != 0 {
			send_image_request(i32(i), gltf_img.uri)
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

gltf_fetch_callback :: proc "c" (response: ^fetch.sfetch_response_t) {
	context = runtime.default_context()
	if response.dispatched {
		buf := fetch.sfetch_range_t{
			ptr = &sfetch_buffers[response.channel][response.lane],
			size = MAX_FILE_SIZE,
		}
		fetch.sfetch_bind_buffer(response.handle, buf)
	} else if response.fetched {
		data := fetch.sfetch_range_t{response.data.ptr, response.data.size}
		gltf_parse(data)
	}
	if response.finished {
		if response.failed {
			fmt.println("Failed to fetch glTF file")
			state.failed = true
		}
	}
}

send_buffer_request :: proc "c" (buffer_index: i32, uri: cstring) {
	context = runtime.default_context()
	full_path := strings.concatenate([]string{gltf_input.basepath, string(uri)})
	user_data := Buffer_Fetch_Userdata {
		buffer_index = i32(buffer_index),
	}
	req := fetch.sfetch_request_t{
		path = strings.clone_to_cstring(full_path),
		callback = gltf_buffer_fetch_callback,
		user_data = fetch.sfetch_range_t{&user_data, size_of(user_data)},
	}
	fetch.sfetch_send(&req)
}

Buffer_Fetch_Userdata :: struct {
	buffer_index: i32,
}

gltf_buffer_fetch_callback :: proc "c" (response: ^fetch.sfetch_response_t) {
	context = runtime.default_context()
	if response.dispatched {
		buf := fetch.sfetch_range_t{
			ptr = &sfetch_buffers[response.channel][response.lane],
			size = MAX_FILE_SIZE,
		}
		fetch.sfetch_bind_buffer(response.handle, buf)
	} else if response.fetched {
		user_data := cast(^Buffer_Fetch_Userdata)(response.user_data)
		gltf_buffer_index := user_data.buffer_index
		sgltf.create_sg_buffers_for_gltf_buffer(gltf_buffer_index, sg.Range{
			ptr = response.data.ptr,
			size = uint(response.data.size),
		}, &state.scene)
	}
	if response.finished {
		if response.failed {
			user_data := cast(^Buffer_Fetch_Userdata)(response.user_data)
			fmt.println("Failed to fetch buffer at index %d", user_data.buffer_index)
			state.failed = true
		}
	}
}

send_image_request :: proc "c" (image_index: i32, uri: cstring) {
	context = runtime.default_context()
	full_path := strings.concatenate([]string{gltf_input.basepath, string(uri)})
	user_data := Image_Fetch_Userdata {
		image_index = i32(image_index)
	}
	req := fetch.sfetch_request_t{
		path = strings.clone_to_cstring(full_path),
		callback = gltf_image_fetch_callback,
		user_data = fetch.sfetch_range_t{&user_data, size_of(user_data)},
	}
	fetch.sfetch_send(&req)
}

Image_Fetch_Userdata :: struct {
	image_index: i32
}

gltf_image_fetch_callback :: proc "c" (response: ^fetch.sfetch_response_t) {
	context = runtime.default_context()
	if response.dispatched {
		buf := fetch.sfetch_range_t{
			ptr = &sfetch_buffers[response.channel][response.lane],
			size = MAX_FILE_SIZE,
		}
		fetch.sfetch_bind_buffer(response.handle, buf)
	} else if response.fetched {
		user_data := cast(^Image_Fetch_Userdata)(response.user_data)
		gltf_image_index := user_data.image_index
		sgltf.create_sg_image_samplers_for_gltf_image(gltf_image_index, sg.Range{
			ptr = response.data.ptr,
			size = uint(response.data.size),
		}, &state.scene)
	}
	if response.finished {
		if response.failed {
			user_data := cast(^Image_Fetch_Userdata)(response.user_data)
			fmt.println("Failed to fetch image at index %d", user_data.image_index)
			// state.failed = true
		}
	}
}

frame :: proc "c" () {
	context = runtime.default_context()
	fetch.sfetch_dowork()

	// state.rx += 0.016
	state.root_transform = linalg.matrix4_rotate(state.rx, Vec3{0, 1, 0})

	fb_width := sapp.width()
	fb_height := sapp.height()
	cam_update(&camera, fb_width, fb_height)

	if state.failed {
		sg.begin_pass({action = state.pass_action_failed, swapchain = sglue.swapchain()})
		sg.end_pass()
	} else {
		sg.begin_pass({action = state.pass_action_ok, swapchain = sglue.swapchain()})

		for node_index in 0..<state.scene.num_nodes {
			node := &state.scene.nodes[node_index]
			vs_params := Vs_Params {
				model = node.transform * state.root_transform,
				view_proj = camera.view_proj,
				eye_pos = {camera.eye_pos.x, camera.eye_pos.y, camera.eye_pos.z},
			}

			mesh := &state.scene.meshes[node.mesh]
			for i in 0..<mesh.num_primitives {
				prim := &state.scene.primitives[i + mesh.first_primitive]
				mat := &state.scene.materials[prim.material]

				bind: sg.Bindings
				for vb_slot in 0..<prim.vertex_buffers.num {
					bind.vertex_buffers[vb_slot] = state.scene.buffers[prim.vertex_buffers.buffer[vb_slot]]
				}
				if prim.index_buffer != sgltf.INVALID_INDEX {
					bind.index_buffer = state.scene.buffers[prim.index_buffer]
				}

				sg.apply_pipeline(state.scene.pipelines[prim.pipeline])
				sg.apply_uniforms(UB_vs_params, sg.Range{&vs_params, size_of(vs_params)})
				sg.apply_uniforms(UB_light_params, sg.Range{&state.point_light, size_of(state.point_light)})

				if mat.is_metallic {
					base_color_tex : Maybe(sg.View) = mat.metallic.images.base_color == -1 ? nil : state.scene.images[mat.metallic.images.base_color].tex_view
					base_color_smp : Maybe(sg.Sampler) = mat.metallic.images.base_color == -1 ? nil : state.scene.images[mat.metallic.images.base_color].smp
					metallic_roughness_tex : Maybe(sg.View) = mat.metallic.images.metallic_roughness == -1 ? nil : state.scene.images[mat.metallic.images.metallic_roughness].tex_view
					metallic_roughness_smp : Maybe(sg.Sampler) = mat.metallic.images.metallic_roughness == -1 ? nil : state.scene.images[mat.metallic.images.metallic_roughness].smp
					normal_tex : Maybe(sg.View) = mat.metallic.images.normal == -1 ? nil : state.scene.images[mat.metallic.images.normal].tex_view
					normal_smp : Maybe(sg.Sampler) = mat.metallic.images.normal == -1 ? nil : state.scene.images[mat.metallic.images.normal].smp
					occlusion_tex : Maybe(sg.View) = mat.metallic.images.occlusion == -1 ? nil : state.scene.images[mat.metallic.images.occlusion].tex_view
					occlusion_smp : Maybe(sg.Sampler) = mat.metallic.images.occlusion == -1 ? nil : state.scene.images[mat.metallic.images.occlusion].smp
					emissive_tex : Maybe(sg.View) = mat.metallic.images.emissive == -1 ? nil : state.scene.images[mat.metallic.images.emissive].tex_view
					emissive_smp : Maybe(sg.Sampler) = mat.metallic.images.emissive == -1 ? nil : state.scene.images[mat.metallic.images.emissive].smp
					specular_tex : Maybe(sg.View) = mat.metallic.images.specular == -1 ? nil : state.scene.images[mat.metallic.images.specular].tex_view
					specular_smp : Maybe(sg.Sampler) = mat.metallic.images.specular == -1 ? nil : state.scene.images[mat.metallic.images.specular].smp

					// these have not loaded yet, so we need to bind placeholders and update them once they are loaded, otherwise the pipeline will be incomplete and will crash
					// TODO Nico: we should ideally not bind the pipeline until all resources are ready, but for now we will just bind placeholders and update them once the real resources are loaded, this is not ideal but it works
					if (base_color_tex == nil || base_color_tex.?.id == 0) {
						// fmt.println("Warning: base color texture for material", prim.material, "is not valid, using white placeholder")
						base_color_tex = state.placeholders.white;
						base_color_smp = state.placeholders.smp;
					}

					if (metallic_roughness_tex == nil || metallic_roughness_tex.?.id == 0) {
						// fmt.println("Warning: metallic-roughness texture for material", prim.material, "is not valid, using white placeholder")
						metallic_roughness_tex = state.placeholders.white;
						metallic_roughness_smp = state.placeholders.smp;
					}

					if (normal_tex == nil || normal_tex.?.id == 0) {
						// fmt.println("Warning: normal texture for material", prim.material, "is not valid, using normal placeholder")
						normal_tex = state.placeholders.normal;
						normal_smp = state.placeholders.smp;
					}

					if (occlusion_tex == nil || occlusion_tex.?.id == 0) {
						// fmt.println("Warning: occlusion texture for material", prim.material, "is not valid, using black placeholder")
						occlusion_tex = state.placeholders.black;
						occlusion_smp = state.placeholders.smp;
					}

					if (emissive_tex == nil || emissive_tex.?.id == 0) {
						// fmt.println("Warning: emissive texture for material", prim.material, "is not valid, using black placeholder")
						emissive_tex = state.placeholders.black;
						emissive_smp = state.placeholders.smp;
					}

					if (specular_tex == nil || specular_tex.?.id == 0) {
						// fmt.println("Warning: specular texture for material", prim.material, "is not valid, using black placeholder")
						specular_tex = state.placeholders.black;
						specular_smp = state.placeholders.smp;
					}

					bind.views[VIEW_base_color_tex] = base_color_tex.?
					bind.views[VIEW_metallic_roughness_tex] = metallic_roughness_tex.?
					bind.views[VIEW_normal_tex] = normal_tex.?
					bind.views[VIEW_occlusion_tex] = occlusion_tex.?
					bind.views[VIEW_emissive_tex] = emissive_tex.?
					bind.views[VIEW_specular_tex] = specular_tex.?
					bind.samplers[SMP_base_color_smp] = base_color_smp.?
					bind.samplers[SMP_metallic_roughness_smp] = metallic_roughness_smp.?
					bind.samplers[SMP_normal_smp] = normal_smp.?
					bind.samplers[SMP_occlusion_smp] = occlusion_smp.?
					bind.samplers[SMP_emissive_smp] = emissive_smp.?
					bind.samplers[SMP_specular_smp] = specular_smp.?

					sg.apply_uniforms(UB_metallic_params, sg.Range{&mat.metallic.fs_params, size_of(mat.metallic.fs_params)})
				}

				sg.apply_bindings(bind)
				sg.draw(prim.base_element, prim.num_elements, 1)
			}
		}

		sg.end_pass()
	}

	sg.commit()
}

cleanup :: proc "c" () {
	basisu.shutdown()
	fetch.sfetch_shutdown()
	sg.shutdown()
}

main :: proc () {
	context.logger = log.create_console_logger()
	sapp.run({
		init_cb = init,
		frame_cb = frame,
		cleanup_cb = cleanup,
		width = 800,
		height = 600,
		window_title = "Opensim",
		icon = { sokol_default = true },
		logger = { func = slog.func },
	})
}
