extends Node3D
## Rocket / grenade projectile with splash damage.

var vel := Vector3.ZERO
var def: Dictionary = {}
var owner_player = null
var life := 6.0
var _mesh: MeshInstance3D

func setup(origin: Vector3, dir: Vector3, w: Dictionary, src) -> void:
	global_position = origin
	vel = dir * w["speed"]
	def = w
	owner_player = src
	var sm := SphereMesh.new()
	sm.radius = 0.14 if w["kind"] == GameTypes.FireKind.ROCKET else 0.1
	sm.height = sm.radius * 2.0
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.15, 0.15, 0.17)
	_mesh.material_override = m
	add_child(_mesh)

func _physics_process(d: float) -> void:
	life -= d
	if life <= 0.0:
		detonate()
		return
	var step := vel * d
	vel.y -= 18.0 * d
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	q.collision_mask = 1 | 4 | 16 | 32
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		global_position += step
	else:
		global_position = hit["position"]
		detonate()

func detonate() -> void:
	Fx.explosion(global_position, def.get("radius", 4.0))
	for c in get_tree().get_nodes_in_group("combatants"):
		if c == owner_player or not is_instance_valid(c):
			continue
		var dist: float = c.global_position.distance_to(global_position)
		if dist > def.get("radius", 4.0):
			continue
		var radius: float = def.get("radius", 4.0)
		var falloff: float = 1.0 - dist / max(radius, 0.001)
		c.take_damage(float(def["damage"]) * falloff, owner_player, global_position, Vector3.ZERO, def)
	for b in get_tree().get_nodes_in_group("builds"):
		if is_instance_valid(b) and b.global_position.distance_to(global_position) < def.get("radius", 4.0):
			b.queue_free()
	queue_free()
