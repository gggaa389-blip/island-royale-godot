extends Node3D
## Builds the island terrain mesh + collision from the extracted Unity heightmap.
## The height data is a raw float32 grid (res x res) produced by tools/u2g_terrain.py.

@export var res := 257
@export var size_x := 600.0
@export var size_z := 600.0

var heights: PackedFloat32Array
var hmin := 0.0
var hmax := 1.0

func _ready() -> void:
	build()

func load_heightmap() -> bool:
	var path := "res://assets/terrain/height_%d.f32.bin" % res
	if not FileAccess.file_exists(path):
		push_warning("heightmap missing: %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var raw := f.get_buffer(f.get_length())
	f.close()
	heights = raw.to_float32_array()
	if heights.size() < res * res:
		push_warning("heightmap too small")
		return false
	hmin = heights[0]; hmax = heights[0]
	for h in heights:
		if h < hmin: hmin = h
		if h > hmax: hmax = h
	return true

func height_at(wx: float, wz: float) -> float:
	"""world XZ -> terrain height (metres)"""
	if heights.is_empty():
		return 0.0
	var u := (wx / size_x + 0.5) * float(res - 1)
	var v := (wz / size_z + 0.5) * float(res - 1)
	u = clamp(u, 0.0, float(res - 1))
	v = clamp(v, 0.0, float(res - 1))
	var i0 := int(u); var j0 := int(v)
	var i1 := mini(i0 + 1, res - 1); var j1 := mini(j0 + 1, res - 1)
	var fx := u - i0; var fz := v - j0
	var h00 := heights[j0 * res + i0]
	var h10 := heights[j0 * res + i1]
	var h01 := heights[j1 * res + i0]
	var h11 := heights[j1 * res + i1]
	return lerp(lerp(h00, h10, fx), lerp(h01, h11, fx), fz)

func build() -> void:
	if not load_heightmap():
		# flat fallback island so the game still runs
		heights = PackedFloat32Array()
		heights.resize(res * res)
		for j in res:
			for i in res:
				var dx := float(i) / float(res - 1) - 0.5
				var dz := float(j) / float(res - 1) - 0.5
				heights[j * res + i] = 6.0 - 10.0 * (dx * dx + dz * dz)
	build_mesh()
	build_collision()

func build_mesh() -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(res * res); uvs.resize(res * res); norms.resize(res * res)
	idx.resize((res - 1) * (res - 1) * 6)

	var vi := 0
	for j in res:
		for i in res:
			var x := (float(i) / float(res - 1) - 0.5) * size_x
			var z := (float(j) / float(res - 1) - 0.5) * size_z
			verts[vi] = Vector3(x, heights[j * res + i], z)
			uvs[vi] = Vector2(float(i) / float(res - 1), float(j) / float(res - 1))
			vi += 1

	var ii := 0
	for j in res - 1:
		for i in res - 1:
			var a := j * res + i
			var b := a + 1
			var c := a + res
			var d := c + 1
			idx[ii] = a; idx[ii + 1] = b; idx[ii + 2] = c
			idx[ii + 3] = b; idx[ii + 4] = d; idx[ii + 5] = c
			ii += 6

	# smooth normals from the grid
	norms.fill(Vector3.UP)
	for j in res:
		for i in res:
			var hl := heights[j * res + maxi(i - 1, 0)]
			var hr := heights[j * res + mini(i + 1, res - 1)]
			var hd := heights[mini(j + 1, res - 1) * res + i]
			var hu := heights[maxi(j - 1, 0) * res + i]
			var sx := float(size_x) / float(res - 1)
			var sz := float(size_z) / float(res - 1)
			norms[j * res + i] = Vector3(hl - hr, 2.0 * sx, hu - hd).normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	mi.material_override = make_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func make_material() -> Material:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec3 col_a : source_color = vec3(0.30, 0.46, 0.20);
uniform vec3 col_b : source_color = vec3(0.72, 0.66, 0.44);
uniform vec3 col_c : source_color = vec3(0.42, 0.40, 0.38);
uniform vec3 col_d : source_color = vec3(0.22, 0.34, 0.18);
uniform float uv_scale = 90.0;

void fragment() {
	vec4 s = texture(splat, UV);
	float total = s.r + s.g + s.b + s.a;
	vec3 base = col_a;
	if (total > 0.02) {
		base = (col_a * s.r + col_b * s.g + col_c * s.b + col_d * s.a) / total;
	}
	// cheap large-scale breakup so big triangles do not look flat
	float n = fract(sin(dot(floor(UV * uv_scale), vec2(12.9898, 78.233))) * 43758.5453);
	base *= 0.92 + 0.16 * n;
	ALBEDO = base;
	ROUGHNESS = 0.95;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	var p := "res://assets/terrain/splat_0.png"
	if ResourceLoader.exists(p):
		m.set_shader_parameter("splat", load(p))
	return m

func build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := HeightMapShape3D.new()
	shape.map_width = res
	shape.map_depth = res
	# HeightMapShape3D wants a square-ish map: keep cell size uniform
	shape.map_data = heights
	var c := CollisionShape3D.new()
	c.shape = shape
	var sx := size_x / float(res - 1)
	var sz := size_z / float(res - 1)
	body.scale = Vector3(sx, 1.0, sz)
	body.position = Vector3(-size_x * 0.5, 0.0, -size_z * 0.5)
	body.add_child(c)
	add_child(body)
	print("[terrain] built: %dx%d, %.0fx%.0f m, height %.1f-%.1f" % [res, res, size_x, size_z, hmin, hmax])
