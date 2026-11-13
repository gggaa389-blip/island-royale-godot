extends Node3D
## Character visuals.
## Primary path: real Mixamo FBX (Assets/ThirdParty/Mixamo/Characters) driven by the
## original animation clips (Assets/ThirdParty/Mixamo/Animations). All clips share the
## 65-bone mixamorig skeleton, so they retarget onto any character directly.
## Fallback: a procedural humanoid using the original character textures.

const CHAR_MODELS := [
	"res://assets/models/ThirdParty_Mixamo_Characters_YBot.fbx",
	"res://assets/models/ThirdParty_Mixamo_Characters_Swat.fbx",
	"res://assets/models/ThirdParty_Mixamo_Characters_BigVegas.fbx",
]

const CLIPS := {
	"idle": "R_Idle",
	"run": "Run",
	"jump": "R_JumpLoop",
	"fall": "U_Fall",
	"death": "N_Death1",
	"victory": "E_Victory",
	"reload": "R_Reload",
	"throw": "U_Throw",
	"glide": "S_Glide",
}

static var _anim_cache: Dictionary = {}

var model: Node3D
var ap: AnimationPlayer
var current_anim: String = ""

# procedural fallback state
var pelvis: Node3D
var spine: Node3D
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var phase := 0.0
var tint := Color(1, 1, 1)

# ------------------------------------------------------------------ build
func build(skin_index: int, tint_col: Color) -> void:
	tint = tint_col
	var path: String = CHAR_MODELS[abs(skin_index) % CHAR_MODELS.size()]
	if ResourceLoader.exists(path):
		var ps = load(path)
		if ps != null:
			model = ps.instantiate()
			model.name = "Model"
			add_child(model)
			# Mixamo FBX are authored in centimetres: normalise to a 1.8 m character
			var h: float = _model_height(model)
			if h > 0.01:
				model.scale = Vector3.ONE * (1.80 / h)
			ap = _find_anim_player(model)
			if ap != null:
				# Godot 4 stores animations inside AnimationLibrary objects
				var lib: AnimationLibrary = null
				var libs: Array = ap.get_animation_library_list()
				if libs.has(""):
					lib = ap.get_animation_library("")
				else:
					lib = AnimationLibrary.new()
					ap.add_animation_library("", lib)
				for key in CLIPS:
					var clip: Animation = anim_clip(CLIPS[key])
					if clip != null and not lib.has_animation(key):
						lib.add_animation(key, clip)
				if lib.has_animation("idle"):
					ap.play("idle")
					current_anim = "idle"
			return
	_build_procedural(skin_index)

static func anim_clip(clip_name: String) -> Animation:
	if _anim_cache.has(clip_name):
		return _anim_cache[clip_name]
	var path := "res://assets/models/ThirdParty_Mixamo_Animations_%s.fbx" % clip_name
	_anim_cache[clip_name] = null
	if not ResourceLoader.exists(path):
		return null
	var ps = load(path)
	if ps == null:
		return null
	var inst: Node = ps.instantiate()
	var player := _find_anim_player(inst)
	if player == null:
		inst.free()
		return null
	var names: Array = player.get_animation_list()
	var pick: String = ""
	for n in names:
		if str(n) != "mixamo_com":
			pick = str(n)
			break
	if pick == "" and names.size() > 0:
		pick = str(names[0])
	if pick == "":
		inst.free()
		return null
	var a: Animation = player.get_animation(pick).duplicate()
	a.loop_mode = Animation.LOOP_LINEAR if (clip_name != "death"
			and clip_name != "victory") else Animation.LOOP_NONE
	_anim_cache[clip_name] = a
	inst.free()
	return a

static func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

# ------------------------------------------------------------------ animate
func animate(speed: float, d: float, aiming: bool, on_floor: bool, alive: bool) -> void:
	if ap != null:
		var want := "idle"
		if not alive:
			want = "death"
		elif not on_floor:
			want = "jump" if speed < 2.0 else "fall"
		elif speed > 5.6:
			want = "run"
		elif speed > 0.4:
			want = "idle"
		if want != current_anim:
			ap.play(want, 0.18)
			current_anim = want
		ap.speed_scale = clamp(speed / 5.0, 0.85, 1.7) if want == "run" else 1.0
		return
	_animate_procedural(speed, d, aiming)

func play_once(clip: String) -> void:
	if ap != null and ap.has_animation(clip):
		ap.play(clip, 0.1)

# ------------------------------------------------------------------ procedural fallback
func _animate_procedural(speed: float, d: float, aiming: bool) -> void:
	if pelvis == null:
		return
	if speed > 0.4:
		phase += d * clamp(speed * 1.15, 1.5, 12.0)
	else:
		phase = lerp(phase, 0.0, d * 6.0)
	var sw := sin(phase)
	var sw2 := cos(phase)
	var amp: float = clamp(speed / 8.0, 0.0, 1.0) * 0.85
	hip_l.rotation.x = sw * amp
	hip_r.rotation.x = -sw * amp
	knee_l.rotation.x = max(0.0, -sw) * amp * 1.25
	knee_r.rotation.x = max(0.0, sw) * amp * 1.25
	if aiming:
		shoulder_l.rotation.x = lerp(shoulder_l.rotation.x, -1.35, d * 10.0)
		shoulder_r.rotation.x = lerp(shoulder_r.rotation.x, -1.35, d * 10.0)
		elbow_l.rotation.x = lerp(elbow_l.rotation.x, -0.25, d * 10.0)
		elbow_r.rotation.x = lerp(elbow_r.rotation.x, -0.25, d * 10.0)
	else:
		shoulder_l.rotation.x = lerp(shoulder_l.rotation.x, -sw * amp * 0.75, d * 12.0)
		shoulder_r.rotation.x = lerp(shoulder_r.rotation.x, sw * amp * 0.75, d * 12.0)
		elbow_l.rotation.x = lerp(elbow_l.rotation.x, -0.35 - max(0.0, sw) * 0.4, d * 12.0)
		elbow_r.rotation.x = lerp(elbow_r.rotation.x, -0.35 - max(0.0, -sw) * 0.4, d * 12.0)
	pelvis.position.y = 0.92 + abs(sw2) * amp * 0.045
	spine.rotation.x = -0.06 + sw * amp * 0.05

const MODULAR_DIR := "ThirdParty_Mixamo_Characters_Ty"
const MODULAR := {
	"head": "Boy_Head_diffuse.png",
	"hair": "Boy_Hair_diffuse.png",
	"torso": "Boy_UpperBody_diffuse.png",
	"legs": "Boy_LowerBody_diffuse.png",
	"hands": "Boy_Hands_diffuse.png",
	"shoes": "Boy_Shoes_diffuse.png",
}
const SKINS := [
	["ThirdParty_Mixamo_Characters_Amy", "Ch46_1001_Diffuse.png"],
	["ThirdParty_Mixamo_Characters_Doozy", "Ch19_1001_Diffuse.png"],
	["ThirdParty_Mixamo_Characters_Michelle", "Ch03_1001_Diffuse.png"],
	["ThirdParty_Mixamo_Characters_Vanguard", "vanguard_diffuse1.png"],
	["ThirdParty_Mixamo_Characters_SportyGranny", "FitnessGrandma_diffuse.jpg"],
	["ThirdParty_Mixamo_Characters_Claire", "Girl01_diffuse.jpg"],
	["ThirdParty_Mixamo_Characters_BigVegas", "FatElvis_diffuse.jpg"],
]

func _build_procedural(skin_index: int) -> void:
	var use_modular: bool = skin_index < 0
	var texs := {}
	if use_modular:
		for k in MODULAR:
			texs[k] = "res://assets/models/%s.fbx.fbm/%s" % [MODULAR_DIR, MODULAR[k]]
	else:
		var s: Array = SKINS[skin_index % SKINS.size()]
		for k in ["head", "hair", "torso", "legs", "hands", "shoes"]:
			texs[k] = "res://assets/models/%s.fbx.fbm/%s" % [s[0], s[1]]

	pelvis = _pivot("Pelvis", Vector3(0, 0.92, 0))
	add_child(pelvis)
	spine = _pivot("Spine", Vector3.ZERO)
	pelvis.add_child(spine)
	var torso_m := _capsule(0.62, 0.20, Vector3(0, 0.29, 0))
	torso_m.mesh.surface_set_material(0, _skin_mat(texs["torso"]))
	spine.add_child(torso_m)

	var head_n := _pivot("Head", Vector3(0, 0.78, 0))
	spine.add_child(head_n)
	var head_m := _sphere(0.125, Vector3(0, 0.06, 0))
	head_m.mesh.surface_set_material(0, _skin_mat(texs["head"]))
	head_n.add_child(head_m)
	if use_modular:
		var hair_m := _sphere(0.135, Vector3(0, 0.09, -0.01))
		hair_m.scale = Vector3(1.0, 0.85, 1.0)
		hair_m.mesh.surface_set_material(0, _skin_mat(texs["hair"]))
		head_n.add_child(hair_m)

	shoulder_l = _pivot("ShoulderL", Vector3(0.20, 0.52, 0))
	shoulder_r = _pivot("ShoulderR", Vector3(-0.20, 0.52, 0))
	spine.add_child(shoulder_l)
	spine.add_child(shoulder_r)
	for side in [shoulder_l, shoulder_r]:
		var upper := _capsule(0.32, 0.062, Vector3(0, -0.16, 0))
		upper.mesh.surface_set_material(0, _skin_mat(texs["torso"]))
		side.add_child(upper)
	elbow_l = _pivot("ElbowL", Vector3(0, -0.32, 0))
	elbow_r = _pivot("ElbowR", Vector3(0, -0.32, 0))
	shoulder_l.add_child(elbow_l)
	shoulder_r.add_child(elbow_r)
	for e in [elbow_l, elbow_r]:
		var fore := _capsule(0.30, 0.055, Vector3(0, -0.15, 0))
		fore.mesh.surface_set_material(0, _skin_mat(texs["hands"]))
		e.add_child(fore)

	hip_l = _pivot("HipL", Vector3(0.11, 0, 0))
	hip_r = _pivot("HipR", Vector3(-0.11, 0, 0))
	pelvis.add_child(hip_l)
	pelvis.add_child(hip_r)
	for h in [hip_l, hip_r]:
		var thigh := _capsule(0.46, 0.082, Vector3(0, -0.23, 0))
		thigh.mesh.surface_set_material(0, _skin_mat(texs["legs"]))
		h.add_child(thigh)
	knee_l = _pivot("KneeL", Vector3(0, -0.46, 0))
	knee_r = _pivot("KneeR", Vector3(0, -0.46, 0))
	hip_l.add_child(knee_l)
	hip_r.add_child(knee_r)
	for k in [knee_l, knee_r]:
		var shin := _capsule(0.42, 0.068, Vector3(0, -0.21, 0))
		shin.mesh.surface_set_material(0, _skin_mat(texs["legs"]))
		k.add_child(shin)
		var shoe := _box(Vector3(0.13, 0.09, 0.26), Vector3(0, -0.44, 0.05))
		shoe.mesh.surface_set_material(0, _skin_mat(texs["shoes"]))
		k.add_child(shoe)

func _pivot(nm: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	return n

func _capsule(h: float, r: float, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 8
	cm.rings = 3
	m.mesh = cm
	m.position = pos
	return m

func _sphere(r: float, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	m.mesh = sm
	m.position = pos
	return m

func _box(sz: Vector3, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	m.mesh = bm
	m.position = pos
	return m

func _skin_mat(path: String) -> Material:
	var m := StandardMaterial3D.new()
	if path != "" and ResourceLoader.exists(path):
		m.albedo_texture = load(path)
	m.albedo_color = tint
	m.roughness = 0.85
	return m

func _model_height(n: Node) -> float:
	var biggest := 0.0
	for mi in _meshes(n):
		var a: AABB = mi.get_aabb()
		biggest = max(biggest, a.size.y * mi.scale.y)
	return biggest

func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and n.mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
