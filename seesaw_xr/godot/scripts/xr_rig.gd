## The player: an OpenXR rig on the Quest, or a mouse + keyboard camera on the desktop.
## It only reports intent (probe / toggle overlay / toggle HUD) and answers "where am I aiming".
##
## Quest 3:  right trigger = probe, A = overlay on/off, B = HUD on/off,
##           left stick = walk, right stick = turn. The laser is the aim direction.
## Desktop:  SPACE / E / left click = probe, O = overlay, H = HUD, WASD (+Shift) = walk,
##           right click = mouse look, arrow keys = turn.
class_name XRRig
extends Node3D

signal probe_requested
signal overlay_toggled
signal hud_toggled

const AIM_DISTANCE := 3.0     # metres: the capture frustum is centred this far along the controller ray
const XR_CAPTURE_FOV := 60.0
const START_POS := Vector3(2.2, 0.0, 2.4)

var is_xr := false
var camera: Camera3D
var left_hand: XRController3D
var right_hand: XRController3D

var _origin: XROrigin3D
var _body: Node3D             # desktop only
var _yaw := deg_to_rad(35.0)
var _pitch := deg_to_rad(-16.0)


func _ready() -> void:
	var xr: XRInterface = XRServer.find_interface("OpenXR")
	is_xr = xr != null and xr.is_initialized()
	if is_xr:
		_build_xr()
	else:
		_build_desktop()


# ------------------------------------------------------------------ public
## The view the capture camera should render (head position, looking where the user aims).
func aim_transform() -> Transform3D:
	if not is_xr:
		return camera.global_transform
	var target := right_hand.global_position + (-right_hand.global_basis.z) * AIM_DISTANCE
	return Transform3D(Basis.IDENTITY, camera.global_position).looking_at(target, Vector3.UP)


func capture_fov() -> float:
	return XR_CAPTURE_FOV if is_xr else camera.fov


func mount_hud(hud: Node3D) -> void:
	if is_xr:
		left_hand.add_child(hud)
		hud.position = Vector3(0.0, 0.16, -0.05)
		hud.rotation_degrees = Vector3(-55.0, 0.0, 0.0)
	else:
		camera.add_child(hud)
		hud.position = Vector3(-0.85, 0.5, -1.2)


func pulse() -> void:
	if is_xr:
		right_hand.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.12, 0.0)


# ------------------------------------------------------------------ build
func _build_xr() -> void:
	get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_origin = XROrigin3D.new()
	_origin.position = START_POS
	_origin.rotation.y = _yaw
	add_child(_origin)
	camera = XRCamera3D.new()
	_origin.add_child(camera)
	left_hand = _make_hand(&"left_hand", &"default")
	right_hand = _make_hand(&"right_hand", &"aim")
	_add_laser(right_hand)


func _make_hand(tracker: StringName, pose: StringName) -> XRController3D:
	var h := XRController3D.new()
	h.tracker = tracker
	h.pose = pose
	_origin.add_child(h)
	h.button_pressed.connect(_on_button)
	return h


func _add_laser(hand: XRController3D) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.4, 0.9, 1.0, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var box := BoxMesh.new()
	box.size = Vector3(0.004, 0.004, AIM_DISTANCE)
	var laser := MeshInstance3D.new()
	laser.mesh = box
	laser.material_override = m
	laser.position = Vector3(0.0, 0.0, -AIM_DISTANCE / 2.0)
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand.add_child(laser)


func _build_desktop() -> void:
	_body = Node3D.new()
	_body.position = START_POS + Vector3(0.0, 1.6, 0.0)
	add_child(_body)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.current = true
	_body.add_child(camera)
	_apply_look()


# ------------------------------------------------------------------ input
func _on_button(button: String) -> void:
	match button:
		"trigger_click":
			probe_requested.emit()
		"ax_button":
			overlay_toggled.emit()
		"by_button":
			hud_toggled.emit()


func _unhandled_input(e: InputEvent) -> void:
	if is_xr:
		return
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_RIGHT:
			var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		elif e.button_index == MOUSE_BUTTON_LEFT:
			probe_requested.emit()
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= e.relative.x * 0.003
		_pitch = clamp(_pitch - e.relative.y * 0.003, -1.4, 1.4)
		_apply_look()
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE, KEY_E:
				probe_requested.emit()
			KEY_O:
				overlay_toggled.emit()
			KEY_H:
				hud_toggled.emit()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(dt: float) -> void:
	if is_xr:
		_process_xr(dt)
	else:
		_process_desktop(dt)


func _process_xr(dt: float) -> void:
	var move := left_hand.get_vector2("primary")
	if move.length() > 0.2:
		var yaw_basis := Basis(Vector3.UP, camera.global_rotation.y)
		_origin.global_position += yaw_basis * Vector3(move.x, 0.0, -move.y) * 1.5 * dt
	var turn := right_hand.get_vector2("primary").x
	if absf(turn) > 0.4:
		var ang := -turn * 1.4 * dt
		var pivot := camera.global_position
		_origin.global_position = pivot + (_origin.global_position - pivot).rotated(Vector3.UP, ang)
		_origin.rotate_y(ang)


func _process_desktop(dt: float) -> void:
	var look := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT): look.x += 1
	if Input.is_key_pressed(KEY_RIGHT): look.x -= 1
	if Input.is_key_pressed(KEY_UP): look.y += 1
	if Input.is_key_pressed(KEY_DOWN): look.y -= 1
	if look != Vector2.ZERO:
		_yaw += look.x * 1.5 * dt
		_pitch = clamp(_pitch + look.y * 1.2 * dt, -1.4, 1.4)
		_apply_look()
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir.z -= 1
	if Input.is_key_pressed(KEY_S): dir.z += 1
	if Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_D): dir.x += 1
	if dir != Vector3.ZERO:
		var speed := 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.5
		_body.position += (_body.global_transform.basis * dir.normalized()) * speed * dt


func _apply_look() -> void:
	_body.rotation = Vector3(0.0, _yaw, 0.0)
	camera.rotation = Vector3(_pitch, 0.0, 0.0)
