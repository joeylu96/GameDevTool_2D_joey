@tool
extends RefCounted
## 网格构建器：按材质键分 surface，UV 以「米」为单位（shader 再乘像素密度），
## 保证所有程序化模型的像素颗粒大小一致。

const Mats := preload("res://addons/pixel_world/core/pw_materials.gd")
const SNAP := 1.0 / 32.0

var _surfaces := {}
## 之后添加的顶点都带这个顶点色。shader 把 RGB 当色调（白色 = 不变），A 当「每个部件的随机数」（例如每扇窗夜里亮不亮）。
var color := Color.WHITE


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
		st.set_color(color)
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
## wrap_uv = true：侧面贴图沿圆周展开（u = 弧长，v = 高度），用于树干等细圆柱——
## 否则每个窄面都取贴图的同一条竖带，所有面图案一样，横向花纹会连成整齐的圆环。
func ngon_frustum(mat: String, center: Vector3, y0: float, y1: float, r0: float, r1: float,
		sides := 8, rot := 0.0, top := true, bottom := false, wrap_uv := false) -> void:
	var c := Vector3(center.x, 0.0, center.z)
	if wrap_uv:
		tube(mat, c + Vector3(0, y0, 0), c + Vector3(0, y1, 0), r0, r1, sides, rot, top, bottom)
		return
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


## 任意方向的圆台（树干、树枝）：从 a 到 b，a 端半径 r0，b 端半径 r1，截面正 sides 边形。
## 侧面 UV 沿圆周展开（米为单位）：u = 弧长 + 随起点变化的偏移，v = 沿轴距离。
func tube(mat: String, a: Vector3, b: Vector3, r0: float, r1: float, sides := 8, rot := 0.0,
		cap_b := true, cap_a := false) -> void:
	var axis := (b - a).normalized()
	var length := a.distance_to(b)
	var ref := Vector3.FORWARD if absf(axis.y) > 0.95 else Vector3.UP
	var u := ref.cross(axis).normalized()
	var v := axis.cross(u).normalized()
	if absf(axis.y) > 0.95:  # 竖直：让 rot 与 ngon_frustum 的角度定义一致（从 +X 开始）
		u = Vector3.RIGHT
		v = Vector3.BACK if axis.y > 0.0 else Vector3.FORWARD
	var ra: Array[Vector3] = []
	var rb: Array[Vector3] = []
	for i in sides:
		var ang := rot + TAU * i / sides
		var d := u * cos(ang) + v * sin(ang)
		ra.append(a + d * r0)
		rb.append(b + d * r1)
	var circ := TAU * maxf(r0, r1)
	var u0 := fposmod(a.x * 1.7 + a.z * 2.3 + a.y * 0.9, 4.0)  # 不同枝干从贴图不同位置开始
	var v0 := a.y + fposmod(a.x * 0.7 - a.z * 1.1, 2.0)
	for i in sides:
		var j := (i + 1) % sides
		var out := (ra[i] + ra[j] + rb[i] + rb[j]) * 0.25 - (a + b) * 0.5
		out -= axis * out.dot(axis)
		var ui := u0 + circ * i / sides
		var uj := u0 + circ * (i + 1) / sides
		var n := out.normalized()
		tri(mat, ra[i], ra[j], rb[j], n, Vector2(ui, v0), Vector2(uj, v0), Vector2(uj, v0 + length))
		if r1 > 0.001:
			tri(mat, ra[i], rb[j], rb[i], n, Vector2(ui, v0), Vector2(uj, v0 + length), Vector2(ui, v0 + length))
	if cap_b and r1 > 0.001:
		face(mat, rb, axis)
	if cap_a:
		face(mat, ra, -axis)


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key: String in _surfaces:
		var st: SurfaceTool = _surfaces[key]
		mesh = st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Mats.get_mat(key))
	return mesh
