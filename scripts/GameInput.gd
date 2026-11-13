extends Node
## Single input source shared by keyboard/mouse (desktop) and touch (mobile).

var move := Vector2.ZERO          # x = strafe, y = forward
var look := Vector2.ZERO          # accumulated look delta this frame
var look_dir := Vector2.ZERO      # absolute look (used by touch look-pad)
var firing := false
var aiming := false
var jumping := false
var crouching := false
var sprinting := false
var reloading := false
var interact := false
var slot_request := -1            # 0..4 when the player taps an inventory slot
var build_request := -1           # PieceType when a build button is tapped
var fire_pressed := false         # single-frame edge

var sensitivity := 0.0022
var touch_mode := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch_mode = OS.has_feature("mobile") or OS.has_feature("web_android")

func _process(_d: float) -> void:
	look = Vector2.ZERO
	fire_pressed = false

	if not touch_mode:
		read_keyboard()

func read_keyboard() -> void:
	var m := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): m.y -= 1.0
	if Input.is_key_pressed(KEY_S): m.y += 1.0
	if Input.is_key_pressed(KEY_A): m.x -= 1.0
	if Input.is_key_pressed(KEY_D): m.x += 1.0
	move = m.normalized() if m.length() > 0.0 else Vector2.ZERO

	var jm := Input.get_last_mouse_velocity()
	look = Vector2(-jm.x, -jm.y) * sensitivity

	firing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	fire_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	aiming = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	jumping = Input.is_key_pressed(KEY_SPACE)
	crouching = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C)
	sprinting = Input.is_key_pressed(KEY_SHIFT)
	reloading = Input.is_key_pressed(KEY_R)
	interact = Input.is_key_pressed(KEY_E)

	slot_request = -1
	for i in 5:
		if Input.is_key_pressed(KEY_1 + i):
			slot_request = i

## called by the touch layer
func touch_move(v: Vector2) -> void:
	move = v
	touch_mode = true

func touch_look(delta: Vector2) -> void:
	look += delta
	touch_mode = true

func set_fire(pressed: bool) -> void:
	if pressed and not firing:
		fire_pressed = true
	firing = pressed
	touch_mode = true

func set_aim(pressed: bool) -> void:
	aiming = pressed

func set_jump(pressed: bool) -> void:
	jumping = pressed

func set_crouch(pressed: bool) -> void:
	crouching = pressed

func set_sprint(pressed: bool) -> void:
	sprinting = pressed

func request_reload() -> void:
	reloading = true

func request_slot(i: int) -> void:
	slot_request = i

func request_build(piece: int) -> void:
	build_request = piece
