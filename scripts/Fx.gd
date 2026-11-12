extends Node
## Lightweight visual feedback (no particle systems: mobile friendly).

var _canvas: CanvasLayer
var _flash: ColorRect
var _marker: Label
var _marker_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = CanvasLayer.new()
	_canvas.layer = 90
	add_child(_canvas)

	_flash = ColorRect.new()
	_flash.color = Color(0.85, 0.1, 0.1, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_flash)

	_marker = Label.new()
	_marker.text = "✛"
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_marker.set_anchors_preset(Control.PRESET_CENTER)
	_marker.position = Vector2(-12, -12)
	_marker.add_theme_font_size_override("font_size", 28)
	_marker.modulate = Color(1, 1, 1, 0)
	_canvas.add_child(_marker)

func _process(d: float) -> void:
	if _flash.color.a > 0.0:
		_flash.color.a = max(0.0, _flash.color.a - d * 1.8)
	if _marker_t > 0.0:
		_marker_t -= d
		_marker.modulate.a = clamp(_marker_t * 4.0, 0.0, 1.0)
	else:
		_marker.modulate.a = 0.0

func damage_flash() -> void:
	_flash.color.a = 0.32

func hit_marker(head: bool) -> void:
	_marker_t = 0.22
	_marker.modulate = Color(1.0, 0.75, 0.3) if head else Color(1, 1, 1)
	_marker.add_theme_font_size_override("font_size", 36 if head else 26)

func impact(point: Vector3, normal: Vector3) -> void:
	# small short-lived decal quad
	var q := MeshInstance3D.new()
	var pm := QuadMesh.new()
	pm.size = Vector2(0.28, 0.28)
	q.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.14, 0.12)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material_override = m
	q.global_position = point + normal * 0.02
	if normal.length() > 0.001:
		q.look_at(point + normal, Vector3.UP)
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(q)
		var t := get_tree().create_timer(6.0)
		t.timeout.connect(q.queue_free)

func explosion(point: Vector3, radius: float) -> void:
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	s.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.55, 0.18, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s.material_override = m
	s.global_position = point
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(s)
		var tw := create_tween()
		tw.tween_property(s, "scale", Vector3.ONE * 1.6, 0.35)
		tw.tween_callback(s.queue_free)
