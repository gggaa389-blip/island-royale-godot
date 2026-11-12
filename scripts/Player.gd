extends CharacterBody3D
## Player + shared combatant logic (health, shield, inventory, weapons, building).

const WALK := 5.2
const SPRINT := 8.0
const CROUCH := 2.4
const ADS_SPEED := 3.2
const JUMP_VEL := 7.4
const GRAVITY := 22.0
const EYE := 1.62

signal health_changed(hp: float, shield: float)
signal inventory_changed()
signal died(killer)

@export var is_bot := false
@export var display_name := "Player"

var health := 100.0
var shield := 100.0
var alive := true

# inventory: 5 slots + pickaxe (slot 5)
var items: Array = []            # Array[Dictionary]
var ammo := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
var mats := [0, 0, 0]            # wood, brick, metal
var active_slot := 0

var yaw := 0.0
var pitch := 0.0
var bloom := 0.0
var next_fire := 0.0
var reloading_left := 0.0
var using_left := 0.0
var using_item := {}
var build_mat := 0

var rig: Node3D
var _cam: Node3D
var _pivot: Node3D
var _weapon_view: Node3D
var _hitbox: Area3D

func _ready() -> void:
	add_to_group("combatants")
	setup_nodes()
	if items.is_empty():
		items = [null, null, null, null, null]
		give(GameTypes.new_item_weapon(GameTypes.weapon("pickaxe"), 0), 5)

func setup_nodes() -> void:
	# collision
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.75
	col.shape = cap
	col.position.y = 0.88
	add_child(col)
	collision_layer = 2
	collision_mask = 1 | 32

	# humanoid body built from the original Mixamo character textures
	var rig_script = load("res://scripts/CharacterRig.gd")
	rig = Node3D.new()
	rig.name = "Rig"
	rig.set_script(rig_script)
	var tint := Color(0.68, 0.84, 1.0) if not is_bot else Color(1.0, 0.74, 0.58)
	rig.build(-1 if not is_bot else (randi() % 11), tint)
	add_child(rig)

	# hitbox area on a separate layer so raycasts can find it
	_hitbox = Area3D.new()
	_hitbox.name = "Hitbox"
	_hitbox.collision_layer = 4
	_hitbox.collision_mask = 0
	var hc := CollisionShape3D.new()
	var hcap := CapsuleShape3D.new()
	hcap.radius = 0.5
	hcap.height = 1.9
	hc.shape = hcap
	hc.position.y = 0.95
	_hitbox.add_child(hc)
	_hitbox.set_meta("owner_combatant", self)
	add_child(_hitbox)

	# camera rig
	_pivot = Node3D.new()
	_pivot.name = "CamPivot"
	_pivot.position.y = EYE
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.position = Vector3(0.55, 0.18, 3.1)
	_cam.fov = 75.0
	_cam.near = 0.12
	_cam.far = 900.0
	_pivot.add_child(_cam)

# ------------------------------------------------------------------ movement
func _physics_process(d: float) -> void:
	if not alive:
		return
	if not is_bot:
		apply_player_input(d)

	if not is_on_floor():
		velocity.y -= GRAVITY * d
	elif velocity.y < 0.0:
		velocity.y = 0.0

	move_and_slide()
	_animate(d, GameInput.aiming)

func _animate(d: float, aiming: bool) -> void:
	if rig != null and rig.has_method("animate"):
		rig.animate(Vector2(velocity.x, velocity.z).length(), d, aiming)

func apply_player_input(d: float) -> void:
	var gi = GameInput
	# look
	yaw -= gi.look.x
	pitch = clamp(pitch - gi.look.y, -1.45, 1.45)
	global_rotation.y = yaw
	_pivot.rotation.x = pitch

	# move
	var dir := Vector3.ZERO
	var wish: Vector2 = gi.move
	var basis := Basis(Vector3.UP, yaw)
	dir += basis * Vector3(wish.x, 0.0, wish.y)
	dir = dir.normalized() if dir.length() > 0.0 else Vector3.ZERO

	var speed := WALK
	if gi.crouching: speed = CROUCH
	elif gi.aiming and current_weapon_valid(): speed = ADS_SPEED
	elif gi.sprinting and wish.y < 0.1: speed = SPRINT

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	if gi.jumping and is_on_floor():
		velocity.y = JUMP_VEL

	# actions
	if gi.slot_request >= 0 and gi.slot_request < 5:
		select_slot(gi.slot_request)
	if gi.reloading:
		start_reload()
		gi.reloading = false
	if gi.build_request >= 0:
		try_build(gi.build_request)
		gi.build_request = -1

	handle_fire(d)

# ------------------------------------------------------------------ inventory
func give(item: Dictionary, slot: int = -1) -> bool:
	if slot < 0:
		for i in 5:
			if items[i] == null:
				slot = i
				break
	if slot < 0 or slot > 4:
		return false
	if items[slot] != null and GameTypes.item_is_weapon(items[slot]) \
			and GameTypes.item_is_weapon(item) \
			and items[slot]["weapon"]["id"] == item["weapon"]["id"]:
		items[slot]["mag"] = item["weapon"]["mag"]
	else:
		items[slot] = item
	inventory_changed.emit()
	return true

func add_ammo(type: int, n: int) -> void:
	if type == 0:
		return
	ammo[type] = mini(ammo[type] + n, GameTypes.AMMO_CAP[type])

func add_mats(m: int, n: int) -> void:
	mats[m] = mini(mats[m] + n, GameTypes.MAX_MATS)

func select_slot(i: int) -> void:
	if i == active_slot:
		return
	active_slot = i
	reloading_left = 0.0
	using_left = 0.0
	inventory_changed.emit()

func current_item() -> Dictionary:
	if active_slot >= 0 and active_slot < 5 and items[active_slot] != null:
		return items[active_slot]
	return {}

func current_weapon() -> Dictionary:
	var it: Dictionary = current_item()
	if it.is_empty():
		return {}
	if it["weapon"] != null:
		return it["weapon"]
	return GameTypes.weapon("pickaxe")

func current_weapon_valid() -> bool:
	return not current_weapon().is_empty()

# ------------------------------------------------------------------ combat
func handle_fire(d: float) -> void:
	next_fire -= d
	bloom = max(bloom - d * 4.0, 0.0)

	if reloading_left > 0.0:
		reloading_left -= d
		if reloading_left <= 0.0:
			finish_reload()
		return

	if using_left > 0.0:
		using_left -= d
		if using_left <= 0.0:
			finish_use()
		return

	if not GameInput.firing:
		return

	var it: Dictionary = current_item()
	if it.is_empty():
		return
	var w: Dictionary = it["weapon"] if it["weapon"] != null else {}
	if w.is_empty():
		return

	if w["kind"] == GameTypes.FireKind.CONSUME:
		begin_use()
		return
	if w["kind"] != GameTypes.FireKind.MELEE and it["mag"] <= 0:
		start_reload()
		return
	if not w["auto"] and not GameInput.fire_pressed:
		return
	if next_fire > 0.0:
		return

	next_fire = w["interval"]
	fire(w, it)

func fire(w: Dictionary, it: Dictionary) -> void:
	var origin := _cam.global_position
	var dir := -_cam.global_transform.basis.z
	var aiming := GameInput.aiming
	var spread: float = w["spread_ads"] if aiming else w["spread_hip"]
	spread += bloom
	bloom = min(bloom + w["bloom"], w["bloom_max"])

	match w["kind"]:
		GameTypes.FireKind.HITSCAN:
			it["mag"] -= 1
			for _p in w["pellets"]:
				var d2 := cone_dir(dir, spread)
				hitscan(w, it, origin, d2)
			kick(w["recoil"])
			inventory_changed.emit()
		GameTypes.FireKind.ROCKET, GameTypes.FireKind.GRENADE:
			it["mag"] -= 1
			spawn_projectile(w, it, origin, cone_dir(dir, spread))
			kick(w["recoil"])
			inventory_changed.emit()
		GameTypes.FireKind.MELEE:
			melee_swing(w, it, origin, dir)
		_:
			pass

func cone_dir(dir: Vector3, degrees: float) -> Vector3:
	if degrees <= 0.0:
		return dir
	var a := deg_to_rad(degrees)
	var up := Vector3.UP
	if abs(dir.dot(up)) > 0.98:
		up = Vector3.FORWARD
	var right := dir.cross(up).normalized()
	var real_up := right.cross(dir).normalized()
	var ang := randf() * TAU
	var r := sqrt(randf()) * a
	var off := (right * cos(ang) + real_up * sin(ang)) * tan(r)
	return (dir + off).normalized()

func kick(degrees: float) -> void:
	if is_bot:
		return
	pitch += deg_to_rad(degrees) * 0.35
	yaw += deg_to_rad(degrees) * randf_range(-0.15, 0.15)

func hitscan(w: Dictionary, it: Dictionary, origin: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * w["range"])
	q.collision_mask = 1 | 4 | 32
	q.exclude = [self]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var target = hit.get("collider")
	var point: Vector3 = hit["position"]
	var dist := origin.distance_to(point)

	var dmg: float = w["damage"] * GameTypes.damage_mult(it["rarity"])
	if dist > w["falloff_start"]:
		dmg *= max(0.35, 1.0 - (dist - w["falloff_start"]) / w["range"])

	if target is Area3D and target.has_meta("owner_combatant"):
		var victim: Node3D = target.get_meta("owner_combatant")
		var is_head: bool = point.y > victim.global_position.y + 1.55
		if is_head:
			dmg *= w["head_mult"]
		victim.take_damage(dmg, self, point, dir, w)
		Fx.hit_marker(is_head)
	else:
		# built pieces take damage / harvesting with the pickaxe
		if target != null and target.has_method("take_damage"):
			target.take_damage(dmg, self, point, dir, w)
		Fx.impact(point, hit.get("normal", Vector3.UP))

func melee_swing(w: Dictionary, _it: Dictionary, origin: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * w["range"])
	q.collision_mask = 1 | 4 | 32
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var target = hit.get("collider")
	if target is Area3D and target.has_meta("owner_combatant"):
		target.get_meta("owner_combatant").take_damage(w["damage"], self, hit["position"], dir, w)
	elif target != null and target.has_method("harvest"):
		target.harvest(self)
	else:
		Fx.impact(hit["position"], hit.get("normal", Vector3.UP))

func spawn_projectile(w: Dictionary, _it: Dictionary, origin: Vector3, dir: Vector3) -> void:
	var p = load("res://scripts/Projectile.tscn")
	if p == null:
		return
	var inst = p.instantiate()
	get_tree().current_scene.add_child(inst)
	inst.setup(origin, dir, w, self)

func start_reload() -> void:
	var it: Dictionary = current_item()
	if it.is_empty() or it["weapon"] == null:
		return
	var w: Dictionary = it["weapon"]
	if w["mag"] <= 0 or it["mag"] >= w["mag"]:
		return
	if ammo.get(w["ammo"], 0) <= 0:
		return
	reloading_left = w["reload"] * GameTypes.reload_mult(it["rarity"])

func finish_reload() -> void:
	var it: Dictionary = current_item()
	if it.is_empty() or it["weapon"] == null:
		return
	var w: Dictionary = it["weapon"]
	var need: int = w["mag"] - it["mag"]
	var have: int = ammo.get(w["ammo"], 0)
	var take: int = mini(need, have)
	it["mag"] += take
	ammo[w["ammo"]] = have - take
	inventory_changed.emit()

func begin_use() -> void:
	var it: Dictionary = current_item()
	if it.is_empty() or it["consumable"] == null:
		return
	using_item = it
	using_left = it["consumable"]["use_time"]

func finish_use() -> void:
	var it := using_item
	using_item = {}
	if it.is_empty() or it["consumable"] == null:
		return
	var c: Dictionary = it["consumable"]
	if c["heal"] > 0.0:
		health = min(health + c["heal"], c["heal_cap"])
	elif c["shield"] > 0.0:
		shield = min(shield + c["shield"], c["shield_cap"])
	it["mag"] -= 1
	if it["mag"] <= 0:
		var i := items.find(it)
		if i >= 0:
			items[i] = null
	health_changed.emit(health, shield)
	inventory_changed.emit()

# ------------------------------------------------------------------ building
func try_build(piece: int) -> void:
	if mats[build_mat] < GameTypes.BUILD_COST:
		return
	var origin := _cam.global_position
	var dir := -_cam.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 12.0)
	q.collision_mask = 1 | 32
	var hit := space.intersect_ray(q)
	var pos := origin + dir * 6.0
	if not hit.is_empty():
		pos = hit["position"]
	var g := GameTypes.GRID
	pos = Vector3(round(pos.x / g) * g, round(pos.y / GameTypes.LEVEL) * GameTypes.LEVEL,
			round(pos.z / g) * g)
	Building.place(piece, build_mat, pos, yaw, self)
	mats[build_mat] -= GameTypes.BUILD_COST
	inventory_changed.emit()

# ------------------------------------------------------------------ damage
func take_damage(amount: float, source, point: Vector3, _dir: Vector3, _w) -> void:
	if not alive:
		return
	var left: float = amount
	if shield > 0.0:
		var absorbed: float = min(shield, left)
		shield -= absorbed
		left -= absorbed
	if left > 0.0:
		health -= left
	health_changed.emit(health, shield)
	if not is_bot:
		Fx.damage_flash()
	if health <= 0.0:
		die(source)
	print("[dmg] %s <- %.0f (hp %.0f sh %.0f)" % [display_name, amount, health, shield])

func die(killer) -> void:
	if not alive:
		return
	alive = false
	health = 0.0
	died.emit(killer)
	Match.on_eliminated(self, killer)
	set_physics_process(false)
	var t := get_tree().create_timer(2.5)
	t.timeout.connect(queue_free)
