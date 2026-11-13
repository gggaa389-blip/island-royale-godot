extends Node
## Match flow: bus drop, loot, storm phases, elimination feed, victory.

enum Phase { LOBBY, BUS, GLIDER, LIVE, OVER }

signal phase_changed(p: int)
signal feed(text: String)
signal storm_changed(center: Vector2, radius: float)
signal alive_changed(n: int)

var phase: int = Phase.LOBBY
var alive := 0
var total := 0
var bots_total := 4

@export var island_half := 280.0

# storm state
var storm_center := Vector2.ZERO
var storm_radius := 420.0
var storm_target := 420.0
var storm_damage := 1.0
var storm_phase := 0
var storm_timer := 0.0
var _storm_vis: Node3D

# storm schedule: wait, shrink, radius, dps
const SCHEDULE := [
	[55.0, 25.0, 260.0, 1.0],
	[45.0, 25.0, 170.0, 2.0],
	[40.0, 20.0, 105.0, 4.0],
	[35.0, 20.0, 60.0, 7.0],
	[30.0, 18.0, 28.0, 11.0],
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func start(bot_count: int = 24) -> void:
	bots_total = bot_count
	Building.clear_all()
	storm_phase = 0
	storm_timer = SCHEDULE[0][0]
	storm_radius = 460.0
	storm_target = 460.0
	storm_damage = SCHEDULE[0][3]
	storm_center = Vector2.ZERO
	phase = Phase.BUS
	phase_changed.emit(phase)
	set_process(true)

	var world := get_tree().current_scene.get_node_or_null("World")
	if world == null:
		push_warning("no World node")
		return

	# spawn the player high above the island (bus drop)
	var player = preload("res://scripts/Player.gd").new()
	player.is_bot = false
	player.display_name = "You"
	player.name = "Player"
	var a := randf() * TAU
	var r := randf() * 120.0
	player.global_position = Vector3(cos(a) * r, 300.0, sin(a) * r)
	world.add_child(player)
	Match.player = player

	# spawn bots
	var bot_script = load("res://scripts/Bot.gd")
	var names := ["Amy", "Ninja", "Jackie", "Kate", "Ortiz", "Timmy", "Claire",
			"Remy", "Michelle", "Vanguard", "Kaya", "Ty", "Doozy", "Swat",
			"BigVegas", "SportyGranny"]
	for i in bots_total:
		var b = bot_script.new()
		b.is_bot = true
		b.display_name = names[i % names.size()] + str(i / names.size() + 1)
		b.name = "Bot_%d" % i
		var ang := randf() * TAU
		var rad := randf() * (island_half * 0.85)
		b.global_position = Vector3(cos(ang) * rad, 60.0, sin(ang) * rad)
		b.give(GameTypes.new_item_weapon(GameTypes.weapon("assault_rifle"),
				GameTypes.roll_rarity(false)), 0)
		b.give(GameTypes.new_item_weapon(GameTypes.weapon("pickaxe"), 0), 5)
		world.add_child(b)

	total = bots_total + 1
	alive = total
	alive_changed.emit(alive)
	spawn_loot(world)
	phase = Phase.GLIDER
	phase_changed.emit(phase)

var player = null

func spawn_loot(world: Node) -> void:
	# scattered floor loot + chests
	var weapon_ids := ["assault_rifle", "shotgun", "pistol", "sniper_rifle",
			"rocket_launcher", "grenade"]
	var chests := 60
	for i in chests:
		var a := randf() * TAU
		var r := sqrt(randf()) * island_half * 0.9
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		# sample terrain height if available
		var terr := world.get_node_or_null("Terrain")
		if terr != null and terr.has_method("height_at"):
			p.y = terr.height_at(p.x, p.z) + 0.4
		else:
			p.y = 8.0
		var is_chest := i % 3 == 0
		var wid: String = weapon_ids[randi() % weapon_ids.size()]
		var it := GameTypes.new_item_weapon(GameTypes.weapon(wid),
				GameTypes.roll_rarity(is_chest))
		Pickups.spawn(world, p, it)
		if is_chest:
			for _k in 2:
				var wid2: String = weapon_ids[randi() % weapon_ids.size()]
				Pickups.spawn(world, p + Vector3(randf_range(-1.2, 1.2), 0.0,
						randf_range(-1.2, 1.2)),
						GameTypes.new_item_weapon(GameTypes.weapon(wid2),
						GameTypes.roll_rarity(true)))
	# ammo boxes
	for i in 120:
		var a := randf() * TAU
		var r := sqrt(randf()) * island_half * 0.95
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var terr := world.get_node_or_null("Terrain")
		p.y = (terr.height_at(p.x, p.z) + 0.35) if terr and terr.has_method("height_at") else 8.0
		Pickups.spawn_ammo(world, p, 1 + randi() % 4)

func _process(d: float) -> void:
	if phase != Phase.LIVE and phase != Phase.GLIDER:
		return

	# storm schedule
	storm_timer -= d
	if storm_phase < SCHEDULE.size():
		var s: Array = SCHEDULE[storm_phase]
		if storm_timer <= 0.0:
			if storm_radius > storm_target + 0.5:
				# shrink
				var rate: float = (storm_radius - s[2]) / s[1] if s[1] > 0.0 else 0.0
				storm_radius = max(storm_radius - rate * d * 6.0, s[2])
			else:
				storm_phase += 1
				if storm_phase < SCHEDULE.size():
					var ns: Array = SCHEDULE[storm_phase]
					storm_timer = ns[0]
					storm_target = ns[2]
					storm_damage = ns[3]
					feed.emit("Storm shrinking")
	storm_changed.emit(storm_center, storm_radius)

	# damage everyone outside the circle
	storm_timer = max(storm_timer, -1.0)
	for c in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(c) or not c.alive:
			continue
		var p2 := Vector2(c.global_position.x, c.global_position.z)
		if p2.distance_to(storm_center) > storm_radius:
			c.take_damage(storm_damage * d, null, c.global_position, Vector3.ZERO, null)

func on_eliminated(victim, killer) -> void:
	alive = max(alive - 1, 0)
	alive_changed.emit(alive)
	var who := "The Storm" if killer == null else str(killer.display_name)
	feed.emit("%s eliminated %s" % [who, str(victim.display_name)])
	if victim == player:
		phase = Phase.OVER
		phase_changed.emit(phase)
		feed.emit("#%d  -  %d left" % [alive + 1, alive])
	elif alive <= 1:
		phase = Phase.OVER
		phase_changed.emit(phase)
		feed.emit("VICTORY ROYALE")
