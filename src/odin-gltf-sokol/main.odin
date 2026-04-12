package odin_gltf_sokol

import "core:log"
import "core:fmt"
import "core:c"
import "core:strings"
import "base:runtime"
import "core:math"
import "core:math/linalg"
import "core:image"
import stbi "vendor:stb/image"
import "vendor:cgltf"
import sg "../sokol/gfx"
import sapp "../sokol/app"
import sglue "../sokol/glue"
import slog "../sokol/log"
import fetch "../sokol/fetch"
import basisu "../sokol/basisu/"

// gltf_filepath :: "Ferrari.gltf"
// gltf_basepath :: "/Users/nico/Development/delve-framework/assets/meshes/multiple-materials/ferrari/"
 gltf_filepath :: "DamagedHelmet.gltf"
 gltf_basepath :: "/Users/nico/Development/sokol-samples/sapp/data/gltf/DamagedHelmet/"
// gltf_filepath :: "Box With Spaces.gltf"
// gltf_basepath :: "/Users/nico/Development/odin-sokol-imgui-template/src/odin-gltf-sokol/models/"

SCENE_INVALID_INDEX :: -1
SCENE_MAX_BUFFERS    :: 128
SCENE_MAX_IMAGES     :: 128
SCENE_MAX_MATERIALS  :: 32
SCENE_MAX_PIPELINES  :: 16
SCENE_MAX_PRIMITIVES :: 32
SCENE_MAX_MESHES     :: 16
SCENE_MAX_NODES      :: 32


// statically allocated buffers for file downloads
SFETCH_NUM_CHANNELS :: 1
SFETCH_NUM_LANES :: 4

MAX_FILE_SIZE :: 16 * 1024 * 1024

sfetch_buffers: [SFETCH_NUM_CHANNELS][SFETCH_NUM_LANES][MAX_FILE_SIZE]u8

Metallic_Images :: struct {
	base_color:            i32,
	metallic_roughness:    i32,
	normal:                i32,
	occlusion:             i32,
	emissive:             i32,
}

Metallic_Material :: struct {
	fs_params: Metallic_Params,
	images:     Metallic_Images,
}

Material :: struct {
	is_metallic: bool,
	metallic:    Metallic_Material,
}

Vertex_Buffer_Mapping :: struct {
	num:    i32,
	buffer: [sg.MAX_VERTEXBUFFER_BINDSLOTS]i32,
}

Primitive :: struct {
	pipeline:        i32,
	material:        i32,
	vertex_buffers:  Vertex_Buffer_Mapping,
	index_buffer:    i32,
	base_element:    i32,
	num_elements:    i32,
}

Mesh :: struct {
	first_primitive: i32,
	num_primitives: i32,
}

Node :: struct {
	mesh:     i32,
	transform: Matrix,
}

Image :: struct {
	img:      sg.Image,
	tex_view: sg.View,
	smp:      sg.Sampler,
}

Scene :: struct {
	num_buffers:    i32,
	num_images:     i32,
	num_pipelines:  i32,
	num_materials:  i32,
	num_primitives: i32,
	num_meshes:     i32,
	num_nodes:      i32,
	buffers:    [SCENE_MAX_BUFFERS]sg.Buffer,
	images:    [SCENE_MAX_IMAGES]Image,
	pipelines: [SCENE_MAX_PIPELINES]sg.Pipeline,
	materials: [SCENE_MAX_MATERIALS]Material,
	primitives:    [SCENE_MAX_PRIMITIVES]Primitive,
	meshes:    [SCENE_MAX_MESHES]Mesh,
	nodes:     [SCENE_MAX_NODES]Node,
}

Buffer_Creation_Params :: struct {
	usage:           sg.Buffer_Usage,
	offset:          i32,
	size:            i32,
	gltf_buffer_index: i32,
}

Image_Sampler_Creation_Params :: struct {
	min_filter:         sg.Filter,
	mag_filter:         sg.Filter,
	mipmap_filter:      sg.Filter,
	wrap_s:             sg.Wrap,
	wrap_t:             sg.Wrap,
	gltf_image_index:   i32,
	has_basisu:         bool,
}

Pipeline_Cache_Params :: struct {
	layout:     sg.Vertex_Layout_State,
	prim_type:  sg.Primitive_Type,
	index_type: sg.Index_Type,
	alpha:      bool,
}

state: struct {
	failed:             bool,
	pass_action_ok:     sg.Pass_Action,
	pass_action_failed: sg.Pass_Action,
	shader:             sg.Shader,
	smp:                sg.Sampler,
	scene:              Scene,
	rx, ry:             f32,
	root_transform:     Matrix,
	creation_params: struct {
		buffers: [SCENE_MAX_BUFFERS]Buffer_Creation_Params,
		images:  [SCENE_MAX_IMAGES]Image_Sampler_Creation_Params,
	},
	pip_cache: struct {
		items: [SCENE_MAX_PIPELINES]Pipeline_Cache_Params,
	},
	placeholders: struct {
		white:  sg.View,
		normal: sg.View,
		black:  sg.View,
		smp:    sg.Sampler,
	},
	point_light: Light_Params,
}

Matrix :: linalg.Matrix4f32
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
	view:     Matrix,
	proj:     Matrix,
	view_proj: Matrix,
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
	})

	cam_init(&camera, {
		latitude = 25.0,
		longitude = 0.0,
		distance = 8.5,
	})

	// setup sokol-fetch with 2 channels and 6 lanes per channel,
    // we'll use one channel for mesh data and the other for textures
    fetch.sfetch_setup(&(fetch.sfetch_desc_t){
		max_requests = 64,
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

	state.shader = sg.make_shader(metallic_shader_desc(sg.query_backend()))

	state.point_light = Light_Params {
		light_pos = {10.0, 10.0, 10.0},
		light_range = 200.0,
		light_color = {1.0, 1.5, 2.0},
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

	fmt.println("Loading glTF file: ", gltf_filepath)

	full_path := strings.concatenate([]string{gltf_basepath, string(gltf_filepath)})
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

	gltf_parse_buffers(gltf_data)
	gltf_parse_images(gltf_data)
	gltf_parse_materials(gltf_data)
	gltf_parse_meshes(gltf_data)
	gltf_parse_nodes(gltf_data)
}

gltf_fetch_callback :: proc "c" (response: ^fetch.sfetch_response_t) {
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
			state.failed = true
		}
	}
}

gltf_parse_buffers :: proc "c" (gltf: ^cgltf.data) {
	context = runtime.default_context()
	if len(gltf.buffer_views) > SCENE_MAX_BUFFERS {
		fmt.println("Too many buffer views in glTF file (max: %d), current: %d", SCENE_MAX_BUFFERS, len(gltf.buffer_views))
		state.failed = true
		return
	}

	state.scene.num_buffers = i32(len(gltf.buffer_views))
	for i in 0..<state.scene.num_buffers {
		gltf_buf_view := &gltf.buffer_views[i]
		p := &state.creation_params.buffers[i]
		p.gltf_buffer_index = i32(cgltf.buffer_index(gltf, gltf_buf_view.buffer))
		p.offset = i32(gltf_buf_view.offset)
		p.size = i32(gltf_buf_view.size)

		// it may be the case that bufferView does not have a target,
		// in that case we have to inspect the accessors that reference this bufferView to determine the usage 
		// We are not doing that yet so it will break.
		// TODO fix this by inspecting accessors and determining usage based on that, for now we just assume it's a vertex buffer
		if gltf_buf_view.type == .indices {
			p.usage.index_buffer = true
		} else {
			p.usage.vertex_buffer = true
		}
		state.scene.buffers[i] = sg.alloc_buffer()
	}

	for i in 0..<len(gltf.buffers) {
		gltf_buf := &gltf.buffers[i]
		if gltf_buf.uri != nil && (cast([^]u8)(gltf_buf.uri))[0] != 0 {
			send_buffer_request(i32(i), gltf_buf.uri)
		}
	}
}

send_buffer_request :: proc "c" (buffer_index: i32, uri: cstring) {
	context = runtime.default_context()
	full_path := strings.concatenate([]string{gltf_basepath, string(uri)})
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
	if response.dispatched {
		buf := fetch.sfetch_range_t{
			ptr = &sfetch_buffers[response.channel][response.lane],
			size = MAX_FILE_SIZE,
		}
		fetch.sfetch_bind_buffer(response.handle, buf)
	} else if response.fetched {
		user_data := cast(^Buffer_Fetch_Userdata)(response.user_data)
		gltf_buffer_index := user_data.buffer_index
		create_sg_buffers_for_gltf_buffer(gltf_buffer_index, sg.Range{
			ptr = response.data.ptr,
			size = uint(response.data.size),
		})
	}
	if response.finished {
		if response.failed {
			state.failed = true
		}
	}
}

gltf_parse_images :: proc "c" (gltf: ^cgltf.data) {
	context = runtime.default_context()
	if len(gltf.textures) > SCENE_MAX_IMAGES {
		fmt.println("Too many textures in glTF file (max: %d), current: %d", SCENE_MAX_IMAGES, len(gltf.textures))
		state.failed = true
		return
	}

	state.scene.num_images = i32(len(gltf.textures))
	for i in 0..<state.scene.num_images {
		gltf_tex := &gltf.textures[i]
		p := &state.creation_params.images[i]
		p.gltf_image_index = i32(cgltf.image_index(gltf, gltf_tex.image_))
		assert(p.gltf_image_index >= 0)
		p.has_basisu = strings.contains(string(gltf_tex.image_.uri), ".basis")
		p.min_filter = gltf_tex.sampler != nil ? gltf_to_sg_min_filter(gltf_tex.sampler.min_filter) : .LINEAR
		p.mag_filter = gltf_tex.sampler != nil ? gltf_to_sg_mag_filter(gltf_tex.sampler.mag_filter) : .LINEAR
		p.mipmap_filter = gltf_tex.sampler != nil ? gltf_to_sg_mipmap_filter(gltf_tex.sampler.min_filter) : .LINEAR
		p.wrap_s = gltf_tex.sampler != nil ? gltf_to_sg_wrap(gltf_tex.sampler.wrap_s) : .REPEAT
		p.wrap_t = gltf_tex.sampler != nil ? gltf_to_sg_wrap(gltf_tex.sampler.wrap_t) : .REPEAT
		
	}

	for i in 0..<len(gltf.images) {
		gltf_img := &gltf.images[i]
		if gltf_img.uri != nil && (cast([^]u8)(gltf_img.uri))[0] != 0 {
			send_image_request(i32(i), gltf_img.uri)
		}
	}
}

send_image_request :: proc "c" (image_index: i32, uri: cstring) {
	context = runtime.default_context()
	full_path := strings.concatenate([]string{gltf_basepath, string(uri)})
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
		create_sg_image_samplers_for_gltf_image(gltf_image_index, sg.Range{
			ptr = response.data.ptr,
			size = uint(response.data.size),
		})
	}
	if response.finished {
		if response.failed {
			user_data := cast(^Image_Fetch_Userdata)(response.user_data)
			fmt.println("Failed to fetch image at index %d", user_data.image_index)
			// state.failed = true
		}
	}
}

gltf_to_sg_min_filter :: proc "c" (gltf_filter: cgltf.filter_type) -> sg.Filter {
	#partial switch gltf_filter {
	case .nearest: return .NEAREST
	case .linear: return .LINEAR
	case .nearest_mipmap_nearest: return .NEAREST
	case .linear_mipmap_nearest: return .LINEAR
	case .nearest_mipmap_linear: return .NEAREST
	case .linear_mipmap_linear: return .LINEAR
	}
	return .LINEAR
}

gltf_to_sg_mag_filter :: proc "c" (gltf_filter: cgltf.filter_type) -> sg.Filter {
	#partial switch gltf_filter {
	case .nearest: return .NEAREST
	case .linear: return .LINEAR
	case .nearest_mipmap_nearest: return .NEAREST
	case .linear_mipmap_nearest: return .LINEAR
	case .nearest_mipmap_linear: return .NEAREST
	case .linear_mipmap_linear: return .LINEAR
	}
	return .LINEAR
}

gltf_to_sg_mipmap_filter :: proc "c" (gltf_filter: cgltf.filter_type) -> sg.Filter {
	#partial switch gltf_filter {
	case .nearest, .linear, .nearest_mipmap_nearest, .linear_mipmap_nearest: return .NEAREST
	case .nearest_mipmap_linear, .linear_mipmap_linear: return .LINEAR
	}
	return .LINEAR
}

gltf_to_sg_wrap :: proc "c" (gltf_wrap: cgltf.wrap_mode) -> sg.Wrap {
	#partial switch gltf_wrap {
	case .clamp_to_edge: return .CLAMP_TO_EDGE
	case .mirrored_repeat: return .MIRRORED_REPEAT
	case .repeat: return .REPEAT
	}
	return .REPEAT
}

create_sg_buffers_for_gltf_buffer :: proc "c" (gltf_buffer_index: i32, data: sg.Range) {
	for i in 0..<state.scene.num_buffers {
		p := &state.creation_params.buffers[i]
		if p.gltf_buffer_index == gltf_buffer_index {
			sg.init_buffer(state.scene.buffers[i], sg.Buffer_Desc{
				usage = p.usage,
				data = {
					ptr = cast(rawptr)(uintptr(data.ptr) + uintptr(p.offset)),
					size = uint(p.size),
				},
			})
		}
	}
}

create_sg_image_samplers_for_gltf_image :: proc "c" (gltf_image_index: i32, data: sg.Range) {
	context = runtime.default_context()
	for i in 0..<state.scene.num_images {
		p := &state.creation_params.images[i]
		if p.gltf_image_index == gltf_image_index {
			if p.has_basisu {
				state.scene.images[i].img = basisu.make_image(data);
				state.scene.images[i].tex_view = sg.make_view(sg.View_Desc{
				    texture = { image = state.scene.images[i].img },
				});
			} else {	
				width, height, channels_in_file: i32
				desired_channels : i32 = 4
				pixels := stbi.load_from_memory(cast([^]byte)(data.ptr), i32(data.size), &width, &height, &channels_in_file, desired_channels)
				
				state.scene.images[i].img = sg.make_image(sg.Image_Desc{
					width = i32(width),
					height = i32(height),
					pixel_format = .RGBA8,
					data = {mip_levels = {0 = {ptr = pixels, size = uint(width * height * desired_channels)}}},
				})

				state.scene.images[i].tex_view = sg.make_view(sg.View_Desc{
					texture = { image = state.scene.images[i].img },
				})

				stbi.image_free(pixels)
			}

			state.scene.images[i].smp = sg.make_sampler((sg.Sampler_Desc){
				min_filter = p.min_filter,
				mag_filter = p.mag_filter,
				mipmap_filter = p.mipmap_filter,
				wrap_u = p.wrap_s,
				wrap_v = p.wrap_t,
			})
		}
	}
}

gltf_parse_materials :: proc "c" (gltf: ^cgltf.data) {
	context = runtime.default_context()
	if len(gltf.materials) > SCENE_MAX_MATERIALS {
		fmt.println("Too many materials in glTF file (max: %d), current: %d", SCENE_MAX_MATERIALS, len(gltf.materials))
		state.failed = true
		return
	}
	state.scene.num_materials = i32(len(gltf.materials))

	for i in 0..<state.scene.num_materials {
		gltf_mat := &gltf.materials[i]
		scene_mat := &state.scene.materials[i]

		scene_mat.is_metallic = bool(gltf_mat.has_pbr_metallic_roughness)
		fmt.println("Parsing material", i, "is_metallic:", scene_mat.is_metallic)

		if scene_mat.is_metallic {
			src := &gltf_mat.pbr_metallic_roughness
			dst := &scene_mat.metallic
			
			dst.fs_params.base_color_factor = src.base_color_factor
			dst.fs_params.emissive_factor = gltf_mat.emissive_factor			
			dst.fs_params.metallic_factor = src.metallic_factor
			dst.fs_params.roughness_factor = src.roughness_factor

			fmt.println("  Raw - base_color:", dst.fs_params.base_color_factor)
			fmt.println("  Raw - metallic:", dst.fs_params.metallic_factor, "roughness:", dst.fs_params.roughness_factor)

			dst.images = Metallic_Images{
				base_color = src.base_color_texture.texture != nil ? i32(cgltf.texture_index(gltf, src.base_color_texture.texture)) : SCENE_INVALID_INDEX,
				metallic_roughness = src.metallic_roughness_texture.texture != nil ? i32(cgltf.texture_index(gltf, src.metallic_roughness_texture.texture)) : SCENE_INVALID_INDEX,
				normal = gltf_mat.normal_texture.texture != nil ? i32(cgltf.texture_index(gltf, gltf_mat.normal_texture.texture)) : SCENE_INVALID_INDEX,
				occlusion = gltf_mat.occlusion_texture.texture != nil ? i32(cgltf.texture_index(gltf, gltf_mat.occlusion_texture.texture)) : SCENE_INVALID_INDEX,
				emissive = gltf_mat.emissive_texture.texture != nil ? i32(cgltf.texture_index(gltf, gltf_mat.emissive_texture.texture)) : SCENE_INVALID_INDEX,
			};
		}
	}
}

gltf_parse_meshes :: proc "c" (gltf: ^cgltf.data) {
	context = runtime.default_context()
	if len(gltf.meshes) > SCENE_MAX_MESHES {
		fmt.println("Too many meshes in glTF file (max: %d), current: %d", SCENE_MAX_MESHES, len(gltf.meshes))
		state.failed = true
		return
	}
	state.scene.num_meshes = i32(len(gltf.meshes))

	for mesh_index in 0..<len(gltf.meshes) {
		gltf_mesh := &gltf.meshes[mesh_index]

		if i32(len(gltf_mesh.primitives)) + state.scene.num_primitives > SCENE_MAX_PRIMITIVES {
			fmt.println("Too many primitives in glTF file (max: %d), current: %d", SCENE_MAX_PRIMITIVES, i32(len(gltf_mesh.primitives)) + state.scene.num_primitives)
			state.failed = true
			return
		}

		mesh := &state.scene.meshes[mesh_index]
		mesh.first_primitive = state.scene.num_primitives
		mesh.num_primitives = i32(len(gltf_mesh.primitives))

		for prim_index in 0..<len(gltf_mesh.primitives) {
			gltf_prim := &gltf_mesh.primitives[prim_index]
			prim := &state.scene.primitives[state.scene.num_primitives]

			prim.vertex_buffers = create_vertex_buffer_mapping_for_gltf_primitive(gltf, gltf_prim)
			prim.pipeline = create_sg_pipeline_for_gltf_primitive(gltf, gltf_prim, &prim.vertex_buffers)
			prim.material = i32(cgltf.material_index(gltf, gltf_prim.material))

			if gltf_prim.indices != nil {
				prim.index_buffer = i32(cgltf.buffer_view_index(gltf, gltf_prim.indices.buffer_view))
				prim.base_element = 0
				prim.num_elements = i32(gltf_prim.indices.count)
			} else {
				prim.index_buffer = SCENE_INVALID_INDEX
				prim.base_element = 0
				if len(gltf_prim.attributes) > 0 {
					prim.num_elements = i32(gltf_prim.attributes[0].data.count)
				} else {
					prim.num_elements = 0
				}
			}

			state.scene.num_primitives += 1
		}
	}
}

gltf_attr_type_to_vs_input_slot :: proc "c" (attr_type: cgltf.attribute_type) -> i32 {
	#partial switch attr_type {
	case .position: return ATTR_metallic_position
	case .normal: return ATTR_metallic_normal
	case .texcoord: return ATTR_metallic_texcoord
	}
	return SCENE_INVALID_INDEX
}

gltf_to_vertex_format :: proc "c" (acc: ^cgltf.accessor) -> sg.Vertex_Format {
	#partial switch acc.component_type {
	case .r_8:
		if acc.type == .vec4 {
			return bool(acc.normalized) ? .BYTE4N : .BYTE4
		}
	case .r_8u:
		if acc.type == .vec4 {
			return bool(acc.normalized) ? .UBYTE4N : .UBYTE4
		}
	case .r_16:
		#partial switch acc.type {
		case .vec2: return bool(acc.normalized) ? .SHORT2N : .SHORT2
		case .vec4: return bool(acc.normalized) ? .SHORT4N : .SHORT4
		}
	case .r_32f:
		#partial switch acc.type {
		case .scalar: return .FLOAT
		case .vec2: return .FLOAT2
		case .vec3: return .FLOAT3
		case .vec4: return .FLOAT4
		}
	}
	return .INVALID
}

gltf_to_prim_type :: proc "c" (prim_type: cgltf.primitive_type) -> sg.Primitive_Type {
	#partial switch prim_type {
	case .points: return .POINTS
	case .lines: return .LINES
	case .line_strip: return .LINE_STRIP
	case .triangles: return .TRIANGLES
	case .triangle_strip: return .TRIANGLE_STRIP
	}
	return .TRIANGLES
}

gltf_to_index_type :: proc "c" (prim: ^cgltf.primitive) -> sg.Index_Type {
	if prim.indices != nil {
		if prim.indices.component_type == .r_16u {
			return .UINT16
		} else {
			return .UINT32
		}
	}
	return .NONE
}

create_vertex_buffer_mapping_for_gltf_primitive :: proc "c" (gltf: ^cgltf.data, prim: ^cgltf.primitive) -> Vertex_Buffer_Mapping {
	mappping: Vertex_Buffer_Mapping
	for i in 0..<sg.MAX_VERTEXBUFFER_BINDSLOTS {
		mappping.buffer[i] = SCENE_INVALID_INDEX
	}

	for attr_index in 0..<len(prim.attributes) {
		attr := &prim.attributes[attr_index]
		buffer_view_index := i32(cgltf.buffer_view_index(gltf, attr.data.buffer_view))

		found := false
		for i in 0..<mappping.num {
			if mappping.buffer[i] == buffer_view_index {
				found = true
				break
			}
		}

		if !found && mappping.num < sg.MAX_VERTEXBUFFER_BINDSLOTS {
			mappping.buffer[mappping.num] = buffer_view_index
			mappping.num += 1
		}
	}

	return mappping
}

create_sg_layout_for_gltf_primitive :: proc "c" (gltf: ^cgltf.data, prim: ^cgltf.primitive, vbuf_map: ^Vertex_Buffer_Mapping) -> sg.Vertex_Layout_State {
	layout: sg.Vertex_Layout_State

	textcoord_missing := true
	for attr_index in 0..<len(prim.attributes) {
		attr := &prim.attributes[attr_index]
		attr_slot := gltf_attr_type_to_vs_input_slot(attr.type)

		if (attr.type == .texcoord) {
			textcoord_missing = false
		}

		if attr_slot != SCENE_INVALID_INDEX {
			layout.attrs[attr_slot].format = gltf_to_vertex_format(attr.data)
			
			buffer_view_index := i32(cgltf.buffer_view_index(gltf, attr.data.buffer_view))
			for vb_slot in 0..<vbuf_map.num {
				if vbuf_map.buffer[vb_slot] == buffer_view_index {
					layout.attrs[attr_slot].buffer_index = i32(vb_slot)
				}
			}
		}
	}

	if (textcoord_missing) {
		layout.attrs[ATTR_metallic_texcoord].format = .FLOAT2
		// TODO Nico create a dummy vertex buffer with zeroes for texcoords and bind it here
		// layout.attrs[ATTR_metallic_texcoord].buffer_index = DUMMY_TEXCOORD_BUFFER_SLOT
	}

	return layout
}

pipelines_equal :: proc "c" (p0, p1: ^Pipeline_Cache_Params) -> bool {
	if p0.prim_type != p1.prim_type do return false
	if p0.alpha != p1.alpha do return false
	if p0.index_type != p1.index_type do return false

	for i in 0..<sg.MAX_VERTEX_ATTRIBUTES {
		a0 := &p0.layout.attrs[i]
		a1 := &p1.layout.attrs[i]
		if a0.buffer_index != a1.buffer_index ||
		   a0.offset != a1.offset ||
		   a0.format != a1.format {
			return false
		}
	}

	return true
}

create_sg_pipeline_for_gltf_primitive :: proc "c" (gltf: ^cgltf.data, prim: ^cgltf.primitive, vbuf_map: ^Vertex_Buffer_Mapping) -> i32 {
	pip_params := Pipeline_Cache_Params {
		layout = create_sg_layout_for_gltf_primitive(gltf, prim, vbuf_map),
		prim_type = gltf_to_prim_type(prim.type),
		index_type = gltf_to_index_type(prim),
		alpha = prim.material.alpha_mode != .opaque,
	}

	for i in 0..<state.scene.num_pipelines {
		if pipelines_equal(&state.pip_cache.items[i], &pip_params) {
			return i
		}
	}

	if state.scene.num_pipelines < SCENE_MAX_PIPELINES {
		state.pip_cache.items[state.scene.num_pipelines] = pip_params
		state.scene.pipelines[state.scene.num_pipelines] = sg.make_pipeline((sg.Pipeline_Desc){
			layout = pip_params.layout,
			shader = state.shader,
			primitive_type = pip_params.prim_type,
			index_type = pip_params.index_type,
			cull_mode = .BACK,
			face_winding = .CCW,
			depth = {
				write_enabled = !pip_params.alpha,
				compare = .LESS_EQUAL,
			},
			colors = {
				0 = {
					write_mask = pip_params.alpha ? .RGB : {},
					blend = {
						enabled = pip_params.alpha,
						src_factor_rgb = pip_params.alpha ? .SRC_ALPHA : {},
						dst_factor_rgb = pip_params.alpha ? .ONE_MINUS_SRC_ALPHA : {},
					},
				},
			},
		})
		state.scene.num_pipelines += 1
	}

	return state.scene.num_pipelines - 1
}

gltf_parse_nodes :: proc "c" (gltf: ^cgltf.data) {
	context = runtime.default_context()
	if len(gltf.nodes) > SCENE_MAX_NODES {
		fmt.println("Too many nodes in glTF file (max: %d), current: %d", SCENE_MAX_NODES, len(gltf.nodes))
		state.failed = true
		return
	}

	for node_index in 0..<len(gltf.nodes) {
		gltf_node := &gltf.nodes[node_index]
		if gltf_node.mesh != nil {
			node := &state.scene.nodes[state.scene.num_nodes]
			node.mesh = i32(cgltf.mesh_index(gltf, gltf_node.mesh))
			node.transform = build_transform_for_gltf_node(gltf, gltf_node)
			state.scene.num_nodes += 1
		}
	}
}

build_transform_for_gltf_node :: proc "c" (gltf: ^cgltf.data, node: ^cgltf.node) -> Matrix {
	parent_tform := linalg.identity(Matrix)
	if node.parent != nil {
		parent_tform = build_transform_for_gltf_node(gltf, node.parent)
	}

	translate := linalg.identity(Matrix)
	rotate := linalg.identity(Matrix)
	scale := linalg.identity(Matrix)

	if node.has_translation {
		translate = linalg.matrix4_translate(Vec3{node.translation[0], node.translation[1], node.translation[2]})
	}
	if node.has_rotation {
		q := quaternion(x=node.rotation[0], y=node.rotation[1], z=node.rotation[2], w=node.rotation[3])
		rotate = linalg.matrix4_from_quaternion(q)
	}
	if node.has_scale {
		scale = linalg.matrix4_scale(Vec3{node.scale[0], node.scale[1], node.scale[2]})
	}

	if node.has_matrix {
		return Matrix{
			node.matrix_[0], node.matrix_[1], node.matrix_[2], node.matrix_[3],
			node.matrix_[4], node.matrix_[5], node.matrix_[6], node.matrix_[7],
			node.matrix_[8], node.matrix_[9], node.matrix_[10], node.matrix_[11],
			node.matrix_[12], node.matrix_[13], node.matrix_[14], node.matrix_[15],
		}
	}

	return translate * rotate * scale * parent_tform
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
				if prim.index_buffer != SCENE_INVALID_INDEX {
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

					// these have not loaded yet, so we need to bind placeholders and update them once they are loaded, otherwise the pipeline will be incomplete and will crash
					// TODO Nico: we should ideally not bind the pipeline until all resources are ready, but for now we will just bind placeholders and update them once the real resources are loaded, this is not ideal but it works
					if (base_color_tex == nil || base_color_tex.?.id == 0) {
						fmt.println("Warning: base color texture for material", prim.material, "is not valid, using white placeholder")
						base_color_tex = state.placeholders.white;
						base_color_smp = state.placeholders.smp;
					}

					if (metallic_roughness_tex == nil || metallic_roughness_tex.?.id == 0) {
						fmt.println("Warning: metallic-roughness texture for material", prim.material, "is not valid, using white placeholder")
						metallic_roughness_tex = state.placeholders.white;
						metallic_roughness_smp = state.placeholders.smp;
					}

					if (normal_tex == nil || normal_tex.?.id == 0) {
						fmt.println("Warning: normal texture for material", prim.material, "is not valid, using normal placeholder")
						normal_tex = state.placeholders.normal;
						normal_smp = state.placeholders.smp;
					}

					if (occlusion_tex == nil || occlusion_tex.?.id == 0) {
						fmt.println("Warning: occlusion texture for material", prim.material, "is not valid, using black placeholder")
						occlusion_tex = state.placeholders.black;
						occlusion_smp = state.placeholders.smp;
					}

					if (emissive_tex == nil || emissive_tex.?.id == 0) {
						fmt.println("Warning: emissive texture for material", prim.material, "is not valid, using black placeholder")
						emissive_tex = state.placeholders.black;
						emissive_smp = state.placeholders.smp;
					}

					bind.views[VIEW_base_color_tex] = base_color_tex.?
					bind.views[VIEW_metallic_roughness_tex] = metallic_roughness_tex.?
					bind.views[VIEW_normal_tex] = normal_tex.?
					bind.views[VIEW_occlusion_tex] = occlusion_tex.?
					bind.views[VIEW_emissive_tex] = emissive_tex.?
					bind.samplers[SMP_base_color_smp] = base_color_smp.?
					bind.samplers[SMP_metallic_roughness_smp] = metallic_roughness_smp.?
					bind.samplers[SMP_normal_smp] = normal_smp.?
					bind.samplers[SMP_occlusion_smp] = occlusion_smp.?
					bind.samplers[SMP_emissive_smp] = emissive_smp.?

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
		window_title = "GLTF Viewer",
		icon = { sokol_default = true },
		logger = { func = slog.func },
	})
}
