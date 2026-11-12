extends Node3D
## Humanoid character built from the original Mixamo character textures
## (Assets/ThirdParty/Mixamo/Characters/*.fbm). Includes a procedural walk
## cycle so bots and the player read as real soldiers, not capsules.

const TEX := "res://assets/models/%s.fbx.fbm/%s"

# modular skin (Ty): separate texture per body part
const MODULAR := {
	"head": "Boy_Head_diffuse.png",
	"hair": "Boy_Hair_diffuse.png",
	"torso": "Boy_UpperBody_diffuse.png",
	"legs": "Boy_LowerBody_diffuse.png",
	"hands": "Boy_Hands_diffuse.png",
	"shoes": "Boy_Shoes_diffuse.png",
}
const MODULAR_DIR := "ThirdParty_Mixamo_Characters_Ty"

# whole-body skins
const SKINS := [
	["ThirdParty_Mixamo_Characters_Amy", "Ch46_1001_Diffuse.png"],
	["ThirdParty_Mixamo_Characters_Doozy", "Ch19_1001_Diffuse.png"],
	["ThirdParty_Mixamo_Characters_Jackie", "Ch29_1001_Diffuse.png"],
	["ThirdParty_Mixamo_Characters_Michelle", "Ch03_1001_Diffuse.png"],
	["ThirdParty_Mixamo_Characters_Timmy", "Ch09_1001_Diffuse.png"],
	["ThirdParty_Mixamo_Characters_Ortiz", "Ch24_1001_Diffuse.png"],
	["ThirdParty_Mixamo_Characters_Vanguard", "vanguard_diffuse1.png"],
	["ThirdParty_Mixamo_Characters_SportyGranny", "FitnessGrandma_diffuse.jpg"],
	["ThirdParty_Mixamo_Characters_Claire", "Girl01_diffuse.jpg"],
	["ThirdParty_Mixamo_Characters_BigVegas", "FatElvis_diffuse.jpg"],
	["ThirdParty_Mixamo_Characters_Swat", "Soldier_Body_diffuse.png"],
]

var pelvis: Node3D
var spine: Node3D
var head_node: Node3D
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

func build(skin_index: int, tint_col: Color) -> void:
	tint = tint_col
	var use_modular := skin_index < 0
	var torso_tex := ""
	var legs_tex := ""
	var head_tex := ""
	var hands_tex := ""
	var shoes_tex := ""
	if use_modular:
		torso_tex = TEX % [MODULAR_DIR, MODULAR["torso"]]
		legs_tex = TEX % [MODULAR_DIR, MODULAR["legs"]]
		head_tex = TEX % [MODULAR_DIR, MODULAR["head"]]
		hands_tex = TEX % [MODULAR_DIR, MODULAR["hands"]]
		shoes_tex = TEX % [MODULAR_DIR, MODULAR["shoes"]]
	else:
		var s: Array = SKINS[skin_index % SKINS.size()]
		torso_tex = TEX % [s[0], s[1]]
		legs_tex = torso_tex
		head_tex = torso_tex
		hands_tex = torso_tex
		shoes_tex = torso_tex

	# ---- skeleton -------------------------------------------------------
	pelvis = _pivot("Pelvis", Vector3(0, 0.92, 0))
	add_child(pelvis)
	spine = _pivot("Spine", Vector3.ZERO)
	pelvis.add_child(spine)
	head_node = _pivot("Head", Vector3(0, 0.78, 0))
	spine.add_child(head_node)

	# torso
	var torso_m := _capsule(0.62, 0.20, Vector3(0, 0.29, 0))
	torso_m.mesh.surface_set_material(0, _skin_mat(torso_tex))
	spine.add_child(torso_m)

	# head + hair
	var head_m := _sphere(0.125, Vector3(0, 0.06, 0))
	head_m.mesh.surface_set_material(0, _skin_mat(head_tex))
	head_node.add_child(head_m)
	if use_modular:
		var hair_m := _sphere(0.135, Vector3(0, 0.09, -0.01))
		hair_m.scale = Vector3(1.0, 0.85, 1.0)
		hair_m.mesh.surface_set_material(0,
				_skin_mat(TEX % [MODULAR_DIR, MODULAR["hair"]]))
		head_node.add_child(hair_m)

	# arms
	shoulder_l = _pivot("ShoulderL", Vector3(0.20, 0.52, 0))
	shoulder_r = _pivot("ShoulderR", Vector3(-0.20, 0.52, 0))
	spine.add_child(shoulder_l)
	spine.add_child(shoulder_r)
	for side in [shoulder_l, shoulder_r]:
		var upper := _capsule(0.32, 0.062, Vector3(0, -0.16, 0))
		upper.mesh.surface_set_material(0, _skin_mat(torso_tex))
		side.add_child(upper)
	for e in [[shoulder_l, elbow_l, "ElbowL"], [shoulder_r, elbow_r, "ElbowR"]]:
		var el := _pivot(e[2], Vector3(0, -0.32, 0))
		e[0].add_child(el)
		var fore := _capsule(0.30, 0.055, Vector3(0, -0.15, 0))
		fore.mesh.surface_set_material(0, _skin_mat(hands_tex))
		el.add_child(fore)
		if e[1] == elbow_l:
			elbow_l = el
		else:
			elbow_r = el

	# legs
	hip_l = _pivot("HipL", Vector3(0.11, 0, 0))
	hip_r = _pivot("HipR", Vector3(-0.11, 0, 0))
	pelvis.add_child(hip_l)
	pelvis.add_child(hip_r)
	for h in [hip_l, hip_r]:
		var thigh := _capsule(0.46, 0.082, Vector3(0, -0.23, 0))
		thigh.mesh.surface_set_material(0, _skin_mat(legs_tex))
		h.add_child(thigh)
	knee_l = _pivot("KneeL", Vector3(0, -0.46, 0))
	knee_r = _pivot("KneeR", Vector3(0, -0.46, 0))
	hip_l.add_child(knee_l)
	hip_r.add_child(knee_r)
	for k in [knee_l, knee_r]:
		var shin := _capsule(0.42, 0.068, Vector3(0, -0.21, 0))
		shin.mesh.surface_set_material(0, _skin_mat(legs_tex))
		k.add_child(shin)
		var shoe := _box(Vector3(0.13, 0.09, 0.26), Vector3(0, -0.44, 0.05))
		shoe.mesh.surface_set_material(0, _skin_mat(shoes_tex))
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
	m.normal_enabled = false
	return m

# ---------------------------------------------------------------- animation
func animate(speed: float, d: float, aiming: bool) -> void:
	if pelvis == null:
		return
	var moving := speed > 0.4
	if moving:
		phase += d * clamp(speed * 1.15, 1.5, 12.0)
	else:
		phase = lerp(phase, 0.0, d * 6.0)

	var sw := sin(phase)
	var sw2 := cos(phase)
	var amp := clamp(speed / 8.0, 0.0, 1.0) * 0.85

	hip_l.rotation.x = sw * amp
	hip_r.rotation.x = -sw * amp
	knee_l.rotation.x = max(0.0, -sw) * amp * 1.25
	knee_r.rotation.x = max(0.0, sw) * amp * 1.25

	if aiming:
		# both arms forward when aiming
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
