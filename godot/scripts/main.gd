## See/Saw proof of concept, desktop version (Godot 4.3+).
## Aim with the centre reticle, press SPACE (or left click) to probe:
## the view inside the capture square is sent to the Python sidecar (DINOv2 + k-means),
## and the returned groups are painted back onto the 3D surfaces.
extends Node3D

const SIDECAR_URL := "http://127.0.0.1:8765/probe"
const CAPTURE_SIZE := 448
const PALETTE: Array[Color] = [
	Color("f6d55c"), Color("9ad27a"), Color("f29bb8"), Color("6fc3d6"),
	Color("b79ad9"), Color("e8964a"), Color("8a9a5b"), Color("a9d8f0"),
]

var overlay_mat: ShaderMaterial
var player: Node3D
var cam: Camera3D
var cap_vp: SubViewport
var cap_cam: Camera3D
var http: HTTPRequest

var info: Label
var frame_rect: ReferenceRect
var legend: HBoxContainer
var hud_root: Control

var yaw := deg_to_rad(35.0)
var pitch := deg_to_rad(-16.0)
var busy := false
var has_result := false
var overlay_on := true
var pending_vp: Projection
var t_send := 0
var capture_ms := 0.0
var roundtrip_ms := 0.0
var last: Dictionary = {}
var status := "Press SPACE to probe the view inside the white square."
var probe_count := 0
var autoprobe_path := ""


func _ready() -> void:
	_setup_env()
	var glb := "res://assets/scene.glb"
	if ResourceLoader.exists(glb):
		add_child(load(glb).instantiate())
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-55, 35, 0)
		add_child(sun)
	else:
		RoomBuilder.build(self)

	overlay_mat = ShaderMaterial.new()
	overlay_mat.shader = load("res://shaders/probe_overlay.gdshader")
	overlay_mat.render_priority = 1
	overlay_mat.set_shader_parameter("palette", PackedColorArray(PALETTE))
	overlay_mat.set_shader_parameter("attn", PackedFloat32Array([1, 1, 1, 1, 1, 1, 1, 1]))
	_attach_overlay(self)

	_setup_player()
	_setup_capture()
	_setup_hud()

	http = HTTPRequest.new()
	http.timeout = 60.0
	add_child(http)
	http.request_completed.connect(_on_probe_done)

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoprobe="):
			autoprobe_path = a.trim_prefix("--autoprobe=")
	if autoprobe_path != "":
		await get_tree().create_timer(1.0).timeout
		probe()


# ------------------------------------------------------------------ scene setup
func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)


func _attach_overlay(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			_overlay_mesh(c)
		_attach_overlay(c)


func _overlay_mesh(mi: MeshInstance3D) -> void:
	if mi.material_override != null:
		_chain(mi.material_override)
		return
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var m: Material = mi.get_active_material(i)
		m = StandardMaterial3D.new() if m == null else m.duplicate()
		_chain(m)
		mi.set_surface_override_material(i, m)


func _chain(m: Material) -> void:
	# put the overlay at the end of the material's next_pass chain, once
	var cur := m
	while cur.next_pass != null:
		if cur.next_pass == overlay_mat:
			return
		cur = cur.next_pass
	cur.next_pass = overlay_mat


func _setup_player() -> void:
	player = Node3D.new()
	player.position = Vector3(2.2, 1.6, 2.4)
	add_child(player)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.current = true
	player.add_child(cam)
	_apply_look()


func _apply_look() -> void:
	player.rotation = Vector3(0.0, yaw, 0.0)
	cam.rotation = Vector3(pitch, 0.0, 0.0)


func _setup_capture() -> void:
	# square capture camera = the probe "frustum"; it shares the main 3D world
	cap_vp = SubViewport.new()
	cap_vp.size = Vector2i(CAPTURE_SIZE, CAPTURE_SIZE)
	cap_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(cap_vp)
	cap_cam = Camera3D.new()
	cap_vp.add_child(cap_cam)
	cap_cam.current = true


# ------------------------------------------------------------------ HUD
func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud_root)

	frame_rect = ReferenceRect.new()
	frame_rect.editor_only = false
	frame_rect.border_color = Color(1, 1, 1, 0.55)
	frame_rect.border_width = 2.0
	frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(frame_rect)

	for s in [Vector2(22, 2), Vector2(2, 22)]:
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.9)
		r.size = s
		r.set_anchors_preset(Control.PRESET_CENTER)
		r.position = -s / 2.0
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_root.add_child(r)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.14, 0.82)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	hud_root.add_child(panel)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 15)
	panel.add_child(info)

	legend = HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	legend.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	legend.position = Vector2(-330, -54)
	hud_root.add_child(legend)
	for i in 8:
		var box := HBoxContainer.new()
		var c := ColorRect.new()
		c.color = PALETTE[i]
		c.custom_minimum_size = Vector2(22, 22)
		var l := Label.new()
		l.name = "L"
		l.text = "  -"
		l.add_theme_font_size_override("font_size", 13)
		box.add_child(c)
		box.add_child(l)
		legend.add_child(box)
	legend.visible = false
	_update_hud()


func _update_hud() -> void:
	var t := "See/Saw PoC  ·  Godot 4 desktop prototype\n"
	if last.is_empty():
		t += "Backend: (no probe yet)\n"
	else:
		var tm: Dictionary = last.get("timing_ms", {})
		t += "Backend: %s\n" % last.get("backend", "?")
		t += "Probe #%d   K = %d   colour matching: %s\n" % [probe_count, int(last.get("k", 8)), "on" if last.get("matched_colors", false) else "off"]
		t += "Latency  total %.0f ms  =  capture %.0f + round trip %.0f\n" % [capture_ms + roundtrip_ms, capture_ms, roundtrip_ms]
		t += "  sidecar: encoder %.0f · k-means %.0f · upsample %.0f ms\n" % [tm.get("encoder", 0.0), tm.get("kmeans", 0.0), tm.get("upsample", 0.0)]
		if not last.get("has_attention", true):
			t += "  (no attention in this backend: brightness is flat)\n"
	t += status + "\n"
	t += "SPACE/click probe · WASD move · right-click mouse look · O overlay · H hide HUD · F12 screenshot"
	info.text = t

	if not last.is_empty():
		legend.visible = true
		var att: Array = last.get("attn", [])
		var share: Array = last.get("share", [])
		for i in legend.get_child_count():
			var l: Label = legend.get_child(i).get_node("L")
			l.text = " %d%%" % int(round(float(share[i]) * 100.0)) if i < share.size() else " -"


# ------------------------------------------------------------------ input
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_RIGHT:
			var cap := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if cap else Input.MOUSE_MODE_CAPTURED
		elif e.button_index == MOUSE_BUTTON_LEFT:
			probe()
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.003
		pitch = clamp(pitch - e.relative.y * 0.003, -1.4, 1.4)
		_apply_look()
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE, KEY_E:
				probe()
			KEY_O:
				overlay_on = not overlay_on
				overlay_mat.set_shader_parameter("enabled", overlay_on and has_result)
			KEY_H:
				hud_root.visible = not hud_root.visible
			KEY_F12:
				_save_screenshot("")
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(dt: float) -> void:
	var look := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT): look.x += 1
	if Input.is_key_pressed(KEY_RIGHT): look.x -= 1
	if Input.is_key_pressed(KEY_UP): look.y += 1
	if Input.is_key_pressed(KEY_DOWN): look.y -= 1
	if look != Vector2.ZERO:
		yaw += look.x * 1.5 * dt
		pitch = clamp(pitch + look.y * 1.2 * dt, -1.4, 1.4)
		_apply_look()

	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir.z -= 1
	if Input.is_key_pressed(KEY_S): dir.z += 1
	if Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_D): dir.x += 1
	if dir != Vector3.ZERO:
		var speed := 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.5
		player.position += (player.global_transform.basis * dir.normalized()) * speed * dt

	var vs := get_viewport().get_visible_rect().size
	frame_rect.position = Vector2((vs.x - vs.y) / 2.0, 0.0)
	frame_rect.size = Vector2(vs.y, vs.y)


# ------------------------------------------------------------------ probe
func probe() -> void:
	if busy:
		return
	busy = true
	status = "Probing..."
	_update_hud()
	var t0 := Time.get_ticks_usec()
	cap_cam.global_transform = cam.global_transform
	cap_cam.fov = cam.fov
	overlay_mat.set_shader_parameter("enabled", false)   # capture the clean scene
	cap_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := cap_vp.get_texture().get_image()
	pending_vp = cap_cam.get_camera_projection() * Projection(cap_cam.global_transform.affine_inverse())
	overlay_mat.set_shader_parameter("enabled", overlay_on and has_result)
	capture_ms = (Time.get_ticks_usec() - t0) / 1000.0

	t_send = Time.get_ticks_usec()
	var err := http.request_raw(SIDECAR_URL, PackedStringArray(["Content-Type: image/png"]),
			HTTPClient.METHOD_POST, img.save_png_to_buffer())
	if err != OK:
		busy = false
		status = "Could not send the request (error %d)." % err
		_update_hud()


func _on_probe_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	roundtrip_ms = (Time.get_ticks_usec() - t_send) / 1000.0
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status = "Sidecar not reachable. Start it with:  python sidecar/server.py"
		_update_hud()
		if autoprobe_path != "":
			get_tree().quit(1)
		return
	var d: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	var w := int(d["w"])
	var h := int(d["h"])
	var lab := Image.create_from_data(w, h, false, Image.FORMAT_R8, Marshalls.base64_to_raw(d["labels_b64"]))
	overlay_mat.set_shader_parameter("labels", ImageTexture.create_from_image(lab))
	overlay_mat.set_shader_parameter("capture_vp", pending_vp)
	overlay_mat.set_shader_parameter("attn", PackedFloat32Array(d["attn"]))
	overlay_mat.set_shader_parameter("highlight", int(round(lab.get_pixel(w / 2, h / 2).r * 255.0)))
	has_result = true
	overlay_mat.set_shader_parameter("enabled", overlay_on)
	probe_count += 1
	last = d
	status = "Done. Walk around: the paint stays where the probe saw it. Probe again to re-tokenize."
	_update_hud()
	if autoprobe_path != "":
		await get_tree().create_timer(0.5).timeout
		_save_screenshot(autoprobe_path)
		get_tree().quit()


func _save_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	if path == "":
		path = "user://seesaw_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	get_viewport().get_texture().get_image().save_png(path)
	status = "Screenshot saved: %s" % ProjectSettings.globalize_path(path)
	print(status)
	_update_hud()
