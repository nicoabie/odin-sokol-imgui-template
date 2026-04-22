package camera

import "core:math"
import "core:math/linalg"
import sapp "../sokol/app"

Vec3 :: linalg.Vector3f32
Matrix :: linalg.Matrix4f32

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
