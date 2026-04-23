package utils

import "../sgltf"
import "../simgui"
import sg "../sokol/gfx"

Global_State :: struct {
	failed:             bool,
	pass_action_ok:     sg.Pass_Action,
	pass_action_failed: sg.Pass_Action,
	smp:                sg.Sampler,
	scene:              sgltf.Scene,
	rx, ry:             f32,
	root_transform:     sgltf.Matrix,
	pip_cache:          sgltf.Pipeline_Cache,
	placeholders:       struct {
		white:  sg.View,
		normal: sg.View,
		black:  sg.View,
		smp:    sg.Sampler,
	},
	point_light:        sgltf.Light_Params,
	imgui_context:      ^simgui.Context,
}
