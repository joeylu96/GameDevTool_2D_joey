@tool
class_name PWBatcher
extends RefCounted
## 合批（性能）：静态模型和植被按「区块 × 材质」合并成少量大网格，几百个物体只需几十次绘制调用。
## - add_static：房屋、路灯、篱笆等，原样合并
## - add_plant：树、灌木、石头，每个实例的色调写进顶点色 RGB、摇摆相位写进 UV2.x，
##   合并后仍然每棵颜色不同、各摆各的
## 最后调用 flush(parent) 生成 MeshInstance3D。

var chunk := 40.0
var _static := {}  # "ix,iz,shadow" -> {Material: SurfaceTool}
var _plants := {}  # "ix,iz" -> {Material: {"v","n","uv","uv2","c": Array}}


func _key(o: Vector3) -> String:
	return "%d,%d" % [floori(o.x / chunk), floori(o.z / chunk)]


func add_static(mesh: ArrayMesh, xf: Transform3D, shadows := true) -> void:
	var key := _key(xf.origin) + ("," + str(shadows))
	if not _static.has(key):
		_static[key] = {}
	var groups: Dictionary = _static[key]
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if not groups.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[mat] = st
		(groups[mat] as SurfaceTool).append_from(mesh, s, xf)


## tint.a < 0.5 表示不调色
func add_plant(mesh: ArrayMesh, xf: Transform3D, tint := Color(1, 1, 1, 0)) -> void:
	var key := _key(xf.origin)
	if not _plants.has(key):
		_plants[key] = {}
	var groups: Dictionary = _plants[key]
	var col := Color(tint.r, tint.g, tint.b, 1.0) if tint.a > 0.5 else Color.WHITE
	var nxf := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
	var phase := fposmod(xf.origin.x * 0.37 + xf.origin.z * 0.29, TAU) + 0.01
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var mat := mesh.surface_get_material(s)
		if not groups.has(mat):
			groups[mat] = {"v": [], "n": [], "uv": [], "uv2": [], "c": []}
		var g: Dictionary = groups[mat]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var count := verts.size()
		g.v.append(xf * verts)
		g.n.append(nxf * (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array))
		g.uv.append(arr[Mesh.ARRAY_TEX_UV])
		var uv2 := PackedVector2Array()
		uv2.resize(count)
		uv2.fill(Vector2(phase, 0.0))
		g.uv2.append(uv2)
		var cols := PackedColorArray()
		cols.resize(count)
		cols.fill(col)
		g.c.append(cols)


func flush(parent: Node3D, name_prefix := "Batch") -> void:
	for key: String in _static:
		var groups: Dictionary = _static[key]
		var mesh := ArrayMesh.new()
		for mat: Material in groups:
			mesh = (groups[mat] as SurfaceTool).commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		var mi := MeshInstance3D.new()
		mi.name = "%s_Static_%s" % [name_prefix, key.replace(",", "_")]
		mi.mesh = mesh
		if key.ends_with("false"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	for key: String in _plants:
		var groups: Dictionary = _plants[key]
		var mesh := ArrayMesh.new()
		for mat: Material in groups:
			var g: Dictionary = groups[mat]
			var v := PackedVector3Array()
			var n := PackedVector3Array()
			var uv := PackedVector2Array()
			var uv2 := PackedVector2Array()
			var c := PackedColorArray()
			for i in g.v.size():
				v.append_array(g.v[i])
				n.append_array(g.n[i])
				uv.append_array(g.uv[i])
				uv2.append_array(g.uv2[i])
				c.append_array(g.c[i])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = v
			arrays[Mesh.ARRAY_NORMAL] = n
			arrays[Mesh.ARRAY_TEX_UV] = uv
			arrays[Mesh.ARRAY_TEX_UV2] = uv2
			arrays[Mesh.ARRAY_COLOR] = c
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		var mi := MeshInstance3D.new()
		mi.name = "%s_Plants_%s" % [name_prefix, key.replace(",", "_")]
		mi.mesh = mesh
		parent.add_child(mi)
	_static.clear()
	_plants.clear()
