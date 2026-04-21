package sgltf

import "core:strings"
import "vendor:cgltf"
import "core:math/linalg"
import stbi "vendor:stb/image"
import basisu "../sokol/basisu/"
import sg "../sokol/gfx"

Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32


INVALID_INDEX :: -1
SCENE_MAX_BUFFERS    :: 512
SCENE_MAX_IMAGES     :: 256
SCENE_MAX_MATERIALS  :: 128
SCENE_MAX_PIPELINES  :: 16
SCENE_MAX_PRIMITIVES :: 128
SCENE_MAX_MESHES     :: 16
SCENE_MAX_NODES      :: 32

Matrix :: linalg.Matrix4f32

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

Metallic_Images :: struct {
	base_color:            i32,
	metallic_roughness:    i32,
	normal:                i32,
	occlusion:             i32,
	emissive:              i32,
	specular:              i32,
}

Metallic_Material :: struct {
	fs_params: Metallic_Params,
	images:     Metallic_Images,
}

Material :: struct {
	is_metallic: bool,
	metallic:    Metallic_Material,
}

Primitive :: struct {
	pipeline:        i32,
	material:        i32,
	vertex_buffers:  Vertex_Buffer_Mapping,
	index_buffer:    i32,
	base_element:    i32,
	num_elements:    i32,
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
	creation_params: struct {
		buffers: [SCENE_MAX_BUFFERS]Buffer_Creation_Params,
		images:  [SCENE_MAX_IMAGES]Image_Sampler_Creation_Params,
	},
	shader:    sg.Shader,
}

Vertex_Buffer_Mapping :: struct {
	num:    i32,
	buffer: [sg.MAX_VERTEXBUFFER_BINDSLOTS]i32,
}

Pipeline_Cache_Params :: struct {
	layout:     sg.Vertex_Layout_State,
	prim_type:  sg.Primitive_Type,
	index_type: sg.Index_Type,
	alpha:      bool,
}

Pipeline_Cache :: struct {
	items: [SCENE_MAX_PIPELINES]Pipeline_Cache_Params,
}

gltf_to_sg_min_filter :: proc (gltf_filter: cgltf.filter_type) -> sg.Filter {
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

gltf_to_sg_mag_filter :: proc (gltf_filter: cgltf.filter_type) -> sg.Filter {
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

gltf_to_sg_mipmap_filter :: proc (gltf_filter: cgltf.filter_type) -> sg.Filter {
	#partial switch gltf_filter {
	case .nearest, .linear, .nearest_mipmap_nearest, .linear_mipmap_nearest: return .NEAREST
	case .nearest_mipmap_linear, .linear_mipmap_linear: return .LINEAR
	}
	return .LINEAR
}

gltf_to_sg_wrap :: proc (gltf_wrap: cgltf.wrap_mode) -> sg.Wrap {
	#partial switch gltf_wrap {
	case .clamp_to_edge: return .CLAMP_TO_EDGE
	case .mirrored_repeat: return .MIRRORED_REPEAT
	case .repeat: return .REPEAT
	}
	return .REPEAT
}

gltf_attr_type_to_vs_input_slot :: proc (attr_type: cgltf.attribute_type) -> i32 {
	#partial switch attr_type {
	case .position: return ATTR_metallic_position
	case .normal: return ATTR_metallic_normal
	case .texcoord: return ATTR_metallic_texcoord
	}
	return INVALID_INDEX
}

gltf_to_vertex_format :: proc (acc: ^cgltf.accessor) -> sg.Vertex_Format {
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

gltf_to_prim_type :: proc (prim_type: cgltf.primitive_type) -> sg.Primitive_Type {
	#partial switch prim_type {
	case .points: return .POINTS
	case .lines: return .LINES
	case .line_strip: return .LINE_STRIP
	case .triangles: return .TRIANGLES
	case .triangle_strip: return .TRIANGLE_STRIP
	}
	return .TRIANGLES
}

gltf_to_index_type :: proc (prim: ^cgltf.primitive) -> sg.Index_Type {
	if prim.indices != nil {
		if prim.indices.component_type == .r_16u {
			return .UINT16
		} else {
			return .UINT32
		}
	}
	return .NONE
}

create_vertex_buffer_mapping_for_gltf_primitive :: proc (gltf: ^cgltf.data, prim: ^cgltf.primitive) -> Vertex_Buffer_Mapping {
	mappping: Vertex_Buffer_Mapping
	for i in 0..<sg.MAX_VERTEXBUFFER_BINDSLOTS {
		mappping.buffer[i] = INVALID_INDEX
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

create_sg_buffers_for_gltf_buffer :: proc (gltf_buffer_index: i32, data: sg.Range, scene: ^Scene) {
	for i in 0..<scene.num_buffers {
		p := &scene.creation_params.buffers[i]
		if p.gltf_buffer_index == gltf_buffer_index {
			sg.init_buffer(scene.buffers[i], {
				usage = p.usage,
				data = {
					ptr = cast(rawptr)(uintptr(data.ptr) + uintptr(p.offset)),
					size = uint(p.size),
				},
			})
		}
	}
}

create_sg_image_samplers_for_gltf_image :: proc "c" (gltf_image_index: i32, data: sg.Range, scene: ^Scene) {
	for i in 0..<scene.num_images {
		p := &scene.creation_params.images[i]
		if p.gltf_image_index == gltf_image_index {
			if p.has_basisu {
				scene.images[i].img = basisu.make_image(data);
				scene.images[i].tex_view = sg.make_view({
				    texture = { image = scene.images[i].img },
				});
			} else {	
				width, height, channels_in_file: i32
				desired_channels : i32 = 4
				pixels := stbi.load_from_memory(cast([^]byte)(data.ptr), i32(data.size), &width, &height, &channels_in_file, desired_channels)
				
				scene.images[i].img = sg.make_image({
					width = i32(width),
					height = i32(height),
					pixel_format = .RGBA8,
					data = {mip_levels = {0 = {ptr = pixels, size = uint(width * height * desired_channels)}}},
				})

				scene.images[i].tex_view = sg.make_view({
					texture = { image = scene.images[i].img },
				})

				stbi.image_free(pixels)
			}

			scene.images[i].smp = sg.make_sampler({
				min_filter = p.min_filter,
				mag_filter = p.mag_filter,
				mipmap_filter = p.mipmap_filter,
				wrap_u = p.wrap_s,
				wrap_v = p.wrap_t,
			})
		}
	}
}

create_sg_layout_for_gltf_primitive :: proc (gltf: ^cgltf.data, prim: ^cgltf.primitive, vbuf_map: ^Vertex_Buffer_Mapping) -> sg.Vertex_Layout_State {
	layout: sg.Vertex_Layout_State

	textcoord_missing := true
	for attr_index in 0..<len(prim.attributes) {
		attr := &prim.attributes[attr_index]
		attr_slot := gltf_attr_type_to_vs_input_slot(attr.type)

		if (attr.type == .texcoord) {
			textcoord_missing = false
		}

		if attr_slot != INVALID_INDEX {
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

pipelines_equal :: proc (p0, p1: ^Pipeline_Cache_Params) -> bool {
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

create_sg_pipeline_for_gltf_primitive :: proc (gltf: ^cgltf.data, prim: ^cgltf.primitive, vbuf_map: ^Vertex_Buffer_Mapping, scene: ^Scene, pip_cache: ^Pipeline_Cache) -> i32 {
	pip_params := Pipeline_Cache_Params {
		layout = create_sg_layout_for_gltf_primitive(gltf, prim, vbuf_map),
		prim_type = gltf_to_prim_type(prim.type),
		index_type = gltf_to_index_type(prim),
		alpha = prim.material.alpha_mode != .opaque,
	}

	for i in 0..<scene.num_pipelines {
		if pipelines_equal(&pip_cache.items[i], &pip_params) {
			return i
		}
	}

	if scene.num_pipelines < SCENE_MAX_PIPELINES {
		pip_cache.items[scene.num_pipelines] = pip_params
		scene.pipelines[scene.num_pipelines] = sg.make_pipeline({
			layout = pip_params.layout,
			shader = scene.shader,
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
		scene.num_pipelines += 1
	}

	return scene.num_pipelines - 1
}

build_transform_for_gltf_node :: proc (gltf: ^cgltf.data, node: ^cgltf.node) -> Matrix {
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

ParseNodesResult :: enum  {
	Success,
	TooManyNodes,
}

gltf_parse_nodes :: proc (gltf: ^cgltf.data, scene: ^Scene) -> ParseNodesResult {
	if len(gltf.nodes) > SCENE_MAX_NODES {
		return .TooManyNodes
	}

	for node_index in 0..<len(gltf.nodes) {
		gltf_node := &gltf.nodes[node_index]
		if gltf_node.mesh != nil {
			node := &scene.nodes[scene.num_nodes]
			node.mesh = i32(cgltf.mesh_index(gltf, gltf_node.mesh))
			node.transform = build_transform_for_gltf_node(gltf, gltf_node)
			scene.num_nodes += 1
		}
	}
	return .Success
}

ParseMeshesResult :: enum  {
	Success,
	TooManyMeshes,
	TooManyPrimitives,
}

gltf_parse_meshes :: proc (gltf: ^cgltf.data, scene: ^Scene, pip_cache: ^Pipeline_Cache) -> ParseMeshesResult {
	if len(gltf.meshes) > SCENE_MAX_MESHES {
		return .TooManyMeshes
	}
	scene.num_meshes = i32(len(gltf.meshes))

	for mesh_index in 0..<len(gltf.meshes) {
		gltf_mesh := &gltf.meshes[mesh_index]

		if i32(len(gltf_mesh.primitives)) + scene.num_primitives > SCENE_MAX_PRIMITIVES {
			return .TooManyPrimitives
		}

		mesh := &scene.meshes[mesh_index]
		mesh.first_primitive = scene.num_primitives
		mesh.num_primitives = i32(len(gltf_mesh.primitives))

		for prim_index in 0..<len(gltf_mesh.primitives) {
			gltf_prim := &gltf_mesh.primitives[prim_index]
			prim := &scene.primitives[scene.num_primitives]

			prim.vertex_buffers = create_vertex_buffer_mapping_for_gltf_primitive(gltf, gltf_prim)
			prim.pipeline = create_sg_pipeline_for_gltf_primitive(gltf, gltf_prim, &prim.vertex_buffers, scene, pip_cache)
			prim.material = i32(cgltf.material_index(gltf, gltf_prim.material))

			if gltf_prim.indices != nil {
				prim.index_buffer = i32(cgltf.buffer_view_index(gltf, gltf_prim.indices.buffer_view))
				prim.base_element = 0
				prim.num_elements = i32(gltf_prim.indices.count)
			} else {
				prim.index_buffer = INVALID_INDEX
				prim.base_element = 0
				if len(gltf_prim.attributes) > 0 {
					prim.num_elements = i32(gltf_prim.attributes[0].data.count)
				} else {
					prim.num_elements = 0
				}
			}

			scene.num_primitives += 1
		}
	}
	return .Success
}

ParseImagesResult :: enum  {
	Success,
	TooManyImages,
}

gltf_parse_images :: proc (gltf: ^cgltf.data, scene: ^Scene) -> ParseImagesResult {
	if len(gltf.textures) > SCENE_MAX_IMAGES {
		return .TooManyImages
	}

	scene.num_images = i32(len(gltf.textures))
	for i in 0..<scene.num_images {
		gltf_tex := &gltf.textures[i]
		p := &scene.creation_params.images[i]
		p.gltf_image_index = i32(cgltf.image_index(gltf, gltf_tex.image_))
		assert(p.gltf_image_index >= 0)
		p.has_basisu = strings.contains(string(gltf_tex.image_.uri), ".basis")
		p.min_filter = gltf_tex.sampler != nil ? gltf_to_sg_min_filter(gltf_tex.sampler.min_filter) : .LINEAR
		p.mag_filter = gltf_tex.sampler != nil ? gltf_to_sg_mag_filter(gltf_tex.sampler.mag_filter) : .LINEAR
		p.mipmap_filter = gltf_tex.sampler != nil ? gltf_to_sg_mipmap_filter(gltf_tex.sampler.min_filter) : .LINEAR
		p.wrap_s = gltf_tex.sampler != nil ? gltf_to_sg_wrap(gltf_tex.sampler.wrap_s) : .REPEAT
		p.wrap_t = gltf_tex.sampler != nil ? gltf_to_sg_wrap(gltf_tex.sampler.wrap_t) : .REPEAT
	}
	return .Success
}


ParseBuffersResult :: enum  {
	Success,
	TooManyBuffers,
}

gltf_parse_buffers :: proc (gltf: ^cgltf.data, scene: ^Scene) -> ParseBuffersResult {
	if len(gltf.buffer_views) > SCENE_MAX_BUFFERS {
		return .TooManyBuffers
	}

	scene.num_buffers = i32(len(gltf.buffer_views))
	for i in 0..<scene.num_buffers {
		gltf_buf_view := &gltf.buffer_views[i]
		p := &scene.creation_params.buffers[i]
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
		scene.buffers[i] = sg.alloc_buffer()
	}
	return .Success
}

ParseMaterialsResult :: enum  {
	Success,
	TooManyMaterials,
}

gltf_parse_materials :: proc (gltf: ^cgltf.data, scene: ^Scene) -> ParseMaterialsResult {
	if len(gltf.materials) > SCENE_MAX_MATERIALS {
		return .TooManyMaterials
	}
	scene.num_materials = i32(len(gltf.materials))

	for i in 0..<scene.num_materials {
		gltf_mat := &gltf.materials[i]
		scene_mat := &scene.materials[i]

		scene_mat.is_metallic = bool(gltf_mat.has_pbr_metallic_roughness)

		if scene_mat.is_metallic {
			src := &gltf_mat.pbr_metallic_roughness
			dst := &scene_mat.metallic
			
			dst.fs_params.base_color_factor = src.base_color_factor
			dst.fs_params.emissive_factor = gltf_mat.emissive_factor			
			dst.fs_params.metallic_factor = src.metallic_factor
			dst.fs_params.roughness_factor = src.roughness_factor
			dst.fs_params.specular_factor = gltf_mat.specular.specular_factor

			dst.images = Metallic_Images{
				base_color = src.base_color_texture.texture != nil ? i32(cgltf.texture_index(gltf, src.base_color_texture.texture)) : INVALID_INDEX,
				metallic_roughness = src.metallic_roughness_texture.texture != nil ? i32(cgltf.texture_index(gltf, src.metallic_roughness_texture.texture)) : INVALID_INDEX,
				normal = gltf_mat.normal_texture.texture != nil ? i32(cgltf.texture_index(gltf, gltf_mat.normal_texture.texture)) : INVALID_INDEX,
				occlusion = gltf_mat.occlusion_texture.texture != nil ? i32(cgltf.texture_index(gltf, gltf_mat.occlusion_texture.texture)) : INVALID_INDEX,
				emissive = gltf_mat.emissive_texture.texture != nil ? i32(cgltf.texture_index(gltf, gltf_mat.emissive_texture.texture)) : INVALID_INDEX,
				specular = gltf_mat.specular.specular_texture.texture != nil ? i32(cgltf.texture_index(gltf, gltf_mat.specular.specular_texture.texture)) : INVALID_INDEX,
			};
		}
	}
	return .Success
}

