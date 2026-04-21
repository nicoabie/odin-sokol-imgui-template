package main

import "base:runtime"
import "core:log"
import "core:mem"
import sapp "sokol/app"
import sg "sokol/gfx"
import sglue "sokol/glue"
import slog "sokol/log"

import imgui "imgui"
import simgui "simgui"

Game_State :: struct {
	imgui_context: ^simgui.Context,
	should_quit:   bool,
	showImguiDemo: bool,
}

g: ^Game_State

pass_action: sg.Pass_Action
tracking_global: mem.Tracking_Allocator
tracking_inited: bool = false
tracking_alloc: mem.Allocator
orig_allocator: mem.Allocator

TrackingAllocator :: proc() -> mem.Allocator {
	allocator: mem.Allocator = runtime.default_context().allocator
	when ODIN_DEBUG {
		if !tracking_inited {
			mem.tracking_allocator_init(&tracking_global, allocator)
			tracking_alloc = mem.tracking_allocator(&tracking_global)
			orig_allocator = allocator
			tracking_inited = true
		}
		return tracking_alloc
	}

	return allocator
}

core_init :: proc "c" () {
	context = runtime.default_context()
	context.allocator = TrackingAllocator()
	context.logger = log.create_console_logger()

	sg.setup({environment = sglue.environment(), logger = {func = slog.func}})
	g = new(Game_State)
	g.showImguiDemo = true
	g.imgui_context = simgui.setup()
	pass_action.colors[0] = {
		load_action = .CLEAR,
		clear_value = {0.16, 0.16, 0.16, 1.0},
	}
}

core_frame :: proc "c" () {
	context = runtime.default_context()
	context.allocator = TrackingAllocator()
	context.logger = log.create_console_logger()

	simgui.new_frame(
		{
			width = sapp.width(),
			height = sapp.height(),
			delta_time = sapp.frame_duration(),
			dpi_scale = sapp.dpi_scale(),
		},
	)

	sg.begin_pass({action = pass_action, swapchain = sglue.swapchain()})

	if g.should_quit {
		sapp.quit()
	}


	if g.showImguiDemo {
		imgui.ShowDemoWindow(nil)

		imgui.SetNextWindowPos(imgui.Vec2{10, 10})
		old_font_size := imgui.GetDefaultFont().Scale
		if imgui.Begin(
			"Hello, Sokol + ImGui!",
			nil,
			{.AlwaysAutoResize, .NoTitleBar, .NoBackground, .NoMove},
		) {
			imgui.PushFont(imgui.GetDefaultFont())
			imgui.Text("FPS %.f", (1.0 / sapp.frame_duration()))
		}
		imgui.PopFont()
		imgui.End()
	}

	simgui.render()
	sg.end_pass()
	sg.commit()
}


core_event :: proc "c" (event: ^sapp.Event) {
	context = runtime.default_context()
	context.allocator = TrackingAllocator()

	if simgui.handle_event(event) {
		return
	}

	if event.key_code == .ESCAPE {
		g.should_quit = true
	}

	if event.key_code == .F1 && event.type == .KEY_DOWN {
		g.showImguiDemo = !g.showImguiDemo
	}
}


core_cleanup :: proc "c" () {
	context = runtime.default_context()
	context.allocator = TrackingAllocator()
	context.logger = log.create_console_logger()
	simgui.shutdown()
	sg.shutdown()
	free(g)
}

main :: proc() {
	sapp.run(
		{
			init_cb = core_init,
			frame_cb = core_frame,
			cleanup_cb = core_cleanup,
			event_cb = core_event,
			width = 1920,
			height = 1080,
			window_title = "Imgui with Sokol and Odin",
			icon = {sokol_default = true},
			logger = {func = slog.func},
		},
	)
}
