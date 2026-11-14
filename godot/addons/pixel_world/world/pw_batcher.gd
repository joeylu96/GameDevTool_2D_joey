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
static var _arrays_cache := {}  # "网格 id:面" -> 展开过的顶点数组（同一个模型种很多棵，只展开一次）


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


## tint.a < 0.5 表示不调色；shadows = false 时不投影（草）
func add_plant(mesh: ArrayMesh, xf: Transform3D, tint := Color(1, 1, 1, 0), shadows := true) -> void:
	var key := _key(xf.origin) + ("" if shadows else ",noshadow")
	if not _plants.has(key):
		_plants[key] = {}
	var groups: Dictionary = _plants[key]
	var col := Color(tint.r, tint.g, tint.b, 1.0) if tint.a > 0.5 else Color.WHITE
	var nxf := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
	var phase := fposmod(xf.origin.x * 0.37 + xf.origin.z * 0.29, TAU) + 0.01
	for s in mesh.get_surface_count():
		var ck := "%d:%d" % [mesh.get_instance_id(), s]
		if not _arrays_cache.has(ck):
			_arrays_cache[ck] = _deindexed(mesh.surface_get_arrays(s))
		var arr: Array = _arrays_cache[ck]
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
		# 模型自带顶点色（例如草叶根部深、尖端亮）就乘上色调；没有就直接用色调
		var cols := PackedColorArray()
		var src: Variant = arr[Mesh.ARRAY_COLOR]
		if src is PackedColorArray and (src as PackedColorArray).size() == count:
			cols = (src as PackedColorArray).duplicate()
			for ci in count:
				cols[ci] = Color(cols[ci].r * col.r, cols[ci].g * col.g, cols[ci].b * col.b, cols[ci].a)
		else:
			cols.resize(count)
			cols.fill(col)
		g.c.append(cols)


## 带索引的网格（Blender 导入的 glb 都是）展开成逐三角形的顶点：植被合批直接拼顶点数组，
## 不展开的话顶点会被按顺序当成三角形，模型就碎成满屏乱飞的长三角
static func _deindexed(arr: Array) -> Array:
	var idx: Variant = arr[Mesh.ARRAY_INDEX]
	if not (idx is PackedInt32Array) or (idx as PackedInt32Array).is_empty():
		return arr
	var out := arr.duplicate()
	var ids: PackedInt32Array = idx
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR]:
		var src: Variant = arr[k]
		if src == null or (src is Array and (src as Array).is_empty()):
			continue
		if src is PackedVector3Array:
			var d := PackedVector3Array()
			d.resize(ids.size())
			for i in ids.size():
				d[i] = src[ids[i]]
			out[k] = d
		elif src is PackedVector2Array:
			var d2 := PackedVector2Array()
			d2.resize(ids.size())
			for i in ids.size():
				d2[i] = src[ids[i]]
			out[k] = d2
		elif src is PackedColorArray:
			var dc := PackedColorArray()
			dc.resize(ids.size())
			for i in ids.size():
				dc[i] = src[ids[i]]
			out[k] = dc
	out[Mesh.ARRAY_INDEX] = null
	return out


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
		if key.ends_with("noshadow"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	_static.clear()
	_plants.clear()
