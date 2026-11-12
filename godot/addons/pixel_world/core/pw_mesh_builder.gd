@tool
extends RefCounted
## 网格构建器：按材质键分 surface，UV 以「米」为单位（shader 再乘像素密度），
## 保证所有程序化模型的像素颗粒大小一致。

const Mats := preload("res://addons/pixel_world/core/pw_materials.gd")
const SNAP := 1.0 / 16.0

var _surfaces := {}


static func snap(v: float) -> float:
	return roundf(v / SNAP) * SNAP


func _st(mat: String) -> SurfaceTool:
	if not _surfaces.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[mat] = st
	return _surfaces[mat]


## 单个三角形；自动调整绕序，使 n 方向为正面（Godot 正面为顺时针）。
func tri(mat: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
	var st := _st(mat)
	for i in 3:
		st.set_normal(n)
		st.set_uv([ua, ub, uc][i])
		st.add_vertex([a, b, c][i])


## 平面多边形（凸，按顺序给点）。outward 只需大致指向外侧。UV 按米自动投影。
func face(mat: String, pts: Array, outward: Vector3) -> void:
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	if n.dot(outward) < 0.0:
		n = -n
	var u_axis := n.cross(Vector3.UP)
	if u_axis.length_squared() < 0.0001:
		u_axis = Vector3.RIGHT
	u_axis = u_axis.normalized()
	var v_axis := n.cross(u_axis).normalized()
	var uvs: Array[Vector2] = []
	for p: Vector3 in pts:
		uvs.append(Vector2(p.dot(u_axis), p.dot(v_axis)))
	for i in range(1, pts.size() - 1):
		tri(mat, pts[0], pts[i], pts[i + 1], n, uvs[0], uvs[i], uvs[i + 1])


## 四边形，UV 铺满 0..1（窗户、门这类整张贴图）。点顺序：左上、右上、右下、左下（从外侧看）。
func quad01(mat: String, tl: Vector3, tr: Vector3, br: Vector3, bl: Vector3, outward: Vector3) -> void:
	var n: Vector3 = (tr - tl).cross(bl - tl).normalized()
	if n.dot(outward) < 0.0:
		n = -n
	tri(mat, tl, tr, br, n, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	tri(mat, tl, br, bl, n, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))


func box(mat: String, mn: Vector3, mx: Vector3, top := true, bottom := false, sides := true) -> void:
	if sides:
		face(mat, [Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mn.y, mn.z)], Vector3.RIGHT)
		face(mat, [Vector3(mn.x, mx.y, mx.z), Vector3(mn.x, mx.y, mn.z), Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mn.y, mx.z)], Vector3.LEFT)
		face(mat, [Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z)], Vector3.BACK)
		face(mat, [Vector3(mx.x, mx.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z)], Vector3.FORWARD)
	if top:
		face(mat, [Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z)], Vector3.UP)
	if bottom:
		face(mat, [Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z)], Vector3.DOWN)


## 方形棱台（松树层、屋顶小尖等）。r0 底半宽，r1 顶半宽。
func frustum(mat: String, center: Vector3, y0: float, y1: float, r0: float, r1: float, bottom := true) -> void:
	var b := [Vector3(-r0, y0, -r0), Vector3(r0, y0, -r0), Vector3(r0, y0, r0), Vector3(-r0, y0, r0)]
	var t := [Vector3(-r1, y1, -r1), Vector3(r1, y1, -r1), Vector3(r1, y1, r1), Vector3(-r1, y1, r1)]
	for i in 4:
		b[i] += center
		t[i] += center
	for i in 4:
		var j := (i + 1) % 4
		var mid: Vector3 = (b[i] + b[j]) * 0.5 - center
		mid.y = 0.0
		var pts := [t[i], t[j], b[j], b[i]]
		if r1 <= 0.001:
			pts = [t[i], b[j], b[i]]
		face(mat, pts, mid)
	if r1 > 0.001:
		face(mat, t, Vector3.UP)
	if bottom:
		face(mat, b, Vector3.DOWN)


## 正 N 边形棱台（树冠、灌木、石头）。center 只取 xz；y0/y1 为绝对高度；rot 为起始角（弧度）。
## r1 = 0 时为尖顶；r0 不要为 0。
func ngon_frustum(mat: String, center: Vector3, y0: float, y1: float, r0: float, r1: float,
		sides := 8, rot := 0.0, top := true, bottom := false) -> void:
	var c := Vector3(center.x, 0.0, center.z)
	var b: Array[Vector3] = []
	var t: Array[Vector3] = []
	for i in sides:
		var a := rot + TAU * i / sides
		var d := Vector3(cos(a), 0.0, sin(a))
		b.append(c + d * r0 + Vector3(0, y0, 0))
		t.append(c + d * r1 + Vector3(0, y1, 0))
	for i in sides:
		var j := (i + 1) % sides
		var mid: Vector3 = (b[i] + b[j]) * 0.5 - c
		mid.y = 0.0
		if r1 <= 0.001:
			face(mat, [t[i], b[j], b[i]], mid)
		else:
			face(mat, [t[i], t[j], b[j], b[i]], mid)
	if top and r1 > 0.001:
		face(mat, t, Vector3.UP)
	if bottom:
		face(mat, b, Vector3.DOWN)


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key: String in _surfaces:
		var st: SurfaceTool = _surfaces[key]
		mesh = st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Mats.get_mat(key))
	return mesh
