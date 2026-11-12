extends Node3D
## Rebuilds the island: instantiates every prefab placement extracted from
## Unity's Island.unity (2381 instances) at their original transform.

@export var cull_distance := 420.0      # hide distant props (mobile perf)
@export var enabled := true

# Unity is left-handed-ish on X for positions: mirror X and swap quat x/z sign
const MIRROR_X := true

func _ready() -> void:
	if enabled:
		build()

func build() -> void:
	var path := "res://assets/data/island_placements.json"
	if not FileAccess.file_exists(path):
		push_warning("island placements missing")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if data == null:
		push_warning("island placements unreadable")
		return

	var prefabs: Dictionary = data["prefabs"]
	var placements: Array = data["placements"]

	# cache loaded scenes
	var cache := {}
	var placed := 0
	var missing := 0
	var proxy_count := 0

	for p in placements:
		var guid: String = p["g"]
		if not prefabs.has(guid):
			missing += 1
			continue
		var scene_path: String = prefabs[guid]
		if not cache.has(scene_path):
			if ResourceLoader.exists(scene_path) and scene_is_loadable(scene_path):
				cache[scene_path] = load(scene_path)
			else:
				cache[scene_path] = null
		var sc = cache[scene_path]
		if sc == null:
			# the extracted model is not available: stand in a procedural proxy so
			# the island still has cover and silhouette. Real assets replace these
			# automatically once they are restored.
			var proxy := make_proxy(scene_path.get_file().get_basename())
			if proxy == null:
				missing += 1
				continue
			apply_transform(proxy, p)
			add_child(proxy)
			proxy_count += 1
			continue
		var inst = sc.instantiate()
		apply_transform(inst, p)
		add_child(inst)
		placed += 1

	print("[island] placed %d, procedural proxies %d, missing %d (of %d)" % [placed, proxy_count, missing, placements.size()])

func apply_transform(node: Node3D, p: Dictionary) -> void:
	var t: Array = p["t"]
	var q: Array = p["r"]
	var s: Array = p["s"]
	var px := float(t[0]); var py := float(t[1]); var pz := float(t[2])
	if MIRROR_X:
		px = -px
	var qx := float(q[0]); var qy := float(q[1]); var qz := float(q[2]); var qw := float(q[3])
	if MIRROR_X:
		qx = -qx
		qz = -qz
	# Unity (left-handed, Y up) -> Godot (right-handed, Y up): negate Z axis
	node.transform = Transform3D(
		Basis(Quaternion(qx, qy, -qz, -qw)).scaled(Vector3(float(s[0]), float(s[1]), float(s[2]))),
		Vector3(px, py, -pz))

## Stand-in geometry used until the converted Unity models are available.
func make_proxy(prefab_name: String) -> Node3D:
	var n := prefab_name.to_lower()
	var root := Node3D.new()
	root.name = "proxy_" + prefab_name

	if n.begins_with("tree"):
		if n.contains("palm"):
			var trunk := _mesh_cyl(0.22, 0.16, 6.0, Color(0.45, 0.34, 0.20))
			trunk.position.y = 3.0
			root.add_child(trunk)
			var top := _mesh_sphere(1.9, Color(0.24, 0.46, 0.20))
			top.position.y = 6.2
			top.scale = Vector3(1.0, 0.42, 1.0)
			root.add_child(top)
		else:
			var trunk := _mesh_cyl(0.28, 0.22, 3.4, Color(0.38, 0.28, 0.17))
			trunk.position.y = 1.7
			root.add_child(trunk)
			var c1 := _mesh_cone(2.3, 5.0, Color(0.18, 0.40, 0.18))
			c1.position.y = 4.6
			root.add_child(c1)
			var c2 := _mesh_cone(1.7, 3.6, Color(0.22, 0.46, 0.20))
			c2.position.y = 6.6
			root.add_child(c2)
	elif n.begins_with("bush"):
		var b := _mesh_sphere(1.1, Color(0.26, 0.48, 0.22))
		b.position.y = 0.7
		b.scale = Vector3(1.0, 0.7, 1.0)
		root.add_child(b)
	elif n.begins_with("rock"):
		var r := _mesh_box(Vector3(2.4, 1.6, 2.2), Color(0.44, 0.43, 0.41))
		r.position.y = 0.7
		r.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))
		root.add_child(r)
	elif n.begins_with("house") or n.begins_with("warehouse"):
		root.add_child(_building(8.0, 6.0, 8.0, Color(0.72, 0.68, 0.60)))
	elif n.begins_with("fence"):
		var f := _mesh_box(Vector3(2.0, 1.2, 0.16), Color(0.55, 0.42, 0.26))
		f.position.y = 0.9
		root.add_child(f)
	elif n.begins_with("wood_crate") or n.begins_with("crate"):
		var c := _mesh_box(Vector3(1.1, 1.1, 1.1), Color(0.62, 0.46, 0.26))
		c.position.y = 0.55
		root.add_child(c)
	elif n.begins_with("lookout") or n.begins_with("tower"):
		root.add_child(_tower())
	else:
		var g := _mesh_box(Vector3(1.4, 1.0, 1.4), Color(0.60, 0.58, 0.52))
		g.position.y = 0.5
		root.add_child(g)

	# every proxy mesh gets a collider so it blocks shots and movement
	for mi in _collect_meshes(root):
		var body := _collider_for(mi)
		if body != null:
			mi.add_child(body)
	return root

func _collect_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_collect_meshes(c))
	return out

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.92
	return m

func _mesh_box(sz: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	m.mesh = bm
	m.material_override = _mat(col)
	return m

func _mesh_sphere(r: float, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	m.mesh = sm
	m.material_override = _mat(col)
	return m

func _mesh_cone(r: float, h: float, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 9
	m.mesh = cm
	m.material_override = _mat(col)
	return m

func _mesh_cyl(rt: float, rb: float, h: float, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rt
	cm.bottom_radius = rb
	cm.height = h
	cm.radial_segments = 8
	m.mesh = cm
	m.material_override = _mat(col)
	return m

func _building(w: float, h: float, d: float, col: Color) -> Node3D:
	var g := Node3D.new()
	var walls := _mesh_box(Vector3(w, h, d), col)
	walls.position.y = h * 0.5
	g.add_child(walls)
	var roof := _mesh_box(Vector3(w * 1.1, 0.3, d * 1.1), Color(0.42, 0.28, 0.24))
	roof.position.y = h + 0.15
	g.add_child(roof)
	return g

func _tower() -> Node3D:
	var g := Node3D.new()
	for i in 4:
		var leg := _mesh_box(Vector3(0.3, 9.0, 0.3), Color(0.5, 0.38, 0.24))
		leg.position = Vector3(-2.0 + (i % 2) * 4.0, 4.5, -2.0 + (i / 2) * 4.0)
		g.add_child(leg)
	var deck := _mesh_box(Vector3(5.0, 0.3, 5.0), Color(0.55, 0.42, 0.28))
	deck.position.y = 9.0
	g.add_child(deck)
	return g

func _collider_for(m: MeshInstance3D) -> StaticBody3D:
	if m.mesh == null:
		return null
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var s2 = m.mesh.create_trimesh_shape()
	if s2 == null:
		return null
	cs.shape = s2
	b.add_child(cs)
	return b

## A converted .tscn whose models were not restored will fail to instantiate;
## detect that up front and fall back to a proxy instead of crashing.
func scene_is_loadable(tscn_path: String) -> bool:
	if not FileAccess.file_exists(tscn_path):
		return false
	var f := FileAccess.open(tscn_path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var re := RegEx.new()
	re.compile('\\[ext_resource[^\\]]*path="res://([^"]+)"')
	for m in re.search_all(text):
		var rp := "res://" + m.get_string(1)
		if not ResourceLoader.exists(rp):
			return false
	return true
