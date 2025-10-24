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
	g.imgui_context = simgui.setup()
	pass_action.colors[0] = {
		load_action = .CLEAR,
		clear_value = {1.0, 0.0, 0.0, 1.0},
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

	imgui.ShowDemoWindow(nil)

	simgui.render()
	sg.end_pass()
	sg.commit()
}

core_cleanup :: proc "c" () {
	context = runtime.default_context()
	context.allocator = TrackingAllocator()
	context.logger = log.create_console_logger()
	simgui.shutdown()
	sg.shutdown()
	free(g)
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
}

main :: proc() {
	sapp.run(
		{
			init_cb = core_init,
			frame_cb = core_frame,
			cleanup_cb = core_cleanup,
			event_cb = core_event,
			width = 1280,
			height = 720,
			window_title = "Imgui with Sokol and Odin",
			icon = {sokol_default = true},
			logger = {func = slog.func},
		},
	)
}
