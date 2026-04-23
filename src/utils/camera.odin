package utils

import sapp "../sokol/app"
import "core:math"
import "core:math/linalg"

Vec3 :: linalg.Vector3f32
Matrix :: linalg.Matrix4f32

DEFAULT_MIN_DIST :: 2.0
DEFAULT_MAX_DIST :: 30.0
DEFAULT_MIN_LAT :: -85.0
DEFAULT_MAX_LAT :: 85.0
DEFAULT_DIST :: 5.0
DEFAULT_FOV :: 60.0
DEFAULT_NEARZ :: 0.01
DEFAULT_FARZ :: 100.0

Camera_Desc :: struct {
	min_dist:  f32,
	max_dist:  f32,
	min_lat:   f32,
	max_lat:   f32,
	distance:  f32,
	latitude:  f32,
	longitude: f32,
	fov:       f32,
	nearz:     f32,
	farz:      f32,
	center:    Vec3,
}

Camera :: struct {
	min_dist:  f32,
	max_dist:  f32,
	min_lat:   f32,
	max_lat:   f32,
	distance:  f32,
	latitude:  f32,
	longitude: f32,
	fov:       f32,
	nearz:     f32,
	farz:      f32,
	center:    Vec3,
	eye_pos:   Vec3,
	view:      Matrix,
	proj:      Matrix,
	view_proj: Matrix,
}

_cam_def :: proc "c" (val: f32, def: f32) -> f32 {
	return val if val != 0 else def
}

cam_init :: proc "c" (cam: ^Camera, desc: Camera_Desc) {
	cam.min_dist = _cam_def(desc.min_dist, DEFAULT_MIN_DIST)
	cam.max_dist = _cam_def(desc.max_dist, DEFAULT_MAX_DIST)
	cam.min_lat = _cam_def(desc.min_lat, DEFAULT_MIN_LAT)
	cam.max_lat = _cam_def(desc.max_lat, DEFAULT_MAX_LAT)
	cam.distance = _cam_def(desc.distance, DEFAULT_DIST)
	cam.center = desc.center
	cam.latitude = desc.latitude
	cam.longitude = desc.longitude
	cam.fov = _cam_def(desc.fov, DEFAULT_FOV)
	cam.nearz = _cam_def(desc.nearz, DEFAULT_NEARZ)
	cam.farz = _cam_def(desc.farz, DEFAULT_FARZ)
}

cam_orbit :: proc "c" (cam: ^Camera, dx: f32, dy: f32) {
	cam.longitude -= dx
	if cam.longitude < 0 {
		cam.longitude += 360.0
	}
	if cam.longitude > 360.0 {
		cam.longitude -= 360.0
	}
	cam.latitude = math.clamp(cam.min_lat, cam.latitude + dy, cam.max_lat)
}

cam_zoom :: proc "c" (cam: ^Camera, d: f32) {
	cam.distance = math.clamp(cam.min_dist, cam.distance + d, cam.max_dist)
}

_cam_euclidean :: proc "c" (latitude: f32, longitude: f32) -> Vec3 {
	lat := latitude * math.PI / 180.0
	lng := longitude * math.PI / 180.0
	return Vec3 {
		math.cos_f32(lat) * math.sin_f32(lng),
		math.sin_f32(lat),
		math.cos_f32(lat) * math.cos_f32(lng),
	}
}

cam_update :: proc "c" (cam: ^Camera, fb_width: i32, fb_height: i32) {
	lat := cam.latitude * math.PI / 180.0
	lon := cam.longitude * math.PI / 180.0
	cam.eye_pos = cam.center + _cam_euclidean(cam.latitude, cam.longitude) * cam.distance
	cam.view = linalg.matrix4_look_at_f32(cam.eye_pos, cam.center, Vec3{0, 1, 0})
	cam.proj = linalg.matrix4_perspective_f32(
		cam.fov * math.PI / 180.0,
		cast(f32)fb_width / cast(f32)fb_height,
		cam.nearz,
		cam.farz,
	)
	cam.view_proj = cam.proj * cam.view
}

cam_handle_event :: proc "c" (cam: ^Camera, ev: ^sapp.Event) {
	#partial switch ev.type {
	case .MOUSE_DOWN:
		if ev.mouse_button == .LEFT {
			sapp.lock_mouse(true)
		}
	case .MOUSE_UP:
		if ev.mouse_button == .LEFT {
			sapp.lock_mouse(false)
		}
	case .MOUSE_SCROLL:
		cam_zoom(cam, cast(f32)ev.scroll_y * 0.5)
	case .MOUSE_MOVE:
		if sapp.mouse_locked() {
			cam_orbit(cam, cast(f32)ev.mouse_dx * 0.25, cast(f32)ev.mouse_dy * 0.25)
		}
	}
}
