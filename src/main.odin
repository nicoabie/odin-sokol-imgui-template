package main

import "base:runtime"
import "core:fmt"
import "core:strconv"
import "core:image"
import "core:log"
import "core:encoding/ini"
import "core:math"
import "core:math/linalg"
import "core:strings"
import "sgltf"
import sapp "sokol/app"
import basisu "sokol/basisu"
import fetch "sokol/fetch"
import sg "sokol/gfx"
import sglue "sokol/glue"
import slog "sokol/log"
import "utils"

import imgui "imgui"
import simgui "simgui"

Gltf_Input :: struct {
	filepath:       string,
	basepath:       string,
	shader_desc_fn: proc "c" (backend: sg.Backend) -> sg.Shader_Desc,
}

cameras_ini :: "/Users/nico/Downloads/mount_akina_2017/layout_downhill/data/cameras.ini"

// gltf_input: Gltf_Input = {
// 	filepath       = "ferrari.gltf",
// 	basepath       = "/Users/nico/Development/odin-sokol-imgui-template/models/ferrari/",
// 	shader_desc_fn = sgltf.acc_shader_desc,
// }

// gltf_input: Gltf_Input = {
// 	filepath       = "ferrari.glb",
// 	basepath       = "/Users/nico/Downloads/Sim_Dream_Grand_Prix_2024_SF24_EVO_BUILD_2.0/content/cars/gp_2024_sf24evo/output/glb_a/",
// 	shader_desc_fn = sgltf.acc_shader_desc,
// }



// gltf_input: Gltf_Input = {
// 	filepath       = "akina.glb",
// 	basepath       = "/Users/nico/Downloads/mount_akina_2017/output/",
// 	shader_desc_fn = sgltf.acc_shader_desc,
// }

gltf_input: Gltf_Input = {
	filepath       = "Untitled.gltf",
	basepath       = "/Users/nico/Downloads/mount_akina_2017/output/gltf/",
	shader_desc_fn = sgltf.acc_shader_desc,
}

// gltf_input : Gltf_Input = {
// 	filepath = "DamagedHelmet.gltf",
// 	basepath = "/Users/nico/Development/sokol-samples/sapp/data/gltf/DamagedHelmet/",
// 	shader_desc_fn = sgltf.metallic_shader_desc,
// }

// gltf_input : Gltf_Input = {
// 	filepath = "Box With Spaces.gltf",
// 	basepath = "/Users/nico/Development/odin-sokol-imgui-template/models/",
// 	shader_desc_fn = sgltf.metallic_shader_desc,
// }

// TODO Galli: maybe I can use /Users/nico/Development/sokol-samples/sapp/offscreen-sapp.c to render to an image and save that for comparisson in tests

state: utils.Global_State
current_camera_index: i32
all_camera_positions: [65]Vec3
all_camera_forwards: [65]Vec3
num_cameras: i32

Vec3 :: linalg.Vector3f32

camera: utils.Camera

init :: proc "c" () {
	context = runtime.default_context()
	sg.setup(
		{
			environment = sglue.environment(),
			logger = {func = slog.func},
			sampler_pool_size = 256,
			buffer_pool_size = 512,
			image_pool_size = 256,
		},
	)

	state.imgui_context = simgui.setup()
	cameras_map, err, ok := ini.load_map_from_path(cameras_ini, context.allocator)
	defer delete(cameras_map)

	num_cameras = 0

	for header, section in cameras_map {
		if strings.has_prefix(header, "CAMERA_") {
			cam_idx_str := strings.trim_prefix(header, "CAMERA_")
			if len(cam_idx_str) == 0 {
				continue
			}
			cam_idx := int(cam_idx_str[0] - '0')
			for i := 1; i < len(cam_idx_str); i += 1 {
				cam_idx = cam_idx * 10 + int(cam_idx_str[i] - '0')
			}
			if cam_idx < 0 || cam_idx >= len(all_camera_positions) {
				continue
			}
			for key, value in section {
				switch key {
				case "POSITION":
					parts := strings.split(value, ",")
					if len(parts) == 3 {
						x, _ := strconv.parse_f32(strings.trim_space(parts[0]))
						y, _ := strconv.parse_f32(strings.trim_space(parts[1]))
						z, _ := strconv.parse_f32(strings.trim_space(parts[2]))
						all_camera_positions[cam_idx] = Vec3{x, y, z}
					}
				case "FORWARD":
					parts := strings.split(value, ",")
					if len(parts) == 3 {
						x, _ := strconv.parse_f32(strings.trim_space(parts[0]))
						y, _ := strconv.parse_f32(strings.trim_space(parts[1]))
						z, _ := strconv.parse_f32(strings.trim_space(parts[2]))
						all_camera_forwards[cam_idx] = Vec3{x, y, z}
					}
				}
			}
			num_cameras = num_cameras > i32(cam_idx + 1) ? num_cameras : i32(cam_idx + 1)
		}
	}

	cam0_pos := all_camera_positions[0]
	cam0_forward := all_camera_forwards[0]

	cam_distance: f32 = 50.0
	cam_center := cam0_pos + cam0_forward * cam_distance

	forward_norm := linalg.normalize(cam0_forward)
	cam_lat := math.asin(forward_norm.y) * 180.0 / math.PI
	proj_xz := Vec3{forward_norm.x, 0, forward_norm.z}
	proj_xz_norm := linalg.normalize(proj_xz)
	cam_lon := math.acos(proj_xz_norm.z) * 180.0 / math.PI
	if proj_xz_norm.x < 0 {
		cam_lon = -cam_lon
	}

	fmt.println("Loaded", num_cameras, "cameras")
	fmt.println("Initializing camera with:", "pos=", cam0_pos, "forward=", cam0_forward, "center=", cam_center, "lat=", cam_lat, "lon=", cam_lon, "dist=", cam_distance)

	utils.cam_init(&camera, {latitude = cam_lat, longitude = cam_lon, distance = cam_distance, center = cam_center})

	// setup sokol-fetch with 2 channels and 6 lanes per channel,
	// we'll use one channel for mesh data and the other for textures
	fetch.sfetch_setup(
		&(fetch.sfetch_desc_t) {
			max_requests = 128,
			num_channels = utils.SFETCH_NUM_CHANNELS,
			num_lanes = utils.SFETCH_NUM_LANES,
			logger = {func = slog.func},
		},
	)

	state.pass_action_ok = {
		colors = {
			0 = {load_action = .CLEAR, clear_value = {r = 0.0, g = 0.569, b = 0.918, a = 1.0}},
		},
	}
	state.pass_action_failed = {
		colors = {0 = {load_action = .CLEAR, clear_value = {r = 1.0, g = 0.0, b = 0.0, a = 1.0}}},
	}

	fmt.println("Backend:", sg.query_backend())

	state.scene.shader = sg.make_shader(gltf_input.shader_desc_fn(sg.query_backend()))

	state.point_light = sgltf.Light_Params {
		light_pos       = {10.0, 10.0, 10.0},
		light_range     = 200.0,
		light_color     = {1.0, 1.0, 1.0},
		light_intensity = 700.0,
	}

	white_pixels: [64]u32
	for i in 0 ..< 64 {
		white_pixels[i] = 0xFFFFFFFF
	}
	state.placeholders.white = sg.make_view(
		sg.View_Desc {
			texture = {
				image = sg.make_image(
					sg.Image_Desc {
						width = 8,
						height = 8,
						pixel_format = .RGBA8,
						data = {
							mip_levels = {0 = {ptr = &white_pixels, size = size_of(white_pixels)}},
						},
					},
				),
			},
		},
	)

	normal_pixels: [64]u32
	for i in 0 ..< 64 {
		normal_pixels[i] = 0xFF0000FF
	}
	state.placeholders.normal = sg.make_view(
		sg.View_Desc {
			texture = {
				image = sg.make_image(
					sg.Image_Desc {
						width = 8,
						height = 8,
						pixel_format = .RGBA8,
						data = {
							mip_levels = {
								0 = {ptr = &normal_pixels, size = size_of(normal_pixels)},
							},
						},
					},
				),
			},
		},
	)

	black_pixels: [64]u32
	for i in 0 ..< 64 {
		black_pixels[i] = 0xFF000000
	}
	state.placeholders.black = sg.make_view(
		sg.View_Desc {
			texture = {
				image = sg.make_image(
					sg.Image_Desc {
						width = 8,
						height = 8,
						pixel_format = .RGBA8,
						data = {
							mip_levels = {0 = {ptr = &black_pixels, size = size_of(black_pixels)}},
						},
					},
				),
			},
		},
	)

	state.placeholders.smp = sg.make_sampler(
		sg.Sampler_Desc{min_filter = .NEAREST, mag_filter = .NEAREST},
	)

	basisu.setup()

	fmt.println("Loading glTF file: ", gltf_input.filepath)

	utils.send_gltf_request(&state, gltf_input.basepath, gltf_input.filepath)
}


frame :: proc "c" () {
	context = runtime.default_context()
	fetch.sfetch_dowork()

	simgui.new_frame(
		{
			width = sapp.width(),
			height = sapp.height(),
			delta_time = sapp.frame_duration(),
			dpi_scale = sapp.dpi_scale(),
		},
	)

	// state.rx += 0.016
	state.root_transform = linalg.matrix4_rotate(state.rx, Vec3{0, 1, 0})

	fb_width := sapp.width()
	fb_height := sapp.height()
	utils.cam_update(&camera, fb_width, fb_height)

	if state.failed {
		sg.begin_pass({action = state.pass_action_failed, swapchain = sglue.swapchain()})
		simgui.render()
		sg.end_pass()
	} else {
		sg.begin_pass({action = state.pass_action_ok, swapchain = sglue.swapchain()})

		for node_index in 0 ..< state.scene.num_nodes {
			node := &state.scene.nodes[node_index]
			vs_params := sgltf.Vs_Params {
				model     = node.transform * state.root_transform,
				view_proj = camera.view_proj,
				eye_pos   = {camera.eye_pos.x, camera.eye_pos.y, camera.eye_pos.z},
			}

			mesh := &state.scene.meshes[node.mesh]
			for i in 0 ..< mesh.num_primitives {
				prim := &state.scene.primitives[i + mesh.first_primitive]
				mat := &state.scene.materials[prim.material]

				bind: sg.Bindings
				for vb_slot in 0 ..< prim.vertex_buffers.num {
					bind.vertex_buffers[vb_slot] =
						state.scene.buffers[prim.vertex_buffers.buffer[vb_slot]]
				}
				if prim.index_buffer != sgltf.INVALID_INDEX {
					bind.index_buffer = state.scene.buffers[prim.index_buffer]
				}

				sg.apply_pipeline(state.scene.pipelines[prim.pipeline])
				sg.apply_uniforms(sgltf.UB_vs_params, sg.Range{&vs_params, size_of(vs_params)})
				sg.apply_uniforms(
					sgltf.UB_light_params,
					sg.Range{&state.point_light, size_of(state.point_light)},
				)

				if mat.is_metallic {
					base_color_tex: Maybe(sg.View) =
						mat.metallic.images.base_color == -1 ? nil : state.scene.images[mat.metallic.images.base_color].tex_view
					base_color_smp: Maybe(sg.Sampler) =
						mat.metallic.images.base_color == -1 ? nil : state.scene.images[mat.metallic.images.base_color].smp
					metallic_roughness_tex: Maybe(sg.View) =
						mat.metallic.images.metallic_roughness == -1 ? nil : state.scene.images[mat.metallic.images.metallic_roughness].tex_view
					metallic_roughness_smp: Maybe(sg.Sampler) =
						mat.metallic.images.metallic_roughness == -1 ? nil : state.scene.images[mat.metallic.images.metallic_roughness].smp
					normal_tex: Maybe(sg.View) =
						mat.metallic.images.normal == -1 ? nil : state.scene.images[mat.metallic.images.normal].tex_view
					normal_smp: Maybe(sg.Sampler) =
						mat.metallic.images.normal == -1 ? nil : state.scene.images[mat.metallic.images.normal].smp
					occlusion_tex: Maybe(sg.View) =
						mat.metallic.images.occlusion == -1 ? nil : state.scene.images[mat.metallic.images.occlusion].tex_view
					occlusion_smp: Maybe(sg.Sampler) =
						mat.metallic.images.occlusion == -1 ? nil : state.scene.images[mat.metallic.images.occlusion].smp
					emissive_tex: Maybe(sg.View) =
						mat.metallic.images.emissive == -1 ? nil : state.scene.images[mat.metallic.images.emissive].tex_view
					emissive_smp: Maybe(sg.Sampler) =
						mat.metallic.images.emissive == -1 ? nil : state.scene.images[mat.metallic.images.emissive].smp
					specular_tex: Maybe(sg.View) =
						mat.metallic.images.specular == -1 ? nil : state.scene.images[mat.metallic.images.specular].tex_view
					specular_smp: Maybe(sg.Sampler) =
						mat.metallic.images.specular == -1 ? nil : state.scene.images[mat.metallic.images.specular].smp

					// these have not loaded yet, so we need to bind placeholders and update them once they are loaded, otherwise the pipeline will be incomplete and will crash
					// TODO Nico: we should ideally not bind the pipeline until all resources are ready, but for now we will just bind placeholders and update them once the real resources are loaded, this is not ideal but it works
					if (base_color_tex == nil || base_color_tex.?.id == 0) {
						// fmt.println("Warning: base color texture for material", prim.material, "is not valid, using white placeholder")
						base_color_tex = state.placeholders.white
						base_color_smp = state.placeholders.smp
					}

					if (metallic_roughness_tex == nil || metallic_roughness_tex.?.id == 0) {
						// fmt.println("Warning: metallic-roughness texture for material", prim.material, "is not valid, using white placeholder")
						metallic_roughness_tex = state.placeholders.white
						metallic_roughness_smp = state.placeholders.smp
					}

					if (normal_tex == nil || normal_tex.?.id == 0) {
						// fmt.println("Warning: normal texture for material", prim.material, "is not valid, using normal placeholder")
						normal_tex = state.placeholders.normal
						normal_smp = state.placeholders.smp
					}

					if (occlusion_tex == nil || occlusion_tex.?.id == 0) {
						// fmt.println("Warning: occlusion texture for material", prim.material, "is not valid, using black placeholder")
						occlusion_tex = state.placeholders.black
						occlusion_smp = state.placeholders.smp
					}

					if (emissive_tex == nil || emissive_tex.?.id == 0) {
						// fmt.println("Warning: emissive texture for material", prim.material, "is not valid, using black placeholder")
						emissive_tex = state.placeholders.black
						emissive_smp = state.placeholders.smp
					}

					if (specular_tex == nil || specular_tex.?.id == 0) {
						// fmt.println("Warning: specular texture for material", prim.material, "is not valid, using black placeholder")
						specular_tex = state.placeholders.black
						specular_smp = state.placeholders.smp
					}

					bind.views[sgltf.VIEW_base_color_tex] = base_color_tex.?
					bind.views[sgltf.VIEW_metallic_roughness_tex] = metallic_roughness_tex.?
					bind.views[sgltf.VIEW_normal_tex] = normal_tex.?
					bind.views[sgltf.VIEW_occlusion_tex] = occlusion_tex.?
					bind.views[sgltf.VIEW_emissive_tex] = emissive_tex.?
					bind.views[sgltf.VIEW_specular_tex] = specular_tex.?
					bind.samplers[sgltf.SMP_base_color_smp] = base_color_smp.?
					bind.samplers[sgltf.SMP_metallic_roughness_smp] = metallic_roughness_smp.?
					bind.samplers[sgltf.SMP_normal_smp] = normal_smp.?
					bind.samplers[sgltf.SMP_occlusion_smp] = occlusion_smp.?
					bind.samplers[sgltf.SMP_emissive_smp] = emissive_smp.?
					bind.samplers[sgltf.SMP_specular_smp] = specular_smp.?

					sg.apply_uniforms(
						sgltf.UB_metallic_params,
						sg.Range{&mat.metallic.fs_params, size_of(mat.metallic.fs_params)},
					)
				}

				sg.apply_bindings(bind)
				sg.draw(prim.base_element, prim.num_elements, 1)
			}
		}

		set_camera_from_index :: proc(idx: i32) {
		if idx < 0 || idx >= num_cameras {
			return
		}
		current_camera_index = idx
		pos := all_camera_positions[idx]
		fwd := all_camera_forwards[idx]

		fwd_norm := linalg.normalize(fwd)
		lat := math.asin(fwd_norm.y) * 180.0 / math.PI
		proj_xz := Vec3{fwd_norm.x, 0, fwd_norm.z}
		proj_xz_norm := linalg.normalize(proj_xz)
		lon := math.acos(proj_xz_norm.z) * 180.0 / math.PI
		if proj_xz_norm.x < 0 {
			lon = -lon
		}

		dist: f32 = 50.0
		center := pos + fwd * dist

		camera.latitude = lat
		camera.longitude = lon
		camera.distance = dist
		camera.center = center

		fmt.println("Switched to camera", idx, "pos=", pos, "center=", center)
	}

	// begin imgui
	imgui.SetNextWindowPos(imgui.Vec2{10, 10})
	if imgui.Begin("Cameras", nil, {.AlwaysAutoResize}) {
		imgui.Text("Camera %d / %d", current_camera_index, num_cameras - 1)
		changed := imgui.SliderInt("##cam", &current_camera_index, 0, max(0, num_cameras - 1))
		if changed {
			set_camera_from_index(current_camera_index)
		}
		if imgui.Button("<-") && current_camera_index > 0 {
			set_camera_from_index(current_camera_index - 1)
		}
		imgui.SameLine()
		if imgui.Button("->") && current_camera_index < num_cameras - 1 {
			set_camera_from_index(current_camera_index + 1)
		}
	}
	imgui.End()

	imgui.SetNextWindowPos(imgui.Vec2{10, 80})
	if imgui.Begin("Light Position", nil, {.AlwaysAutoResize}) {
		imgui.SliderFloat3("Position", &state.point_light.light_pos, -50, 50)
	}
	imgui.End()
	simgui.render()
		// end imgui

		sg.end_pass()
	}

	sg.commit()
}

cleanup :: proc "c" () {
	basisu.shutdown()
	fetch.sfetch_shutdown()
	sg.shutdown()
}

core_event :: proc "c" (ev: ^sapp.Event) {
	context = runtime.default_context()
	if simgui.handle_event(ev) {
		return
	}
	utils.cam_handle_event(&camera, ev)
}

main :: proc() {
	context.logger = log.create_console_logger()
	sapp.run(
		{
			init_cb = init,
			frame_cb = frame,
			cleanup_cb = cleanup,
			event_cb = core_event,
			width = 800,
			height = 600,
			window_title = "OpenSim",
			icon = {sokol_default = true},
			logger = {func = slog.func},
		},
	)
}
