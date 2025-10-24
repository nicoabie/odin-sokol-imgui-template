package simgui

import imgui "../imgui"
import sapp "../sokol/app"
import sg "../sokol/gfx"
import "core:c"
import "core:mem"

ImGuiCol :: enum {
	ImGuiCol_Text = 0,
	ImGuiCol_TextDisabled,
	ImGuiCol_WindowBg, // Background of normal windows
	ImGuiCol_ChildBg, // Background of child windows
	ImGuiCol_PopupBg, // Background of popups, menus, tooltips windows
	ImGuiCol_Border,
	ImGuiCol_BorderShadow,
	ImGuiCol_FrameBg, // Background of checkbox, radio button, plot, slider, text input
	ImGuiCol_FrameBgHovered,
	ImGuiCol_FrameBgActive,
	ImGuiCol_TitleBg, // Title bar
	ImGuiCol_TitleBgActive, // Title bar when focused
	ImGuiCol_TitleBgCollapsed, // Title bar when collapsed
	ImGuiCol_MenuBarBg,
	ImGuiCol_ScrollbarBg,
	ImGuiCol_ScrollbarGrab,
	ImGuiCol_ScrollbarGrabHovered,
	ImGuiCol_ScrollbarGrabActive,
	ImGuiCol_CheckMark, // Checkbox tick and RadioButton circle
	ImGuiCol_SliderGrab,
	ImGuiCol_SliderGrabActive,
	ImGuiCol_Button,
	ImGuiCol_ButtonHovered,
	ImGuiCol_ButtonActive,
	ImGuiCol_Header, // Header* colors are used for CollapsingHeader, TreeNode, Selectable, MenuItem
	ImGuiCol_HeaderHovered,
	ImGuiCol_HeaderActive,
	ImGuiCol_Separator,
	ImGuiCol_SeparatorHovered,
	ImGuiCol_SeparatorActive,
	ImGuiCol_ResizeGrip, // Resize grip in lower-right and lower-left corners of windows.
	ImGuiCol_ResizeGripHovered,
	ImGuiCol_ResizeGripActive,
	ImGuiCol_InputTextCursor, // InputText cursor/caret
	ImGuiCol_TabHovered, // Tab background, when hovered
	ImGuiCol_Tab, // Tab background, when tab-bar is focused & tab is unselected
	ImGuiCol_TabSelected, // Tab background, when tab-bar is focused & tab is selected
	ImGuiCol_TabSelectedOverline, // Tab horizontal overline, when tab-bar is focused & tab is selected
	ImGuiCol_TabDimmed, // Tab background, when tab-bar is unfocused & tab is unselected
	ImGuiCol_TabDimmedSelected, // Tab background, when tab-bar is unfocused & tab is selected
	ImGuiCol_TabDimmedSelectedOverline, // horizontal overline, when tab-bar is unfocused & tab is selected
	ImGuiCol_PlotLines,
	ImGuiCol_PlotLinesHovered,
	ImGuiCol_PlotHistogram,
	ImGuiCol_PlotHistogramHovered,
	ImGuiCol_TableHeaderBg, // Table header background
	ImGuiCol_TableBorderStrong, // Table outer and header borders (prefer using Alpha=1.0 here)
	ImGuiCol_TableBorderLight, // Table inner borders (prefer using Alpha=1.0 here)
	ImGuiCol_TableRowBg, // Table row background (even rows)
	ImGuiCol_TableRowBgAlt, // Table row background (odd rows)
	ImGuiCol_TextLink, // Hyperlink color
	ImGuiCol_TextSelectedBg, // Selected text inside an InputText
	ImGuiCol_TreeLines, // Tree node hierarchy outlines when using ImGuiTreeNodeFlags_DrawLines
	ImGuiCol_DragDropTarget, // Rectangle highlighting a drop target
	ImGuiCol_UnsavedMarker, // Unsaved Document marker (in window title and tabs)
	ImGuiCol_NavCursor, // Color of keyboard/gamepad navigation cursor/rectangle, when visible
	ImGuiCol_NavWindowingHighlight, // Highlight window when using CTRL+TAB
	ImGuiCol_NavWindowingDimBg, // Darken/colorize entire screen behind the CTRL+TAB window list, when active
	ImGuiCol_ModalWindowDimBg, // Darken/colorize entire screen behind a modal window, when one is active
	ImGuiCol_COUNT,
}


Context :: struct {
	cur_dpi_scale:    f32,
	vbuf:             sg.Buffer,
	ibuf:             sg.Buffer,
	font_img:         sg.Image,
	font_smp:         sg.Sampler,
	def_img:          sg.Image,
	def_smp:          sg.Sampler,
	def_shd:          sg.Shader,
	def_pip:          sg.Pipeline,
	// separate shader and pipeline for unfilterable user images
	shd_unfilterable: sg.Shader,
	pip_unfilterable: sg.Pipeline,
	vertices:         []imgui.DrawVert,
	indices:          []imgui.DrawIdx,
	is_osx:           bool,
	// store imgui context so we can restore it for hot-reload
	imgui_context:    ^imgui.Context,
	user_images:      [32]sg.Image,
	user_views:       [32]sg.View,
	user_image_count: c.int,
}
ctx: ^Context

ApplyImGuiTheme :: proc() {
	s := imgui.GetStyle()
	s.WindowRounding = 4.0
	s.FrameRounding = 4.0
	s.GrabRounding = 4.0
	s.WindowBorderSize = 0.0
	s.FrameBorderSize = 0.0
	s.ItemSpacing = imgui.Vec2{8.0, 6.0}

	// accent color (use white/grey only)
	accent_r := cast(f32)0.95
	accent_g := cast(f32)0.95
	accent_b := cast(f32)0.95

	// convenience: set Colors by numeric ImGuiCol indices (matching Dear ImGui enum)
	// Index mapping: 0=Text,1=TextDisabled,2=WindowBg,3=ChildBg,4=PopupBg,5=Border,6=BorderShadow,
	// 7=FrameBg,8=FrameBgHovered,9=FrameBgActive,10=TitleBg,11=TitleBgActive,12=TitleBgCollapsed,
	// 21=Button,22=ButtonHovered,23=ButtonActive,24=Header,25=HeaderHovered,26=HeaderActive,
	// 27=Separator,28=SeparatorHovered,29=SeparatorActive,30=ResizeGrip,33=Tab,34=TabHovered,35=TabActive

	s.Colors[ImGuiCol.ImGuiCol_Text] = imgui.Vec4{0.95, 0.95, 0.95, 1.00} // Text
	s.Colors[ImGuiCol.ImGuiCol_TextDisabled] = imgui.Vec4{0.60, 0.60, 0.60, 1.00} // TextDisabled
	s.Colors[ImGuiCol.ImGuiCol_WindowBg] = imgui.Vec4{0.06, 0.06, 0.06, 0.95} // WindowBg
	s.Colors[ImGuiCol.ImGuiCol_ChildBg] = imgui.Vec4{0.06, 0.06, 0.06, 0.95} // ChildBg
	s.Colors[ImGuiCol.ImGuiCol_PopupBg] = imgui.Vec4{0.06, 0.06, 0.06, 0.95} // PopupBg
	s.Colors[ImGuiCol.ImGuiCol_Border] = imgui.Vec4{0.15, 0.15, 0.15, 0.50} // Border
	s.Colors[ImGuiCol.ImGuiCol_BorderShadow] = imgui.Vec4{0.00, 0.00, 0.00, 0.00} // BorderShadow

	s.Colors[ImGuiCol.ImGuiCol_FrameBg] = imgui.Vec4{0.10, 0.10, 0.12, 0.90} // FrameBg
	s.Colors[ImGuiCol.ImGuiCol_FrameBgHovered] = imgui.Vec4{0.20, 0.20, 0.20, 0.95} // FrameBgHovered
	s.Colors[ImGuiCol.ImGuiCol_FrameBgActive] = imgui.Vec4{0.24, 0.24, 0.24, 0.95} // FrameBgActive

	s.Colors[ImGuiCol.ImGuiCol_TitleBg] = imgui.Vec4{0.08, 0.08, 0.08, 0.95} // TitleBg
	s.Colors[ImGuiCol.ImGuiCol_TitleBgActive] = imgui.Vec4{0.06, 0.06, 0.06, 0.95} // TitleBgActive
	s.Colors[ImGuiCol.ImGuiCol_TitleBgCollapsed] = imgui.Vec4{0.00, 0.00, 0.00, 0.51} // TitleBgCollapsed
	s.Colors[ImGuiCol.ImGuiCol_MenuBarBg] = imgui.Vec4{0.08, 0.08, 0.08, 0.95} // MenuBarBg

	s.Colors[ImGuiCol.ImGuiCol_Button] = imgui.Vec4{0.12, 0.12, 0.14, 0.95} // Button
	s.Colors[ImGuiCol.ImGuiCol_ButtonHovered] = imgui.Vec4 {
		accent_r * 0.85,
		accent_g * 0.85,
		accent_b * 0.85,
		0.95,
	} // ButtonHovered
	s.Colors[ImGuiCol.ImGuiCol_ButtonActive] = imgui.Vec4{0.08, 0.08, 0.08, 0.95} // ButtonActive

	s.Colors[ImGuiCol.ImGuiCol_Header] = imgui.Vec4{0.08, 0.08, 0.08, 0.95} // Header
	s.Colors[ImGuiCol.ImGuiCol_HeaderHovered] = imgui.Vec4 {
		accent_r * 0.85,
		accent_g * 0.85,
		accent_b * 0.85,
		0.95,
	} // HeaderHovered
	s.Colors[ImGuiCol.ImGuiCol_HeaderActive] = imgui.Vec4 {
		accent_r * 0.75,
		accent_g * 0.75,
		accent_b * 0.75,
		0.95,
	} // HeaderActive

	s.Colors[ImGuiCol.ImGuiCol_Separator] = imgui.Vec4{0.12, 0.12, 0.14, 1.00} // Separator
	s.Colors[ImGuiCol.ImGuiCol_SeparatorHovered] = imgui.Vec4 {
		accent_r * 0.85,
		accent_g * 0.85,
		accent_b * 0.85,
		0.95,
	} // SeparatorHovered
	s.Colors[ImGuiCol.ImGuiCol_SeparatorActive] = imgui.Vec4 {
		accent_r * 0.75,
		accent_g * 0.75,
		accent_b * 0.75,
		1.00,
	} // SeparatorActive

	s.Colors[ImGuiCol.ImGuiCol_Tab] = imgui.Vec4{0.10, 0.10, 0.12, 0.95} // Tab
	s.Colors[ImGuiCol.ImGuiCol_TabHovered] = imgui.Vec4 {
		accent_r * 0.85,
		accent_g * 0.85,
		accent_b * 0.85,
		0.95,
	} // TabHovered
	s.Colors[ImGuiCol.ImGuiCol_TabSelected] = imgui.Vec4 {
		accent_r * 0.75,
		accent_g * 0.75,
		accent_b * 0.75,
		0.95,
	} // TabActive

	s.Colors[ImGuiCol.ImGuiCol_CheckMark] = imgui.Vec4 {
		accent_r * 0.85,
		accent_g * 0.85,
		accent_b * 0.85,
		0.95,
	} // CheckMark
	s.Colors[ImGuiCol.ImGuiCol_SliderGrab] = imgui.Vec4 {
		accent_r * 0.85,
		accent_g * 0.85,
		accent_b * 0.85,
		0.95,
	} // SliderGrab
	s.Colors[ImGuiCol.ImGuiCol_SliderGrabActive] = imgui.Vec4 {
		accent_r * 0.75,
		accent_g * 0.75,
		accent_b * 0.75,
		0.95,
	} // SliderGrabActive

	s.Colors[ImGuiCol.ImGuiCol_ScrollbarBg] = imgui.Vec4{0.05, 0.05, 0.06, 0.90} // ScrollbarBg
	s.Colors[ImGuiCol.ImGuiCol_ScrollbarGrab] = imgui.Vec4{0.12, 0.12, 0.14, 0.95} // ScrollbarGrab
	s.Colors[ImGuiCol.ImGuiCol_ScrollbarGrabHovered] = imgui.Vec4 {
		accent_r * 0.85,
		accent_g * 0.85,
		accent_b * 0.85,
		0.95,
	} // ScrollbarGrabHovered
	s.Colors[ImGuiCol.ImGuiCol_ScrollbarGrabActive] = imgui.Vec4 {
		accent_r * 0.75,
		accent_g * 0.75,
		accent_b * 0.75,
		0.95,
	} // ScrollbarGrabActive

	s.Colors[ImGuiCol.ImGuiCol_ResizeGrip] = imgui.Vec4{0.12, 0.12, 0.14, 0.95} // ResizeGrip
	s.Colors[ImGuiCol.ImGuiCol_ResizeGripActive] = imgui.Vec4{0.12, 0.12, 0.14, 0.95} // ResizeGrip
	s.Colors[ImGuiCol.ImGuiCol_ResizeGripHovered] = imgui.Vec4{0.12, 0.12, 0.14, 0.95} // ResizeGrip

	// tooltip
	s.Colors[4] = imgui.Vec4{0.06, 0.06, 0.08, 0.95}
}

setup :: proc() -> ^Context {
	MAX_VERTICES :: 65536 // TODO: this could/should be configurable with the desc

	ctx = new(Context)
	ctx.cur_dpi_scale = 1.0
	ctx.is_osx = is_osx()

	// allocate an intermediate vertex- and index-buffer
	ctx.vertices = make([]imgui.DrawVert, MAX_VERTICES)
	ctx.indices = make([]imgui.DrawIdx, MAX_VERTICES * 3)

	// initialize Dear ImGui
	ctx.imgui_context = imgui.CreateContext()
	io := imgui.GetIO()
	imgui.FontAtlas_AddFontDefault(io.Fonts)
	io.ConfigMacOSXBehaviors = is_osx()
	io.BackendFlags += {.RendererHasVtxOffset, .HasMouseCursors}

	pio := imgui.GetPlatformIO()
	pio.Platform_SetClipboardTextFn = set_clipboard
	pio.Platform_GetClipboardTextFn = get_clipboard

	sg.push_debug_group("sokol-imgui")

	shd_desc := simgui_shader_desc(sg.query_backend())
	ctx.def_shd = sg.make_shader(shd_desc)

	// initialize cached view ids to INVALID
	for i in 0 ..< len(ctx.user_views) {
		ctx.user_views[i].id = sg.INVALID_ID
	}

	pip_desc := sg.Pipeline_Desc {
		label = "sokol-imgui-pipeline",
		shader = ctx.def_shd,
		layout = {
			attrs = {
				ATTR_simgui_position = {
					offset = i32(offset_of(imgui.DrawVert, pos)),
					format = .FLOAT2,
				},
				ATTR_simgui_texcoord0 = {
					offset = i32(offset_of(imgui.DrawVert, uv)),
					format = .FLOAT2,
				},
				ATTR_simgui_color0 = {
					offset = i32(offset_of(imgui.DrawVert, col)),
					format = .UBYTE4N,
				},
			},
			buffers = {0 = {stride = size_of(imgui.DrawVert)}},
		},
		index_type = .UINT16,
		colors = {
			0 = {
				write_mask = .RGB,
				blend = {
					enabled = true,
					src_factor_rgb = .SRC_ALPHA,
					dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
				},
			},
		},
	}
	ctx.def_pip = sg.make_pipeline(pip_desc)

	shd_desc.views[VIEW_tex].texture.sample_type = .UNFILTERABLE_FLOAT
	shd_desc.samplers[SMP_smp].sampler_type = .NONFILTERING
	shd_desc.label = "sokol-imgui-shader-unfilterable"
	ctx.shd_unfilterable = sg.make_shader(shd_desc)
	pip_desc.shader = ctx.shd_unfilterable
	pip_desc.label = "sokol-imgui-pipeline-unfilterable"
	ctx.pip_unfilterable = sg.make_pipeline(pip_desc)

	ctx.vbuf = sg.make_buffer(
		{
			usage = sg.Buffer_Usage{stream_update = true, vertex_buffer = true},
			size = len(ctx.vertices) * size_of(imgui.DrawVert),
			label = "sokol-imgui-vertices",
		},
	)

	ctx.ibuf = sg.make_buffer(
		{
			usage = sg.Buffer_Usage{stream_update = true, index_buffer = true},
			size = len(ctx.indices) * size_of(imgui.DrawIdx),
			label = "sokol-imgui-indices",
		},
	)

	// a default user-image sampler
	ctx.def_smp = sg.make_sampler(
		{
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			wrap_u = .CLAMP_TO_EDGE,
			wrap_v = .CLAMP_TO_EDGE,
			label = "sokol-imgui-default-sampler",
		},
	)

	// a default user image
	def_pixels: [64]u32 = 0xFF
	ctx.def_img = sg.make_image(
		{
			width = 8,
			height = 8,
			pixel_format = .RGBA8,
			data = sg.Image_Data {
				mip_levels = {0 = sg.Range{ptr = &def_pixels, size = size_of(def_pixels)}},
			},
			label = "sokol-imgui-default-image",
		},
	)

	create_fonts_texture(io)
	ApplyImGuiTheme()
	sg.pop_debug_group()

	return ctx
}

set_context :: proc(new_context: ^Context) {
	ctx = new_context
	imgui.SetCurrentContext(ctx.imgui_context)
}

create_fonts_texture :: proc(io: ^imgui.IO) {
	ctx.font_smp = sg.make_sampler(
		{wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE, label = "sokol-imgui-font-sampler"},
	)

	pixels: ^c.uchar
	width, height: c.int
	imgui.FontAtlas_GetTexDataAsRGBA32(io.Fonts, &pixels, &width, &height, nil)

	ctx.font_img = sg.make_image(
		{
			width = width,
			height = height,
			pixel_format = .RGBA8,
			data = sg.Image_Data {
				mip_levels = {
					0 = sg.Range{ptr = pixels, size = uint(width * height) * size_of(u32)},
				},
			},
			label = "sokol-imgui-font-image",
		},
	)
	io.Fonts.TexID = imtextureid_with_sampler(ctx.font_img, ctx.font_smp)
}

destroy_fonts_texture :: proc() {
	// NOTE: it's valid to call the destroy funcs with sg.INVALID_ID
	sg.destroy_sampler(ctx.font_smp)
	sg.destroy_image(ctx.font_img)
	ctx.font_smp.id = sg.INVALID_ID
	ctx.font_img.id = sg.INVALID_ID
}

shutdown :: proc() {
	imgui.DestroyContext()
	sg.destroy_pipeline(ctx.pip_unfilterable)
	sg.destroy_shader(ctx.shd_unfilterable)
	sg.destroy_pipeline(ctx.def_pip)
	sg.destroy_shader(ctx.def_shd)
	sg.destroy_sampler(ctx.font_smp)
	sg.destroy_image(ctx.font_img)
	sg.destroy_sampler(ctx.def_smp)
	sg.destroy_image(ctx.def_img)
	sg.destroy_buffer(ctx.ibuf)
	sg.destroy_buffer(ctx.vbuf)
	sg.pop_debug_group()
	sg.push_debug_group("sokol-imgui")
	delete(ctx.vertices)
	delete(ctx.indices)

	// destroy any cached views we created for user images
	for i in 0 ..< int(ctx.user_image_count) {
		if ctx.user_views[i].id != sg.INVALID_ID {
			sg.destroy_view(ctx.user_views[i])
		}
	}

	free(ctx)
}

imtextureid_with_sampler :: proc(img: sg.Image, smp: sg.Sampler) -> imgui.TextureID {
	return transmute(imgui.TextureID)((u64(smp.id) << 32) | u64(img.id))
}

imtextureid :: proc(img: sg.Image) -> imgui.TextureID {
	return imtextureid_with_sampler(img, ctx.def_smp)
}

image_from_imtextureid :: proc(imtex_id: imgui.TextureID) -> sg.Image {
	imtex_id := transmute(u64)imtex_id
	return sg.Image{u32(imtex_id)}
}

sampler_from_imtextureid :: proc(imtex_id: imgui.TextureID) -> sg.Sampler {
	imtex_id := transmute(u64)imtex_id
	return sg.Sampler{u32(imtex_id >> 32)}
}

set_clipboard :: proc "c" (ctx: ^imgui.Context, text: cstring) {
	sapp.set_clipboard_string(text)
}

get_clipboard :: proc "c" (ctx: ^imgui.Context) -> cstring {
	return sapp.get_clipboard_string()
}

Frame_Desc :: struct {
	width:      i32,
	height:     i32,
	delta_time: f64,
	dpi_scale:  f32,
}

new_frame :: proc(desc: Frame_Desc) {
	ctx.cur_dpi_scale = desc.dpi_scale

	io := imgui.GetIO()

	if !io.Fonts.TexReady {
		destroy_fonts_texture()
		create_fonts_texture(io)
	}

	io.DisplaySize.x = f32(desc.width) / desc.dpi_scale
	io.DisplaySize.y = f32(desc.height) / desc.dpi_scale
	io.DeltaTime = f32(desc.delta_time)

	if io.WantTextInput && !sapp.keyboard_shown() {
		sapp.show_keyboard(true)
	}
	if !io.WantTextInput && sapp.keyboard_shown() {
		sapp.show_keyboard(false)
	}

	imgui_cursor := imgui.GetMouseCursor()
	cursor := sapp.get_mouse_cursor()
	#partial switch imgui_cursor {
	case .Arrow:
		cursor = .ARROW
	case .TextInput:
		cursor = .IBEAM
	case .ResizeAll:
		cursor = .RESIZE_ALL
	case .ResizeNS:
		cursor = .RESIZE_NS
	case .ResizeEW:
		cursor = .RESIZE_EW
	case .ResizeNESW:
		cursor = .RESIZE_NESW
	case .ResizeNWSE:
		cursor = .RESIZE_NWSE
	case .Hand:
		cursor = .POINTING_HAND
	case .NotAllowed:
		cursor = .NOT_ALLOWED
	}
	sapp.set_mouse_cursor(cursor)

	imgui.NewFrame()
}

bind_image_sampler :: proc(bindings: ^sg.Bindings, imtex_id: imgui.TextureID) -> sg.Pipeline {
	img := image_from_imtextureid(imtex_id)
	smp := sampler_from_imtextureid(imtex_id)

	// get or create a view for this image (reuse to avoid exhausting the view pool)
	view := view_for_image(img)
	bindings.views[VIEW_tex] = view
	bindings.samplers[SMP_smp] = smp

	// check whether the image format requires the unfilterable pipeline
	img_pf := sg.query_image_pixelformat(img)
	if sg.query_pixelformat(img_pf).filter {
		return ctx.def_pip
	} else {
		return ctx.pip_unfilterable
	}
}

view_for_image :: proc(img: sg.Image) -> sg.View {
	// search cached images
	for i in 0 ..< int(ctx.user_image_count) {
		if ctx.user_images[i].id == img.id {
			return ctx.user_views[i]
		}
	}
	// not found: create new view and cache it
	if ctx.user_image_count >= len(ctx.user_images) {
		// cache full, just create a transient view (last resort)
		vd := sg.View_Desc {
			texture = sg.Texture_View_Desc{image = img},
		}
		return sg.make_view(vd)
	}
	idx := ctx.user_image_count
	vd := sg.View_Desc {
		texture = sg.Texture_View_Desc{image = img},
	}
	v := sg.make_view(vd)
	ctx.user_images[idx] = img
	ctx.user_views[idx] = v
	ctx.user_image_count += 1
	return v
}

render :: proc() {
	imgui.Render()

	draw_data := imgui.GetDrawData()
	io := imgui.GetIO()

	if draw_data == nil || draw_data.CmdLists.Size == 0 do return

	command_lists := mem.slice_ptr(draw_data.CmdLists.Data, int(draw_data.CmdLists.Size))

	/* copy vertices and indices into an intermediate buffer so that
       they can be updated with a single sg_update_buffer() call each
       (sg_append_buffer() has performance problems on some GL platforms),
       also keep track of valid number of command lists in case of a
       buffer overflow
    */
	all_vtx_size := 0
	all_idx_size := 0
	cmd_list_count := 0
	for cl in command_lists {
		vtx_size := int(cl.VtxBuffer.Size)
		idx_size := int(cl.IdxBuffer.Size)

		// check for buffer overflow
		if (all_vtx_size + vtx_size) > len(ctx.vertices) ||
		   (all_idx_size + idx_size) > len(ctx.indices) {
			break
		}

		// copy vertices and indices into common buffers
		if vtx_size > 0 do copy(ctx.vertices[all_vtx_size:all_vtx_size + vtx_size], mem.slice_ptr(cl.VtxBuffer.Data, vtx_size))
		if idx_size > 0 do copy(ctx.indices[all_idx_size:all_idx_size + idx_size], mem.slice_ptr(cl.IdxBuffer.Data, idx_size))

		all_vtx_size += vtx_size
		all_idx_size += idx_size

		cmd_list_count += 1
	}

	if cmd_list_count == 0 do return

	sg.push_debug_group("sokol-imgui")

	if all_vtx_size > 0 do sg.update_buffer(ctx.vbuf, {ptr = raw_data(ctx.vertices), size = uint(all_vtx_size * size_of(imgui.DrawVert))})
	if all_idx_size > 0 do sg.update_buffer(ctx.ibuf, {ptr = raw_data(ctx.indices), size = uint(all_idx_size * size_of(imgui.DrawIdx))})

	dpi_scale := ctx.cur_dpi_scale
	fb_width := int(io.DisplaySize.x * dpi_scale)
	fb_height := int(io.DisplaySize.y * dpi_scale)
	sg.apply_viewport(0, 0, fb_width, fb_height, true)
	sg.apply_scissor_rect(0, 0, fb_width, fb_height, true)

	sg.apply_pipeline(ctx.def_pip)

	vs_params := Vs_Params {
		disp_size = {io.DisplaySize.x, io.DisplaySize.y},
	}
	sg.apply_uniforms(UB_vs_params, range_def(&vs_params))

	bind := sg.Bindings {
		vertex_buffers = {0 = ctx.vbuf},
		index_buffer = ctx.ibuf,
	}

	tex_id := io.Fonts.TexID
	bind_image_sampler(&bind, tex_id)

	vb_offset: i32 = 0
	ib_offset: i32 = 0
	for cl in command_lists {
		bind.vertex_buffer_offsets[0] = vb_offset
		bind.index_buffer_offset = ib_offset
		sg.apply_bindings(bind)

		commands := mem.slice_ptr(cl.CmdBuffer.Data, int(cl.CmdBuffer.Size))
		vtx_offset: u32 = 0
		for &pcmd in commands {
			if pcmd.UserCallback != nil {
				// User callback, registered via ImDrawList::AddCallback()
				// (ImDrawCallback_ResetRenderState is a special callback value used by the user to request the renderer to reset render state.)
				if pcmd.UserCallback != ImDrawCallback_ResetRenderState {
					pcmd.UserCallback(cl, &pcmd)
					// need to re-apply all state after calling a user callback
					sg.reset_state_cache()
					sg.apply_viewport(0, 0, fb_width, fb_height, true)
					sg.apply_pipeline(ctx.def_pip)
					sg.apply_uniforms(UB_vs_params, range_def(&vs_params))
					sg.apply_bindings(bind)
				}
			} else {
				if tex_id != pcmd.TextureId || vtx_offset != pcmd.VtxOffset {
					tex_id = pcmd.TextureId
					vtx_offset = pcmd.VtxOffset

					pip := bind_image_sampler(&bind, tex_id)
					sg.apply_pipeline(pip)
					sg.apply_uniforms(UB_vs_params, range_def(&vs_params))
					bind.vertex_buffer_offsets[0] =
						vb_offset + i32(pcmd.VtxOffset * size_of(imgui.DrawVert))
					sg.apply_bindings(bind)
				}
				scissor_x := int(pcmd.ClipRect.x * dpi_scale)
				scissor_y := int(pcmd.ClipRect.y * dpi_scale)
				scissor_w := int((pcmd.ClipRect.z - pcmd.ClipRect.x) * dpi_scale)
				scissor_h := int((pcmd.ClipRect.w - pcmd.ClipRect.y) * dpi_scale)
				sg.apply_scissor_rect(scissor_x, scissor_y, scissor_w, scissor_h, true)
				sg.draw(pcmd.IdxOffset, pcmd.ElemCount, 1)
			}
		}

		vtx_size := cl.VtxBuffer.Size * size_of(imgui.DrawVert)
		idx_size := cl.IdxBuffer.Size * size_of(imgui.DrawIdx)
		vb_offset += vtx_size
		ib_offset += idx_size
	}

	sg.apply_viewport(0, 0, fb_width, fb_height, true)
	sg.apply_scissor_rect(0, 0, fb_width, fb_height, true)
	sg.pop_debug_group()
}

range_def :: proc(v: ^$T) -> sg.Range {
	return {ptr = v, size = size_of(T)}
}

ImDrawCallback_ResetRenderState := transmute(imgui.DrawCallback)(~uintptr(7))

handle_event :: proc(ev: ^sapp.Event) -> bool {
	dpi_scale := ctx.cur_dpi_scale
	io := imgui.GetIO()

	is_mouse_event := false
	is_keyboard_event := false

	branch: {
		#partial switch ev.type {
		case .FOCUSED:
			imgui.IO_AddFocusEvent(io, true)
		case .UNFOCUSED:
			imgui.IO_AddFocusEvent(io, false)
		case .MOUSE_DOWN:
			is_mouse_event = true
			add_mouse_pos_event(io, ev.mouse_x / dpi_scale, ev.mouse_y / dpi_scale)
			add_mouse_button_event(io, i32(ev.mouse_button), true)
			update_modifiers(io, ev.modifiers)
		case .MOUSE_UP:
			is_mouse_event = true
			add_mouse_pos_event(io, ev.mouse_x / dpi_scale, ev.mouse_y / dpi_scale)
			add_mouse_button_event(io, i32(ev.mouse_button), false)
			update_modifiers(io, ev.modifiers)
		case .MOUSE_MOVE:
			is_mouse_event = true
			add_mouse_pos_event(io, ev.mouse_x / dpi_scale, ev.mouse_y / dpi_scale)
		case .MOUSE_ENTER:
		case .MOUSE_LEAVE:
			is_mouse_event = true
		case .MOUSE_SCROLL:
			is_mouse_event = true
			add_mouse_wheel_event(io, ev.scroll_x, ev.scroll_y)
		case .TOUCHES_BEGAN:
			is_mouse_event = true
			add_touch_pos_event(
				io,
				ev.touches[0].pos_x / dpi_scale,
				ev.touches[0].pos_y / dpi_scale,
			)
			add_touch_button_event(io, 0, true)
		case .TOUCHES_MOVED:
			is_mouse_event = true
			add_touch_pos_event(
				io,
				ev.touches[0].pos_x / dpi_scale,
				ev.touches[0].pos_y / dpi_scale,
			)
		case .TOUCHES_ENDED:
			is_mouse_event = true
			add_touch_pos_event(
				io,
				ev.touches[0].pos_x / dpi_scale,
				ev.touches[0].pos_y / dpi_scale,
			)
			add_touch_button_event(io, 0, false)
		case .TOUCHES_CANCELLED:
			is_mouse_event = true
			add_touch_button_event(io, 0, false)
		case .KEY_DOWN:
			is_keyboard_event = true
			update_modifiers(io, ev.modifiers)
			// intercept Ctrl-V, this is handled via EVENTTYPE_CLIPBOARD_PASTED
			if is_ctrl(ev.modifiers) && (ev.key_code == .V) {
				break branch
			}
			// on web platform, don't forward Ctrl-X, Ctrl-V to the browser
			if is_ctrl(ev.modifiers) && (ev.key_code == .X) {
				sapp.consume_event()
			}
			if is_ctrl(ev.modifiers) && (ev.key_code == .C) {
				sapp.consume_event()
			}
			// it's ok to add ImGuiKey_None key events
			add_sapp_key_event(io, ev.key_code, true)
		case .KEY_UP:
			is_keyboard_event = true
			update_modifiers(io, ev.modifiers)
			// intercept Ctrl-V, this is handled via EVENTTYPE_CLIPBOARD_PASTED
			if is_ctrl(ev.modifiers) && (ev.key_code == .V) {
				break branch
			}
			// on web platform, don't forward Ctrl-X, Ctrl-V to the browser
			if is_ctrl(ev.modifiers) && (ev.key_code == .X) {
				sapp.consume_event()
			}
			if is_ctrl(ev.modifiers) && (ev.key_code == .C) {
				sapp.consume_event()
			}
			// it's ok to add ImGuiKey_None key events
			add_sapp_key_event(io, ev.key_code, false)
		case .CHAR:
			is_keyboard_event = true
			/* on some platforms, special keys may be reported as
			   characters, which may confuse some ImGui widgets,
			   drop those, also don't forward characters if some
			   modifiers have been pressed
			*/
			update_modifiers(io, ev.modifiers)
			if (ev.char_code >= 32) &&
			   (ev.char_code != 127) &&
			   (0 ==
					   (ev.modifiers &
							   (sapp.MODIFIER_ALT | sapp.MODIFIER_CTRL | sapp.MODIFIER_SUPER))) {
				add_input_character(io, ev.char_code)
			}
		case .CLIPBOARD_PASTED:
			// simulate a Ctrl-V key down/up
			add_imgui_key_event(io, copypaste_modifier(), true)
			add_imgui_key_event(io, .V, true)
			add_imgui_key_event(io, .V, false)
			add_imgui_key_event(io, copypaste_modifier(), false)
		}
	}

	// Only report that we consumed the event for the appropriate input type.
	if is_keyboard_event {
		return io.WantCaptureKeyboard
	}
	if is_mouse_event {
		return io.WantCaptureMouse
	}
	// focus/other events: don't claim
	return false
}

add_mouse_pos_event :: proc(io: ^imgui.IO, x, y: f32) {
	imgui.IO_AddMouseSourceEvent(io, .Mouse)
	imgui.IO_AddMousePosEvent(io, x, y)
}

add_mouse_button_event :: proc(io: ^imgui.IO, mouse_button: i32, down: bool) {
	imgui.IO_AddMouseSourceEvent(io, .Mouse)
	imgui.IO_AddMouseButtonEvent(io, mouse_button, down)
}

update_modifiers :: proc(io: ^imgui.IO, mods: u32) {
	imgui.IO_AddKeyEvent(io, .ImGuiMod_Ctrl, (mods & sapp.MODIFIER_CTRL) != 0)
	imgui.IO_AddKeyEvent(io, .ImGuiMod_Shift, (mods & sapp.MODIFIER_SHIFT) != 0)
	imgui.IO_AddKeyEvent(io, .ImGuiMod_Alt, (mods & sapp.MODIFIER_ALT) != 0)
	imgui.IO_AddKeyEvent(io, .ImGuiMod_Super, (mods & sapp.MODIFIER_SUPER) != 0)
}

add_mouse_wheel_event :: proc(io: ^imgui.IO, wheel_x, wheel_y: f32) {
	imgui.IO_AddMouseSourceEvent(io, .Mouse)
	imgui.IO_AddMouseWheelEvent(io, wheel_x, wheel_y)
}

add_touch_pos_event :: proc(io: ^imgui.IO, x, y: f32) {
	imgui.IO_AddMouseSourceEvent(io, .TouchScreen)
	imgui.IO_AddMousePosEvent(io, x, y)
}

add_touch_button_event :: proc(io: ^imgui.IO, mouse_button: i32, down: bool) {
	imgui.IO_AddMouseSourceEvent(io, .TouchScreen)
	imgui.IO_AddMouseButtonEvent(io, mouse_button, down)
}

add_input_character :: proc(io: ^imgui.IO, c: u32) {
	imgui.IO_AddInputCharacter(io, c)
}

add_sapp_key_event :: proc(io: ^imgui.IO, sapp_key: sapp.Keycode, down: bool) {
	imgui_key := map_keycode(sapp_key)
	imgui.IO_AddKeyEvent(io, imgui_key, down)
}

add_imgui_key_event :: proc(io: ^imgui.IO, imgui_key: imgui.Key, down: bool) {
	imgui.IO_AddKeyEvent(io, imgui_key, down)
}

map_keycode :: proc(key: sapp.Keycode) -> imgui.Key {
	#partial switch key {
	case .SPACE:
		return .Space
	case .APOSTROPHE:
		return .Apostrophe
	case .COMMA:
		return .Comma
	case .MINUS:
		return .Minus
	case .PERIOD:
		return .Apostrophe
	case .SLASH:
		return .Slash
	case ._0:
		return ._0
	case ._1:
		return ._1
	case ._2:
		return ._2
	case ._3:
		return ._3
	case ._4:
		return ._4
	case ._5:
		return ._5
	case ._6:
		return ._6
	case ._7:
		return ._7
	case ._8:
		return ._8
	case ._9:
		return ._9
	case .SEMICOLON:
		return .Semicolon
	case .EQUAL:
		return .Equal
	case .A:
		return .A
	case .B:
		return .B
	case .C:
		return .C
	case .D:
		return .D
	case .E:
		return .E
	case .F:
		return .F
	case .G:
		return .G
	case .H:
		return .H
	case .I:
		return .I
	case .J:
		return .J
	case .K:
		return .K
	case .L:
		return .L
	case .M:
		return .M
	case .N:
		return .N
	case .O:
		return .O
	case .P:
		return .P
	case .Q:
		return .Q
	case .R:
		return .R
	case .S:
		return .S
	case .T:
		return .T
	case .U:
		return .U
	case .V:
		return .V
	case .W:
		return .W
	case .X:
		return .X
	case .Y:
		return .Y
	case .Z:
		return .Z
	case .LEFT_BRACKET:
		return .LeftBracket
	case .BACKSLASH:
		return .Backslash
	case .RIGHT_BRACKET:
		return .RightBracket
	case .GRAVE_ACCENT:
		return .GraveAccent
	case .ESCAPE:
		return .Escape
	case .ENTER:
		return .Enter
	case .TAB:
		return .Tab
	case .BACKSPACE:
		return .Backspace
	case .INSERT:
		return .Insert
	case .DELETE:
		return .Delete
	case .RIGHT:
		return .RightArrow
	case .LEFT:
		return .LeftArrow
	case .DOWN:
		return .DownArrow
	case .UP:
		return .UpArrow
	case .PAGE_UP:
		return .PageUp
	case .PAGE_DOWN:
		return .PageDown
	case .HOME:
		return .Home
	case .END:
		return .End
	case .CAPS_LOCK:
		return .CapsLock
	case .SCROLL_LOCK:
		return .ScrollLock
	case .NUM_LOCK:
		return .NumLock
	case .PRINT_SCREEN:
		return .PrintScreen
	case .PAUSE:
		return .Pause
	case .F1:
		return .F1
	case .F2:
		return .F2
	case .F3:
		return .F3
	case .F4:
		return .F4
	case .F5:
		return .F5
	case .F6:
		return .F6
	case .F7:
		return .F7
	case .F8:
		return .F8
	case .F9:
		return .F9
	case .F10:
		return .F10
	case .F11:
		return .F11
	case .F12:
		return .F12
	case .KP_0:
		return .Keypad0
	case .KP_1:
		return .Keypad1
	case .KP_2:
		return .Keypad2
	case .KP_3:
		return .Keypad3
	case .KP_4:
		return .Keypad4
	case .KP_5:
		return .Keypad5
	case .KP_6:
		return .Keypad6
	case .KP_7:
		return .Keypad7
	case .KP_8:
		return .Keypad8
	case .KP_9:
		return .Keypad9
	case .KP_DECIMAL:
		return .KeypadDecimal
	case .KP_DIVIDE:
		return .KeypadDivide
	case .KP_MULTIPLY:
		return .KeypadMultiply
	case .KP_SUBTRACT:
		return .KeypadSubtract
	case .KP_ADD:
		return .KeypadAdd
	case .KP_ENTER:
		return .KeypadEnter
	case .KP_EQUAL:
		return .KeypadEqual
	case .LEFT_SHIFT:
		return .LeftShift
	case .LEFT_CONTROL:
		return .LeftCtrl
	case .LEFT_ALT:
		return .LeftAlt
	case .LEFT_SUPER:
		return .LeftSuper
	case .RIGHT_SHIFT:
		return .RightShift
	case .RIGHT_CONTROL:
		return .RightCtrl
	case .RIGHT_ALT:
		return .RightAlt
	case .RIGHT_SUPER:
		return .RightSuper
	case .MENU:
		return .Menu
	case:
		return .None
	}
}

is_osx :: proc() -> bool {
	// TODO: web osx
	when ODIN_OS == .Darwin {
		return true
	} else {
		return false
	}
}

is_ctrl :: proc(modifiers: u32) -> bool {
	if ctx.is_osx {
		return 0 != (modifiers & sapp.MODIFIER_SUPER)
	} else {
		return 0 != (modifiers & sapp.MODIFIER_CTRL)
	}
}
copypaste_modifier :: proc() -> imgui.Key {
	return ctx.is_osx ? .ImGuiMod_Super : .ImGuiMod_Ctrl
}
