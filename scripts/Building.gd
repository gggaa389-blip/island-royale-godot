extends Node
## Fortnite-style building: wall / floor / ramp / cone with wood, brick, metal.
## Pieces are simple boxes (cheap for mobile) until the modular kit models are restored.

var _root: Node3D

func _ready() -> void:
	_root = Node3D.new()
	_root.name = "Builds"
	add_child(_root)
	# built pieces live on layer 5 (index 4 -> bit 16); player masks 1|32, so add 16
	set_process(false)

func ensure_root() -> Node3D:
	if _root == null or not is_instance_valid(_root):
		_root = Node3D.new()
		_root.name = "Builds"
		get_tree().current_scene.add_child(_root)
	return _root

var MAT_COLORS := {
	0: Color(0.55, 0.38, 0.20),
	1: Color(0.62, 0.30, 0.24),
	2: Color(0.55, 0.58, 0.62),
}

func place(piece: int, mat: int, pos: Vector3, yaw: float, owner_player) -> Node3D:
	var body := StaticBody3D.new()
	body.collision_layer = 16     # layer 5
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = round(yaw / (PI / 2.0)) * (PI / 2.0)
	body.set_meta("built", true)
	body.set_meta("mat", mat)
	body.set_meta("hp", GameTypes.MAX_HP[mat])
	body.set_meta("max_hp", GameTypes.MAX_HP[mat])
	body.set_meta("build_time", GameTypes.BUILD_TIME[mat])

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	match piece:
		GameTypes.PieceType.WALL:
			bm.size = Vector3(4.0, 4.0, 0.25)
			mesh.position.y = 2.0
		GameTypes.PieceType.FLOOR:
			bm.size = Vector3(4.0, 0.25, 4.0)
		GameTypes.PieceType.STAIRS:
			bm.size = Vector3(4.0, 0.25, 4.0)
			mesh.rotation.x = -deg_to_rad(26.0)
			mesh.position.y = 1.0
		_:
			bm.size = Vector3(4.0, 0.25, 4.0)
			mesh.rotation.x = deg_to_rad(38.0)
			mesh.position.y = 1.4
	mesh.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = MAT_COLORS.get(mat, Color(0.6, 0.4, 0.2))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.55
	mesh.material_override = m
	body.add_child(mesh)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	cs.position = mesh.position
	cs.rotation = mesh.rotation
	body.add_child(cs)

	body.set_script(load("res://scripts/BuiltPiece.gd"))
	ensure_root().add_child(body)

	# build-up: opaque when finished
	var t := create_tween()
	t.tween_property(m, "albedo_color:a", 1.0, GameTypes.BUILD_TIME[mat] * 0.35)
	return body

func clear_all() -> void:
	var r := ensure_root()
	for c in r.get_children():
		c.queue_free()
