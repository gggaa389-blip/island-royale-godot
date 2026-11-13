extends SceneTree
# Captures in-game screenshots by driving the real scene under a software renderer.

var f := 0
var main: Node
var player: Node3D = null
var terr: Node = null
var spots: Array = []
var si := 0

func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	spots = [
		[Vector3(0.0, 0.0, 0.0), 0.0],
		[Vector3(130.0, 0.0, -70.0), 2.3],
		[Vector3(-150.0, 0.0, 95.0), -1.1],
		[Vector3(70.0, 0.0, 165.0), 3.5],
	]
	# SceneTree._process runs every frame once defined

func _process(_d: float) -> bool:
	f += 1
	if f == 8:
		_shot("01_menu.png")
	elif f == 14:
		main._on_start()
	elif f == 45:
		player = Match.player
		terr = main.get_node_or_null("World/Terrain")
		_place(0)
	elif f == 95:
		_shot("02_island_center.png")
	elif f == 110:
		_place(1)
	elif f == 160:
		_shot("03_island_coast.png")
	elif f == 175:
		_place(2)
	elif f == 225:
		_shot("04_island_ridge.png")
	elif f == 240:
		_place(3)
	elif f == 290:
		_shot("05_island_far.png")
	elif f == 320:
		_hudshot("06_hud_closeup.png")
	elif f > 340:
		quit()
	return false

func _place(i: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var p: Vector3 = spots[i][0]
	var h := 8.0
	if terr != null and terr.has_method("height_at"):
		h = terr.height_at(p.x, p.z)
	player.global_position = Vector3(p.x, h + 1.2, p.z)
	player.yaw = spots[i][1]
	player.pitch = -0.12
	player.global_rotation.y = player.yaw
	player.velocity = Vector3.ZERO

func _shot(name: String) -> void:
	var img: Image = root.get_texture().get_image()
	img.save_png("/home/user/shots/" + name)
	print("SHOT: ", name, " ", img.get_size())

func _hudshot(name: String) -> void:
	# frame the HUD and the character: pull the camera in and look slightly down
	if player != null and is_instance_valid(player):
		player.pitch = 0.05
	_shot(name)
