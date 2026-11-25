## Builds a small living-room / bar scene out of primitives, so the project needs no assets.
## To use a real scene instead, put a .glb at res://assets/scene.glb (see README).
class_name RoomBuilder
extends RefCounted


static func mat(color: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


static func box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, name := "Box") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = m
	mi.name = name
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, name := "Cylinder") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	mi.mesh = c
	mi.position = pos
	mi.material_override = m
	mi.name = name
	parent.add_child(mi)
	return mi


static func sphere(parent: Node3D, r: float, pos: Vector3, m: Material, name := "Sphere") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	mi.mesh = s
	mi.position = pos
	mi.material_override = m
	mi.name = name
	parent.add_child(mi)
	return mi


static func build(root: Node3D) -> void:
	var room := Node3D.new()
	room.name = "Room"
	root.add_child(room)

	var wall := mat(Color(0.70, 0.68, 0.64))
	var wall_dark := mat(Color(0.36, 0.40, 0.46))
	var floor_m := mat(Color(0.36, 0.30, 0.26), 0.8)
	var wood := mat(Color(0.52, 0.34, 0.20), 0.5)
	var wood_dark := mat(Color(0.28, 0.17, 0.10), 0.5)
	var fabric := mat(Color(0.30, 0.36, 0.48), 0.95)
	var cushion := mat(Color(0.86, 0.84, 0.80), 0.95)
	var leaf := mat(Color(0.25, 0.55, 0.22), 0.7)
	var pot := mat(Color(0.85, 0.85, 0.82), 0.4)
	var glass_g := mat(Color(0.15, 0.45, 0.20), 0.15, 0.1)
	var glass_p := mat(Color(0.65, 0.35, 0.55), 0.15, 0.1)
	var brass := mat(Color(0.85, 0.65, 0.30), 0.3, 0.8)
	var lamp_m := mat(Color(0.12, 0.12, 0.14), 0.5)
	var rug := mat(Color(0.62, 0.20, 0.18), 1.0)
	var art := mat(Color(0.95, 0.70, 0.25), 0.6)

	# shell: 8 x 3 x 8 m
	box(room, Vector3(8, 0.1, 8), Vector3(0, -0.05, 0), floor_m, "Floor")
	box(room, Vector3(8, 3, 0.1), Vector3(0, 1.5, -4), wall, "WallBack")
	box(room, Vector3(0.1, 3, 8), Vector3(-4, 1.5, 0), wall_dark, "WallLeft")
	box(room, Vector3(0.1, 3, 8), Vector3(4, 1.5, 0), wall, "WallRight")
	box(room, Vector3(8, 0.1, 8), Vector3(0, 3.05, 0), wall, "Ceiling")
	box(room, Vector3(3.2, 0.02, 2.2), Vector3(0, 0.01, -1.0), rug, "Rug")

	# sofa against the left wall
	box(room, Vector3(0.9, 0.45, 2.4), Vector3(-3.4, 0.25, -1.0), fabric, "SofaSeat")
	box(room, Vector3(0.25, 0.9, 2.4), Vector3(-3.85, 0.55, -1.0), fabric, "SofaBack")
	for z in [-1.7, -1.0, -0.3]:
		box(room, Vector3(0.18, 0.45, 0.55), Vector3(-3.65, 0.7, z), cushion, "Cushion")

	# round coffee table with plant and diffuser
	cyl(room, 0.6, 0.6, 0.45, Vector3(0, 0.225, -1.0), wood, "CoffeeTable")
	cyl(room, 0.14, 0.11, 0.22, Vector3(0.15, 0.56, -1.05), pot, "PlantPot")
	sphere(room, 0.22, Vector3(0.15, 0.82, -1.05), leaf, "PlantLeaves")
	sphere(room, 0.14, Vector3(0.30, 0.95, -0.95), leaf, "PlantLeaves2")
	cyl(room, 0.05, 0.07, 0.22, Vector3(-0.25, 0.56, -0.9), glass_g, "Diffuser")
	for i in 5:
		var s := cyl(room, 0.006, 0.006, 0.35, Vector3(-0.25 + 0.02 * (i - 2), 0.82, -0.9), wood_dark, "Reed")
		s.rotation = Vector3(0.0, 0.0, 0.12 * (i - 2))

	# back bar: shelves with bottles
	box(room, Vector3(3.0, 2.2, 0.35), Vector3(1.6, 1.1, -3.78), wood_dark, "ShelfBody")
	for y in [0.55, 1.15, 1.75]:
		box(room, Vector3(2.9, 0.04, 0.32), Vector3(1.6, y, -3.6), wood, "ShelfBoard")
		for i in 9:
			var g := glass_g if (i + int(y * 10)) % 2 == 0 else glass_p
			cyl(room, 0.045, 0.06, 0.32, Vector3(0.35 + i * 0.31, y + 0.18, -3.62), g, "Bottle")
	box(room, Vector3(3.2, 1.05, 0.6), Vector3(1.6, 0.525, -2.6), wood, "BarCounter")
	box(room, Vector3(3.3, 0.06, 0.7), Vector3(1.6, 1.08, -2.6), brass, "BarTop")

	# pendant lamps
	for x in [-0.4, 0.4]:
		cyl(room, 0.01, 0.01, 1.2, Vector3(x, 2.4, -1.0), lamp_m, "LampCord")
		cyl(room, 0.06, 0.22, 0.25, Vector3(x, 1.7, -1.0), lamp_m, "LampShade")

	# wall art
	box(room, Vector3(0.05, 0.9, 1.4), Vector3(3.95, 1.7, -1.0), art, "Painting")
	box(room, Vector3(1.0, 0.7, 0.05), Vector3(-1.6, 1.8, -3.95), mat(Color(0.20, 0.45, 0.65)), "Poster")

	# lights
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.35
	sun.shadow_enabled = true
	root.add_child(sun)
	for x in [-0.4, 0.4]:
		var l := OmniLight3D.new()
		l.position = Vector3(x, 1.5, -1.0)
		l.light_color = Color(1.0, 0.85, 0.65)
		l.light_energy = 0.7
		l.omni_range = 5.0
		l.shadow_enabled = true
		root.add_child(l)
