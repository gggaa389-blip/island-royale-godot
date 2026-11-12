extends "res://scripts/Player.gd"
## Bot brain: roam the island, engage the nearest enemy, reposition and shoot.

enum S { ROAM, ENGAGE, REPOSITION }

var state: int = S.ROAM
var target = null
var wander_target := Vector3.ZERO
var retarget_timer := 0.0
var fire_hold := 0.0
var strafe_dir := 1.0
var strafe_timer := 0.0
var skill := 0.75

func _ready() -> void:
	is_bot = true
	super._ready()
	skill = randf_range(0.45, 0.9)
	var gi = GameInput
	# bots never read real input
	set_physics_process(true)

func _physics_process(d: float) -> void:
	if not alive:
		return
	retarget_timer -= d
	strafe_timer -= d
	if retarget_timer <= 0.0:
		retarget_timer = 0.35
		target = pick_target()
		state = S.ENGAGE if target != null else S.ROAM
	if strafe_timer <= 0.0:
		strafe_timer = randf_range(0.6, 1.6)
		strafe_dir = 1.0 if randf() < 0.5 else -1.0

	var wish := Vector3.ZERO
	if target != null and is_instance_valid(target) and target.alive:
		var to := target.global_position - global_position
		var dist := to.length()
		var w: Dictionary = current_weapon()
		var want := w.get("bot_range", 30.0) if not w.is_empty() else 30.0
		face_towards(target.global_position + Vector3(0.0, 1.2, 0.0))
		if dist > want * 1.25:
			wish = to.normalized()
		elif dist < want * 0.7:
			wish = -to.normalized()
		else:
			wish = Vector3(to.z, 0.0, -to.x).normalized() * strafe_dir
		try_shoot(dist, want)
	else:
		if wander_target == Vector3.ZERO or global_position.distance_to(wander_target) < 8.0:
			wander_target = random_point()
		wish = (wander_target - global_position)
		wish.y = 0.0
		wish = wish.normalized()
		yaw = atan2(-wish.x, -wish.z)

	# apply as GameInput-style movement without touching the global singleton
	var speed := WALK
	velocity.x = wish.x * speed
	velocity.z = wish.z * speed
	if velocity.length_squared() > 0.01:
		global_rotation.y = atan2(-wish.x, -wish.z)
	if not is_on_floor():
		velocity.y -= GRAVITY * d
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()

func face_towards(p: Vector3) -> void:
	var d := (p - _cam.global_position).normalized()
	yaw = atan2(-d.x, -d.z)
	pitch = clamp(-asin(d.y), -1.2, 1.2)
	global_rotation.y = yaw
	_pivot.rotation.x = pitch

func try_shoot(dist: float, want: float) -> void:
	if not current_weapon_valid():
		return
	var w: Dictionary = current_weapon()
	if w["kind"] == GameTypes.FireKind.MELEE:
		return
	var it := current_item()
	if it.is_empty():
		return
	if it["mag"] <= 0:
		start_reload()
		return
	if dist > w["range"] * 0.9:
		return
	if abs(dist - want) > want * 1.4:
		return
	fire_hold -= get_physics_process_delta_time()
	if fire_hold > 0.0:
		return
	fire_hold = w["interval"] * (1.6 - skill)
	# aim error by skill
	var err := (1.0 - skill) * 0.09
	var origin := _cam.global_position
	var dir := -_cam.global_transform.basis.z
	dir = dir.rotated(Vector3.UP, randf_range(-err, err))
	dir = dir.rotated(_cam.global_transform.basis.x, randf_range(-err, err))
	if w["kind"] == GameTypes.FireKind.HITSCAN:
		it["mag"] -= 1
		hitscan(w, it, origin, dir)
	else:
		it["mag"] -= 1
		spawn_projectile(w, it, origin, dir)

func pick_target():
	var best = null
	var best_d := 90.0
	for c in get_tree().get_nodes_in_group("combatants"):
		if c == self or not is_instance_valid(c) or not c.alive:
			continue
		var d := global_position.distance_to(c.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best

func random_point() -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * Match.island_half * 0.9
	var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
	var terr := get_tree().current_scene.get_node_or_null("World/Terrain")
	if terr != null and terr.has_method("height_at"):
		p.y = terr.height_at(p.x, p.z)
	return p
