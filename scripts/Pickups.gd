extends Node
## Floor loot, chest piles and ammo boxes the player walks over to collect.

var _root: Node3D

func root_node() -> Node3D:
	if _root == null or not is_instance_valid(_root):
		_root = Node3D.new()
		_root.name = "Pickups"
		get_tree().current_scene.add_child(_root)
	return _root

func clear() -> void:
	var r := root_node()
	for c in r.get_children():
		c.queue_free()

func spawn(world: Node, pos: Vector3, item: Dictionary) -> void:
	var a := Area3D.new()
	a.position = pos
	a.collision_layer = 8        # layer 4
	a.collision_mask = 2         # detect the player
	a.set_meta("item", item)
	a.set_meta("kind", "item")
	a.add_to_group("pickups")

	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.55, 0.55)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	var col: Color = GameTypes.RARITY_COLORS.get(item["rarity"], Color(0.8, 0.8, 0.8))
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.6
	m.material_override = mat
	m.position.y = 0.3
	a.add_child(m)

	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 1.1
	cs.shape = ss
	a.add_child(cs)

	a.body_entered.connect(_on_pickup.bind(a))
	root_node().add_child(a)

	# idle spin
	var tw := a.create_tween()
	tw.set_loops()
	tw.tween_property(m, "rotation:y", TAU, 3.0).as_relative()

func spawn_ammo(world: Node, pos: Vector3, ammo_type: int) -> void:
	var a := Area3D.new()
	a.position = pos
	a.collision_layer = 8
	a.collision_mask = 2
	a.set_meta("kind", "ammo")
	a.set_meta("ammo", ammo_type)
	a.set_meta("count", GameTypes.AMMO_PILE.get(ammo_type, 10))
	a.add_to_group("pickups")

	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.35, 0.28, 0.5)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.75, 0.3)
	m.material_override = mat
	m.position.y = 0.2
	a.add_child(m)

	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 1.0
	cs.shape = ss
	a.add_child(cs)
	a.body_entered.connect(_on_pickup.bind(a))
	root_node().add_child(a)

func _on_pickup(body: Node3D, area: Area3D) -> void:
	if not is_instance_valid(area):
		return
	if not body.has_method("give"):
		return
	var kind: String = area.get_meta("kind", "")
	if kind == "item":
		var item: Dictionary = area.get_meta("item", {})
		if item.is_empty():
			return
		# stack if possible, otherwise take a free slot
		if GameTypes.item_stacks(item):
			for i in 5:
				var cur = body.items[i]
				if cur != null and cur.get("consumable") != null and item.get("consumable") != null \
						and cur["consumable"]["id"] == item["consumable"]["id"]:
					var room: int = GameTypes.item_max_stack(cur) - cur["mag"]
					if room > 0:
						cur["mag"] += mini(room, item["mag"])
						body.inventory_changed.emit()
						area.queue_free()
						return
		if body.give(item, -1):
			# top up reserve ammo when picking up a weapon
			if item["weapon"] != null and item["weapon"]["ammo"] != 0:
				body.add_ammo(item["weapon"]["ammo"], GameTypes.AMMO_PILE[item["weapon"]["ammo"]])
			area.queue_free()
	elif kind == "ammo":
		var t: int = area.get_meta("ammo", 0)
		body.add_ammo(t, area.get_meta("count", 0))
		body.inventory_changed.emit()
		area.queue_free()
