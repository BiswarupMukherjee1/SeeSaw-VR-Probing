## Paints the sidecar's cluster labels onto the 3D scene.
## One shared ShaderMaterial is chained (next_pass) onto every mesh material under a root node.
class_name OverlayPainter
extends RefCounted

const PALETTE: Array[Color] = [
	Color("f6d55c"), Color("9ad27a"), Color("f29bb8"), Color("6fc3d6"),
	Color("b79ad9"), Color("e8964a"), Color("8a9a5b"), Color("a9d8f0"),
]

var material: ShaderMaterial
var has_result := false
var user_enabled := true


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/probe_overlay.gdshader")
	material.render_priority = 1
	material.set_shader_parameter("palette", PackedColorArray(PALETTE))
	material.set_shader_parameter("attn", PackedFloat32Array([1, 1, 1, 1, 1, 1, 1, 1]))
	material.set_shader_parameter("enabled", false)


## Chain the overlay onto every mesh below `root` (call once, after the scene is built).
func attach_to(root: Node) -> void:
	for c in root.get_children():
		if c is MeshInstance3D:
			_overlay_mesh(c)
		attach_to(c)


## Hide the paint while the capture camera renders, so the model sees the clean scene.
func set_capturing(capturing: bool) -> void:
	material.set_shader_parameter("enabled", (not capturing) and user_enabled and has_result)


func toggle() -> void:
	user_enabled = not user_enabled
	material.set_shader_parameter("enabled", user_enabled and has_result)


## `d` is the sidecar JSON, `capture_vp` the projection*view matrix of the capture camera.
func apply(d: Dictionary, capture_vp: Projection) -> void:
	var w := int(d["w"])
	var h := int(d["h"])
	var lab := Image.create_from_data(w, h, false, Image.FORMAT_R8, Marshalls.base64_to_raw(d["labels_b64"]))
	material.set_shader_parameter("labels", ImageTexture.create_from_image(lab))
	material.set_shader_parameter("capture_vp", capture_vp)
	material.set_shader_parameter("attn", PackedFloat32Array(d["attn"]))
	material.set_shader_parameter("highlight", int(round(lab.get_pixel(w / 2, h / 2).r * 255.0)))
	has_result = true
	material.set_shader_parameter("enabled", user_enabled)


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
	var cur := m
	while cur.next_pass != null:
		if cur.next_pass == material:
			return
		cur = cur.next_pass
	cur.next_pass = material
