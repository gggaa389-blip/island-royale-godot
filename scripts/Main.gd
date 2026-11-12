extends Node3D
## Entry point: builds the world, shows the start menu, begins the match.

@onready var world: Node3D = $World

var _menu: Control
var _terrain: Node3D

func _ready() -> void:
	randomize()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	build_world()
	build_menu()

func build_world() -> void:
	# sun
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_bias = 0.03
	world.add_child(sun)

	# sky + ambient
	var env := WorldEnvironment.new()
	var sky := Sky.new()
	var pm := ProceduralSkyMaterial.new()
	pm.sky_top_color = Color(0.24, 0.46, 0.85)
	pm.sky_horizon_color = Color(0.68, 0.80, 0.92)
	pm.ground_bottom_color = Color(0.30, 0.33, 0.28)
	pm.sun_angle_max = 25.0
	sky.sky_material = pm
	var enviro := Environment.new()
	enviro.background_mode = Environment.BG_SKY
	enviro.sky = sky
	enviro.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	enviro.ambient_light_sky_contribution = 0.85
	enviro.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	enviro.fog_enabled = true
	enviro.fog_light_color = Color(0.70, 0.80, 0.90)
	enviro.fog_density = 0.0016
	env.environment = enviro
	world.add_child(env)

	# terrain (heightmap extracted from Unity)
	var terr_script = load("res://scripts/Terrain.gd")
	_terrain = Node3D.new()
	_terrain.name = "Terrain"
	_terrain.set_script(terr_script)
	world.add_child(_terrain)

	# island props (2381 placements from Island.unity)
	var island_script = load("res://scripts/Island.gd")
	var island := Node3D.new()
	island.name = "Island"
	island.set_script(island_script)
	world.add_child(island)

	# ocean plane
	var water := MeshInstance3D.new()
	water.name = "Water"
	var pm2 := PlaneMesh.new()
	pm2.size = Vector2(2400.0, 2400.0)
	pm2.subdivide_width = 8
	pm2.subdivide_depth = 8
	water.mesh = pm2
	water.position.y = 3.1
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.10, 0.32, 0.46, 0.88)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.14
	wm.metallic = 0.06
	water.material_override = wm
	world.add_child(water)

func build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.09, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-220, -140)
	box.size = Vector2(440, 280)
	_menu.add_child(box)

	var title := Label.new()
	title.text = "ISLAND ROYALE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Battle Royale  -  100 players  -  last one standing"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	box.add_child(spacer)

	var start := Button.new()
	start.text = "START MATCH"
	start.custom_minimum_size = Vector2(320, 78)
	start.pressed.connect(_on_start)
	box.add_child(start)

	var hint := Label.new()
	hint.text = "Desktop: WASD + mouse   |   Mobile: left stick to move, drag right side to look"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	box.add_child(hint)

func _on_start() -> void:
	_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not GameInput.touch_mode else Input.MOUSE_MODE_VISIBLE
	Match.start(28)
	if Match.player != null:
		Match.player.inventory_changed.connect($HUD._rebuild_slots)
		Match.player.health_changed.connect(func(_h, _s): pass)

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
