## See/Saw XR: wires the small modules together.
##   XRRig          player + aiming (Quest controllers, or mouse/keyboard on desktop)
##   ProbeClient    capture the aimed view, send it to the sidecar, report timings
##   OverlayPainter paint the returned groups onto the 3D scene
##   HudPanel       in-world status / latency text
## Desktop test without a window:  godot --path godot -- --autoprobe=C:/path/out.png
extends Node3D

const SCENE_GLB := "res://assets/scene.glb"

var world: Node3D
var painter: OverlayPainter
var rig: XRRig
var client: ProbeClient
var hud: HudPanel

var probe_count := 0
var last: Dictionary = {}
var capture_ms := 0.0
var roundtrip_ms := 0.0
var status := "Aim and probe."
var autoprobe_path := ""


func _ready() -> void:
	_setup_environment()

	world = Node3D.new()
	world.name = "World"
	add_child(world)
	if ResourceLoader.exists(SCENE_GLB):
		world.add_child(load(SCENE_GLB).instantiate())
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-55, 35, 0)
		world.add_child(sun)
	else:
		RoomBuilder.build(world)

	painter = OverlayPainter.new()
	painter.attach_to(world)     # only the scene gets the overlay, not the rig or the HUD

	rig = XRRig.new()
	add_child(rig)
	client = ProbeClient.new()
	add_child(client)
	client.setup(painter)
	hud = HudPanel.new()
	rig.mount_hud(hud)
	hud.setup(rig.is_xr)

	rig.probe_requested.connect(_on_probe_requested)
	rig.overlay_toggled.connect(painter.toggle)
	rig.hud_toggled.connect(func() -> void: hud.visible = not hud.visible)
	client.finished.connect(_on_finished)
	client.failed.connect(_on_failed)

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoprobe="):
			autoprobe_path = a.trim_prefix("--autoprobe=")
	if autoprobe_path != "":
		await get_tree().create_timer(1.0).timeout
		_on_probe_requested()


func _setup_environment() -> void:
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


func _on_probe_requested() -> void:
	if client.busy:
		return
	status = "Probing..."
	_refresh_hud()
	rig.pulse()
	client.probe(rig.aim_transform(), rig.capture_fov())


func _on_finished(d: Dictionary, capture_vp: Projection, timing: Dictionary) -> void:
	painter.apply(d, capture_vp)
	probe_count += 1
	last = d
	capture_ms = timing["capture_ms"]
	roundtrip_ms = timing["roundtrip_ms"]
	status = "Done. Walk around, probe again."
	_refresh_hud()
	print("probe #%d  capture %.0f ms  round trip %.0f ms  %s" % [probe_count, capture_ms, roundtrip_ms, d.get("timing_ms", {})])
	if autoprobe_path != "":
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(autoprobe_path)
		print("screenshot saved: %s" % autoprobe_path)
		get_tree().quit()


func _on_failed(message: String) -> void:
	status = message
	_refresh_hud()
	push_warning(message)
	if autoprobe_path != "":
		get_tree().quit(1)


func _refresh_hud() -> void:
	hud.show_state(last, probe_count, capture_ms, roundtrip_ms, status)
