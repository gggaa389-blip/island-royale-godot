extends CanvasLayer
## HUD + on-screen touch controls (landscape, stretches to fill any aspect).

var hp_label: Label
var shield_label: Label
var ammo_label: Label
var mats_label: Label
var alive_label: Label
var feed_box: VBoxContainer
var slots_box: HBoxContainer
var center_msg: Label
var stick_base: Control
var stick_knob: Control
var build_box: HBoxContainer

var _stick_center := Vector2.ZERO
var _stick_index := -1
var _look_index := -1
var _last_look := Vector2.ZERO

func _ready() -> void:
	layer = 10
	root = get_node_or_null("Root")
	hp_label = _find("HpLabel")
	shield_label = _find("ShieldLabel")
	ammo_label = _find("AmmoLabel")
	mats_label = _find("MatsLabel")
	alive_label = _find("AliveLabel")
	feed_box = _find("FeedBox")
	slots_box = _find("SlotsBox")
	center_msg = _find("CenterMessage")
	stick_base = _find("StickBase")
	stick_knob = _find("StickKnob")
	build_box = _find("BuildBox")

	Match.feed.connect(_on_feed)
	Match.alive_changed.connect(_on_alive)
	Match.phase_changed.connect(_on_phase)
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_connect_buttons()
	_rebuild_slots()

var root: Control

func _find(nm: String):
	if root == null:
		root = get_node_or_null("Root")
	if root == null:
		push_warning("HUD has no Root")
		return null
	var r = root.find_child(nm, true, false)
	if r == null:
		push_warning("HUD missing node: " + nm)
	return r

# ------------------------------------------------------------------ layout
func _relayout() -> void:
	var s: Vector2 = get_viewport().get_visible_rect().size
	var pad: float = max(18.0, s.y * 0.035)
	var stick_r: float = clamp(s.y * 0.13, 60.0, 130.0)

	stick_base.size = Vector2(stick_r * 2.0, stick_r * 2.0)
	stick_base.position = Vector2(pad, s.y - pad - stick_r * 2.0)
	stick_knob.size = Vector2(stick_r, stick_r)
	stick_knob.position = stick_base.position + Vector2(stick_r * 0.5, stick_r * 0.5)
	_stick_center = stick_base.position + Vector2(stick_r, stick_r)

	var bsz := Vector2(clamp(s.y * 0.17, 70.0, 150.0), clamp(s.y * 0.17, 70.0, 150.0))
	var fire_btn: Control = _find("FireBtn")
	var aim_btn: Control = _find("AimBtn")
	var jump_btn: Control = _find("JumpBtn")
	var crouch_btn: Control = _find("CrouchBtn")
	var reload_btn: Control = _find("ReloadBtn")
	fire_btn.size = bsz
	aim_btn.size = bsz
	jump_btn.size = bsz
	crouch_btn.size = bsz
	reload_btn.size = bsz

	fire_btn.position = Vector2(s.x - pad - bsz.x, s.y - pad - bsz.y)
	aim_btn.position = Vector2(s.x - pad - bsz.x * 2.0 - 12.0, s.y - pad - bsz.y)
	jump_btn.position = Vector2(s.x - pad - bsz.x, s.y - pad - bsz.y * 2.0 - 14.0)
	crouch_btn.position = Vector2(jump_btn.position.x - bsz.x - 12.0, jump_btn.position.y)
	reload_btn.position = Vector2(fire_btn.position.x - bsz.x - 12.0,
			fire_btn.position.y - bsz.y - 14.0)

func _connect_buttons() -> void:
	var fire_btn: BaseButton = _find("FireBtn")
	var aim_btn: BaseButton = _find("AimBtn")
	var jump_btn: BaseButton = _find("JumpBtn")
	var crouch_btn: BaseButton = _find("CrouchBtn")
	var reload_btn: BaseButton = _find("ReloadBtn")
	fire_btn.pressed.connect(_on_fire_pressed)
	fire_btn.button_up.connect(_on_fire_released)
	aim_btn.pressed.connect(_on_aim_pressed)
	aim_btn.button_up.connect(_on_aim_released)
	jump_btn.pressed.connect(_on_jump_pressed)
	jump_btn.button_up.connect(_on_jump_released)
	crouch_btn.pressed.connect(_on_crouch_pressed)
	crouch_btn.button_up.connect(_on_crouch_released)
	reload_btn.pressed.connect(_on_reload_pressed)
	var pieces: Array[int] = [GameTypes.PieceType.WALL, GameTypes.PieceType.FLOOR,
			GameTypes.PieceType.STAIRS, GameTypes.PieceType.CONE]
	if build_box != null:
		for i in build_box.get_child_count():
			var btn: BaseButton = build_box.get_child(i)
			btn.pressed.connect(_on_build_pressed.bind(pieces[i]))

func _on_fire_pressed() -> void:
	GameInput.set_fire(true)

func _on_fire_released() -> void:
	GameInput.set_fire(false)

func _on_aim_pressed() -> void:
	GameInput.set_aim(true)

func _on_aim_released() -> void:
	GameInput.set_aim(false)

func _on_jump_pressed() -> void:
	GameInput.set_jump(true)

func _on_jump_released() -> void:
	GameInput.set_jump(false)

func _on_crouch_pressed() -> void:
	GameInput.set_crouch(true)

func _on_crouch_released() -> void:
	GameInput.set_crouch(false)

func _on_reload_pressed() -> void:
	GameInput.request_reload()

func _on_build_pressed(piece: int) -> void:
	GameInput.request_build(piece)

# ------------------------------------------------------------------ touch
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var t: InputEventScreenTouch = e
		if t.pressed:
			if _in_stick_zone(t.position) and _stick_index == -1:
				_stick_index = t.index
				_update_stick(t.position)
			elif _look_index == -1:
				_look_index = t.index
				_last_look = t.position
		else:
			if t.index == _stick_index:
				_stick_index = -1
				_update_stick(_stick_center)
				GameInput.touch_move(Vector2.ZERO)
			elif t.index == _look_index:
				_look_index = -1
	elif e is InputEventScreenDrag:
		var d: InputEventScreenDrag = e
		if d.index == _stick_index:
			_update_stick(d.position)
		elif d.index == _look_index:
			var delta := d.position - _last_look
			_last_look = d.position
			GameInput.touch_look(delta * 0.0045)

func _in_stick_zone(p: Vector2) -> bool:
	var s := get_viewport().get_visible_rect().size
	return p.x < s.x * 0.45 and p.y > s.y * 0.35

func _update_stick(p: Vector2) -> void:
	if stick_knob == null:
		return
	var r: float = stick_base.size.x * 0.5
	var v: Vector2 = p - _stick_center
	if v.length() > r:
		v = v.normalized() * r
	stick_knob.position = _stick_center + v - stick_knob.size * 0.5
	var norm := v / r
	if norm.length() > 0.18:
		GameInput.touch_move(norm)
	else:
		GameInput.touch_move(Vector2.ZERO)

# ------------------------------------------------------------------ updates
func _process(_d: float) -> void:
	var p = Match.player
	if p == null or not is_instance_valid(p):
		return
	hp_label.text = "%d" % int(p.health)
	shield_label.text = "%d" % int(p.shield)
	mats_label.text = "W %d  B %d  M %d" % [p.mats[0], p.mats[1], p.mats[2]]
	var it: Dictionary = p.current_item()
	if it.is_empty():
		ammo_label.text = "--"
	elif it["weapon"] != null:
		var w: Dictionary = it["weapon"]
		if w["ammo"] == 0:
			ammo_label.text = "%s" % w["label"]
		else:
			ammo_label.text = "%s   %d / %d" % [w["label"], it["mag"], p.ammo.get(w["ammo"], 0)]
	else:
		ammo_label.text = "%s x%d" % [it["consumable"]["label"], it["mag"]]

func _rebuild_slots() -> void:
	if slots_box == null:
		return
	for c in slots_box.get_children():
		c.queue_free()
	var p = Match.player
	for i in 5:
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, 44)
		var txt := str(i + 1)
		if p != null and is_instance_valid(p) and p.items[i] != null:
			var it: Dictionary = p.items[i]
			txt = GameTypes.item_label(it).substr(0, 10)
		b.text = txt
		b.pressed.connect(func(): GameInput.request_slot(i))
		slots_box.add_child(b)

func _on_feed(text: String) -> void:
	var l := Label.new()
	l.text = text
	feed_box.add_child(l)
	if feed_box.get_child_count() > 5:
		feed_box.get_child(0).queue_free()
	var t := get_tree().create_timer(7.0)
	t.timeout.connect(l.queue_free)

func _on_alive(n: int) -> void:
	alive_label.text = "%d ALIVE" % n

func _on_phase(p: int) -> void:
	if p == Match.Phase.OVER:
		var alive_now: bool = Match.player != null and is_instance_valid(Match.player) \
				and Match.player.alive
		center_msg.text = "VICTORY ROYALE" if alive_now else "ELIMINATED"
		var t := get_tree().create_timer(4.0)
		t.timeout.connect(func(): center_msg.text = "")
