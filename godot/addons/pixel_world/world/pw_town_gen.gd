@tool
extends RefCounted
## 小镇生成（PWWorld theme = "town"）。
##
## 布局：南侧是湖，岸线自然起伏；陆地上一条贯穿东西的主街，两侧区域用 BSP 递归切分出支路（T 字路口），
## 每条路两侧依次排房屋（正门朝路、留前院和门前通道），沿路交错立路灯；一条土路通到湖边码头，
## 岸边一座灯塔；最后在空地上撒树、灌木和石头。
## 摆放顺序 = 优先级：道路 → 土路 / 码头 → 灯塔 → 房屋（含门前通道）→ 路灯 → 篱笆 → 长椅 / 货物 → 树 → 灌木 → 石头。
## 每一步都先 can_place，通过才 add，所以后放的东西不可能压到先放的东西（规则见 PWPlacement）。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")
const Mats := preload("res://addons/pixel_world/core/pw_materials.gd")
const House := preload("res://addons/pixel_world/assets/placeholder/pw_house_builder.gd")
const Trees := preload("res://addons/pixel_world/assets/placeholder/pw_tree_builder.gd")
const Props := preload("res://addons/pixel_world/assets/placeholder/pw_props_builder.gd")
const POOL_SHADER := preload("res://addons/pixel_world/shaders/light_pool.gdshader")
const P := preload("res://addons/pixel_world/world/pw_placement.gd")

const ROAD_W := 4.0
const CURB := 0.25
const CURB_H := 0.1
const MIN_BLOCK := 18.0
const LAKE_MARGIN := 24.0     # 湖向南延伸到地图外，看得到远处的水面
const WATER_Y := -0.45
const BED_SLOPE1 := 0.35
const BED_BEND1 := 3.0
const BED_SLOPE2 := 0.4
const BED_BEND2 := 9.0

var w: PWWorld
var rng: RandomNumberGenerator
var batch: PWBatcher
var pl: PWPlacement
var H := 40.0
var shore_base := 22.0
var _shore_waves: Array = []  # [振幅, 频率, 相位]
var roads: Array[Rect2] = []
var _lamp_spots: Array = []   # [Vector3 位置, 朝路方向 Vector2]
var _path_x := 0.0
var _path_top := 0.0
var _pier := Rect2()
var prm := {}               # 风格参数（PWStyles）；medieval = true 是中世纪小镇
var medieval := false
var plaza := Rect2()        # 中世纪小镇的中心广场（没有则为空）


func _init(world: PWWorld, r: RandomNumberGenerator, b: PWBatcher, params := {}) -> void:
	w = world
	rng = r
	batch = b
	prm = params
	medieval = prm.get("medieval", false)
	for sp: String in prm.get("specials", []):
		_specials.append(sp)
	if prm.has("lake"):
		w.with_lake = prm.lake
	pl = world.placement
	H = world.size * 0.5


func run() -> void:
	w.water_y = WATER_Y
	w.terraced = false
	shore_base = H - clampf(H * 0.45, 12.0, 22.0) if w.with_lake else H + 50.0
	for i in 3:
		_shore_waves.append([rng.randf_range(0.6, 1.8) / (i + 1), rng.randf_range(0.05, 0.12) * (i + 1), rng.randf() * TAU])
	_build_terrain()
	_build_roads()
	if medieval:
		_build_plaza()
	_build_road_surface()
	if medieval:
		_build_walls()
	var curb_gaps: Array[Rect2] = []
	if w.with_lake and prm.get("pier", true):
		curb_gaps.append(_build_path_and_pier())
		_build_lighthouse()
	if w.with_lake and prm.get("harbor", false):
		_build_harbor()
	if prm.get("curbs", true):
		_build_curbs(curb_gaps)
	_build_houses()
	if medieval:
		_build_plaza_props()
	_build_lamps()
	_build_benches()
	_build_blender_props()
	if prm.get("cars", 0.0) > 0.0:
		_build_cars()
	if prm.get("fields", 0) > 0:
		_build_fields()
	_build_trees()
	_build_bushes_and_rocks()
	_build_grass()
	if w.with_lake:
		_build_lake_life()
	var pier: bool = w.with_lake and prm.get("pier", true)
	var sp := Vector2(_path_x, _path_top + 3.0) if pier else roads[0].get_center()
	# 出生点必须能站人：沿土路（或主街）往前找第一个空地
	for k in 40:
		if w.can_stand(sp):
			break
		sp += Vector2(0, 0.5) if pier else Vector2(0.5, 0)
	w.spawn_point = Vector3(sp.x, w.ground_y(sp.x, sp.y), sp.y)
	for c in [P.HOUSE, P.LAMP, P.TREE, P.BUSH, P.ROCK, P.FENCE, P.BENCH, P.ROAD, P.WALL]:
		w.stats[String(c)] = pl.count(c)


# ---------------------------------------------------------------- 地形与湖

func shore(x: float) -> float:
	var z := shore_base
	for s: Array in _shore_waves:
		z += s[0] * sin(x * s[1] + s[2])
	return z


static func bed_y(d: float) -> float:
	if d <= 0.0:
		return 0.0
	if d < BED_BEND1:
		return -BED_SLOPE1 * d
	var y1 := -BED_SLOPE1 * BED_BEND1
	if d < BED_BEND2:
		return y1 - BED_SLOPE2 * (d - BED_BEND1)
	return y1 - BED_SLOPE2 * (BED_BEND2 - BED_BEND1) - 0.05 * minf(d - BED_BEND2, 6.0)


func _build_terrain() -> void:
	w.init_grid(H, LAKE_MARGIN if w.with_lake else 2.0)
	for j in w.grid_n + 1:
		for i in w.grid_n + 1:
			var p := w.vert_xz(i, j)
			w.set_h(i, j, bed_y(p.y - shore(p.x)))
	# 草地 + 岸边碎石带：按 0.5 米宽的竖条拼，岸线是平滑曲线
	var ground := MB.new()
	var gravel := MB.new()
	var x := -H
	var srng := RandomNumberGenerator.new()
	srng.seed = rng.randi()
	var prev_in := shore(x) - 0.9
	while x < H - 0.001:
		var nx := minf(x + 0.5, H)
		var s0 := minf(shore(x), H)
		var s1 := minf(shore(nx), H)
		var in1 := s1 - 0.9 + srng.randi_range(-6, 6) * MB.SNAP
		if not w.with_lake:
			in1 = s1
		ground.face("grass", [Vector3(x, 0, -H), Vector3(nx, 0, -H), Vector3(nx, 0, minf(in1, s1)), Vector3(x, 0, minf(prev_in, s0))], Vector3.UP)
		if w.with_lake:
			gravel.face("shore", [Vector3(x, 0.012, prev_in), Vector3(nx, 0.012, in1), Vector3(nx, 0.012, s1), Vector3(x, 0.012, s0)], Vector3.UP)
		prev_in = in1
		x = nx
	batch.add_static(ground.commit(), Transform3D.IDENTITY, false)
	if w.with_lake:
		batch.add_static(gravel.commit(), Transform3D.IDENTITY, false)
		_build_lake_bed()


func _build_lake_bed() -> void:
	# 整片湖底一个网格（顶点共享、法线平滑），用 terrain 材质按顶点权重混合沙 / 泥底：
	# 近岸是沙，往深处逐渐变成泥底，交界是不规则的弯曲边——不再是一格一格随机的方块
	var n := w.grid_n + 1
	var idx := {}  # Vector2i -> 顶点序号
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	var vid := func(i: int, j: int) -> int:
		var key := Vector2i(i, j)
		if idx.has(key):
			return idx[key]
		var xz := w.vert_xz(i, j)
		var h := w.get_h(i, j) - 0.01
		var dx := (w.get_h(i + 1, j) - w.get_h(i - 1, j)) * 0.5
		var dz := (w.get_h(i, j + 1) - w.get_h(i, j - 1)) * 0.5
		var depth := WATER_Y - h
		idx[key] = verts.size()
		verts.append(Vector3(xz.x, h, xz.y))
		normals.append(Vector3(-dx, w.cell, -dz).normalized())
		uvs.append(xz)
		# R = 沙，B = 泥底（与 nature 生成器的 terrain 顶点权重约定一致）
		cols.append(Color(1.0 - smoothstep(0.9, 1.5, depth), 0.0, smoothstep(0.9, 1.5, depth), 1.0))
		return idx[key]
	for j in n - 1:
		for i in n - 1:
			var hs := [w.get_h(i, j), w.get_h(i + 1, j), w.get_h(i + 1, j + 1), w.get_h(i, j + 1)]
			if hs.min() >= -0.001:
				continue  # 整格都在岸上（跨岸线的格子要画，否则岸边会漏缝）
			var a: int = vid.call(i, j)
			var b: int = vid.call(i + 1, j)
			var c: int = vid.call(i + 1, j + 1)
			var d: int = vid.call(i, j + 1)
			indices.append_array([a, b, c, a, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, Mats.get_mat("terrain"))
	batch.add_static(mesh, Transform3D.IDENTITY, false)
	# 整条湖岸登记为水域（防止树和房子长进水里）
	var x := -H
	while x < H:
		var s := minf(shore(x), shore(x + 2.0))
		pl.add_rect(P.WATER, Rect2(x, s - 0.6, 2.0, H + LAKE_MARGIN - s))
		x += 2.0


func on_land(r: Rect2, margin := 1.5) -> bool:
	if r.position.x < -H + 0.5 or r.end.x > H - 0.5 or r.position.y < -H + 0.5:
		return false
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var xx: float = lerpf(r.position.x, r.end.x, t)
		if r.end.y > shore(xx) - margin:
			return false
	return true


# ---------------------------------------------------------------- 道路

func _build_roads() -> void:
	var land_bottom := (shore_base - 7.0) if w.with_lake else H - 3.0
	var main_z := rng.randf_range(-H * 0.15, H * 0.15) if w.with_lake else rng.randf_range(-H * 0.2, H * 0.2)
	main_z = minf(main_z, land_bottom - MIN_BLOCK - ROAD_W)
	# 小地图（如主界面的演示场景）放不下完整街区时，主街仍要留在地图里、离北边至少 8 米
	main_z = clampf(main_z, -H + 8.0, maxf(land_bottom - ROAD_W, -H + 8.0))
	var main := Rect2(-H, main_z - ROAD_W * 0.5, H * 2.0, ROAD_W)
	roads.append(main)
	_split(Rect2(-H, -H, H * 2.0, main.position.y + H), 0)
	_split(Rect2(-H, main.end.y, H * 2.0, land_bottom - main.end.y), 0)
	if w.with_lake and prm.get("promenade", false):
		# 滨海大道：贴着岸线的一条宽石板路（房子朝它排，码头从它伸进水里）
		var smin := INF
		var xx := -H
		while xx <= H:
			smin = minf(smin, shore(xx))
			xx += 2.0
		roads.append(Rect2(-H, smin - 7.5, H * 2.0, 6.0))
	for r in roads:
		pl.add_rect(P.ROAD, r)


## 路面网格放在广场之后建（广场也是「路」的一部分，一起算圆角）
func _build_road_surface() -> void:
	var mb := MB.new()
	var road_key: String = prm.get("road", "cobble")
	_road_contour(mb, road_key, 0.02)
	if road_key == "asphalt":
		_lane_markings(mb)
	batch.add_static(mb.commit(), Transform3D.IDENTITY, false)


# ---------------------------------------------------------------- 圆滑的道路（距离场 + marching squares）
# 道路不再是一块块方正的矩形：每条路是圆角矩形（路端是圆头，碰到地图边的那头延伸到图外），
# 多条路用平滑并集合起来（路口内角是半径 ROAD_FILLET 的圆弧），再按风格加一点边缘起伏（土路明显、沥青路几乎没有）。
# 网格用 marching squares 从距离场里取出来；路缘石沿同一条轮廓线走，转角也是圆的。
const ROAD_FILLET := 2.6
const ROAD_END_R := 1.6
const ROAD_GRID := 0.5
var _road_noise: FastNoiseLite
var _road_ready := false
var _sdf_vals := PackedFloat32Array()   # 路面距离场缓存（on_road 查表，不用每次重算）
var _sdf_bb := Rect2()
var _sdf_nx := 0
var _sdf_nz := 0
var _road_segs: Array = []


func road_sdf(p: Vector2) -> float:
	if roads.is_empty():
		return INF
	var d := INF
	for r in roads:
		var rr := r
		# 碰到地图边的路端延伸出去，免得在边上出现圆头
		if rr.position.x <= -H + 0.1:
			rr = rr.expand(Vector2(-H - 4.0, rr.position.y))
		if rr.end.x >= H - 0.1:
			rr = rr.expand(Vector2(H + 4.0, rr.end.y))
		if rr.position.y <= -H + 0.1:
			rr = rr.expand(Vector2(rr.position.x, -H - 4.0))
		if rr.end.y >= H - 0.1:
			rr = rr.expand(Vector2(rr.end.x, H + 4.0))
		var hs := rr.size * 0.5
		var cr := minf(ROAD_END_R, minf(hs.x, hs.y))
		var q := (p - rr.get_center()).abs() - hs + Vector2(cr, cr)
		var db := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - cr
		if d == INF:
			d = db
		else:
			var h := clampf(0.5 + 0.5 * (db - d) / ROAD_FILLET, 0.0, 1.0)
			d = lerpf(db, d, h) - ROAD_FILLET * h * (1.0 - h)
	if _road_noise == null:
		_road_noise = FastNoiseLite.new()
		_road_noise.seed = rng.randi()
		_road_noise.frequency = 0.12
	return d + _road_noise.get_noise_2d(p.x, p.y) * float(prm.get("road_wobble", 0.12))


## marching squares：把距离场 < 0 的区域铺成三角形（整格都在路上的连续格合成一块，面数少）。
## 返回边界线段（给路缘石用）
func _road_contour(mb: MB, key: String, y: float) -> Array:
	var bb := Rect2()
	var first := true
	for r in roads:
		bb = r if first else bb.merge(r)
		first = false
	bb = bb.grow(ROAD_FILLET).intersection(Rect2(-H, -H, 2.0 * H, 2.0 * H))
	var g := ROAD_GRID
	var nx := int(ceil(bb.size.x / g))
	var nz := int(ceil(bb.size.y / g))
	var vals := PackedFloat32Array()
	vals.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			vals[j * (nx + 1) + i] = road_sdf(bb.position + Vector2(i * g, j * g))
	var segs: Array = []
	for j in nz:
		var run_start := -1
		for i in nx + 1:
			var full := false
			if i < nx:
				full = vals[j * (nx + 1) + i] < 0.0 and vals[j * (nx + 1) + i + 1] < 0.0 \
					and vals[(j + 1) * (nx + 1) + i] < 0.0 and vals[(j + 1) * (nx + 1) + i + 1] < 0.0
			if full:
				if run_start < 0:
					run_start = i
				continue
			if run_start >= 0:
				var x0 := bb.position.x + run_start * g
				var x1 := bb.position.x + i * g
				var z0 := bb.position.y + j * g
				mb.face(key, [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z0 + g), Vector3(x0, y, z0 + g)], Vector3.UP)
				run_start = -1
			if i >= nx:
				continue
			# 边界格：沿四个角走一圈，里面的角 + 边上的交点围成多边形
			var cs := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
			var poly: Array[Vector3] = []
			var cross: Array[Vector2] = []
			for k in 4:
				var ca: Vector2i = cs[k]
				var cb: Vector2i = cs[(k + 1) % 4]
				var va := vals[ca.y * (nx + 1) + ca.x]
				var vb := vals[cb.y * (nx + 1) + cb.x]
				var pa := bb.position + Vector2(ca) * g
				var pb := bb.position + Vector2(cb) * g
				if va < 0.0:
					poly.append(Vector3(pa.x, y, pa.y))
				if (va < 0.0) != (vb < 0.0):
					var t := va / (va - vb)
					var pc := pa.lerp(pb, t)
					poly.append(Vector3(pc.x, y, pc.y))
					cross.append(pc)
			if poly.size() >= 3:
				mb.face(key, poly, Vector3.UP)
			if cross.size() == 2:
				segs.append([cross[0], cross[1]])
			elif cross.size() == 4:
				segs.append([cross[0], cross[1]])
				segs.append([cross[2], cross[3]])
	_road_ready = true
	_sdf_vals = vals
	_sdf_bb = bb
	_sdf_nx = nx
	_sdf_nz = nz
	_road_segs = segs
	return segs


## 某处是不是压在（圆滑后的）路面上：路口圆角会比原来的矩形多出一块
func on_road(p: Vector2, margin := 0.3) -> bool:
	if not _road_ready:
		return false
	var q := (p - _sdf_bb.position) / ROAD_GRID
	var i := int(round(q.x))
	var j := int(round(q.y))
	if i < 0 or j < 0 or i > _sdf_nx or j > _sdf_nz:
		return false
	return _sdf_vals[j * (_sdf_nx + 1) + i] < margin


## 沥青路中间的白色虚线（路口 3 米内不画）
func _lane_markings(mb: MB) -> void:
	for r in roads:
		var horiz := r.size.x >= r.size.y
		var a := r.position.x if horiz else r.position.y
		var b := r.end.x if horiz else r.end.y
		var c := r.get_center()
		var t := a + 1.0
		while t + 1.5 < b - 1.0:
			var p := Vector2(t + 0.75, c.y) if horiz else Vector2(c.x, t + 0.75)
			var near_cross := false
			for o in roads:
				if o != r and o.grow(3.0).has_point(p):
					near_cross = true
					break
			if not near_cross:
				var hw := Vector2(0.75, 0.06) if horiz else Vector2(0.06, 0.75)
				mb.face("road_paint", [Vector3(p.x - hw.x, 0.024, p.y - hw.y), Vector3(p.x + hw.x, 0.024, p.y - hw.y),
					Vector3(p.x + hw.x, 0.024, p.y + hw.y), Vector3(p.x - hw.x, 0.024, p.y + hw.y)], Vector3.UP)
			t += 3.0


## BSP：把区域切成街区，切线就是支路。只有足够大的区域才继续切
func _split(region: Rect2, depth: int) -> void:
	var max_depth := 2 if w.size <= 96 else 3
	if depth >= max_depth or region.size.x <= 0.0 or region.size.y <= 0.0:
		return
	var horiz := region.size.y > region.size.x  # 区域偏高 → 横着切（横向的路）
	var span := region.size.y if horiz else region.size.x
	if span < MIN_BLOCK * 2.0 + ROAD_W:
		return
	if depth > 0 and rng.randf() < 0.25:
		return  # 偶尔留一个大街区（公园 / 林地）
	var t := rng.randf_range(0.4, 0.6)
	var cut := (region.position.y if horiz else region.position.x) + span * t
	cut = clampf(cut, (region.position.y if horiz else region.position.x) + MIN_BLOCK + ROAD_W * 0.5,
		(region.end.y if horiz else region.end.x) - MIN_BLOCK - ROAD_W * 0.5)
	var road: Rect2
	var a: Rect2
	var b: Rect2
	if horiz:
		road = Rect2(region.position.x, cut - ROAD_W * 0.5, region.size.x, ROAD_W)
		a = Rect2(region.position.x, region.position.y, region.size.x, road.position.y - region.position.y)
		b = Rect2(region.position.x, road.end.y, region.size.x, region.end.y - road.end.y)
	else:
		road = Rect2(cut - ROAD_W * 0.5, region.position.y, ROAD_W, region.size.y)
		a = Rect2(region.position.x, region.position.y, road.position.x - region.position.x, region.size.y)
		b = Rect2(road.end.x, region.position.y, region.end.x - road.end.x, region.size.y)
	roads.append(road)
	_split(a, depth + 1)
	_split(b, depth + 1)


## 路缘石：每条路两侧各一条，在别的路接进来的地方断开
func _build_curbs(extra_gaps: Array[Rect2]) -> void:
	# 沿圆滑后的路面轮廓砌一圈路缘石（宽 CURB、高 CURB_H），转角跟着路口圆弧走；土路 / 码头小路接进来的地方断开
	var curb := MB.new()
	var segs := _road_segs
	for sg: Array in segs:
		var a2: Vector2 = sg[0]
		var b2: Vector2 = sg[1]
		var mid := (a2 + b2) * 0.5
		var gap := false
		for gr in extra_gaps:
			if gr.grow(0.3).has_point(mid):
				gap = true
		if gap:
			continue
		var na := _road_normal(a2) * CURB
		var nb := _road_normal(b2) * CURB
		var a3 := Vector3(a2.x, CURB_H, a2.y)
		var b3 := Vector3(b2.x, CURB_H, b2.y)
		curb.face("curb", [a3, b3, b3 + Vector3(nb.x, 0, nb.y), a3 + Vector3(na.x, 0, na.y)], Vector3.UP)
		var side := Vector3(-(b2 - a2).y, 0, (b2 - a2).x)
		if side.dot(Vector3(na.x, 0, na.y)) > 0.0:
			side = -side
		curb.face("curb", [Vector3(a2.x, 0, a2.y), Vector3(b2.x, 0, b2.y), b3, a3], side)
	batch.add_static(curb.commit(), Transform3D.IDENTITY)


## 距离场的梯度方向（指向路外）
func _road_normal(p: Vector2) -> Vector2:
	var e := 0.15
	var gx := road_sdf(p + Vector2(e, 0)) - road_sdf(p - Vector2(e, 0))
	var gz := road_sdf(p + Vector2(0, e)) - road_sdf(p - Vector2(0, e))
	var n := Vector2(gx, gz)
	return n.normalized() if n.length() > 1e-5 else Vector2.ZERO


static func _subtract(span: Vector2, cuts: Array[Vector2]) -> Array[Vector2]:
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var out: Array[Vector2] = []
	var cur := span.x
	for c in cuts:
		if c.x > cur:
			out.append(Vector2(cur, minf(c.x, span.y)))
		cur = maxf(cur, c.y)
		if cur >= span.y:
			break
	if cur < span.y:
		out.append(Vector2(cur, span.y))
	return out


# ---------------------------------------------------------------- 土路、码头、灯塔

## 返回土路的矩形（路缘石在这里断开）
func _build_path_and_pier() -> Rect2:
	# 找一条最靠南的横向道路，从它南边沿往湖边修土路；避开竖向道路
	var best := roads[0]  # 主街一定是横向的
	for r in roads:
		if r.size.x > r.size.y and r.end.y > best.end.y:
			best = r
	_path_top = best.end.y
	# 土路必须从这条路的下沿接出去：x 限定在路的覆盖范围内（BSP 支路不一定横贯全图）
	var candidates := []
	var lo := maxf(best.position.x + 3.0, -H * 0.6)
	var hi := minf(best.end.x - 3.0, H * 0.6)
	for i in 12:
		candidates.append(rng.randf_range(lo, hi))
	_path_x = candidates[0]
	for x: float in candidates:
		var ok := true
		for r in roads:
			if r.size.y > r.size.x and r.position.x - 3.0 < x + 1.5 and r.end.x + 3.0 > x - 1.5 and r.end.y > _path_top:
				ok = false
		if ok:
			_path_x = x
			break
	var z_end := shore(_path_x) - 1.0
	# 土路：边缘逐段错开几个像素
	var mb := MB.new()
	var y := 0.022
	var steps := maxi(4, int((z_end - _path_top) / 0.5))
	var prev_l := Vector3(_path_x - 1.4, y, _path_top)
	var prev_r := Vector3(_path_x + 1.4, y, _path_top)
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var z := lerpf(_path_top, z_end, t)
		var wob := sin(t * PI) * 0.6
		var xl := _path_x - 1.4 + wob + (rng.randi_range(-3, 3) * MB.SNAP if i < steps else 0.0)
		var xr := _path_x + 1.4 + wob + (rng.randi_range(-3, 3) * MB.SNAP if i < steps else 0.0)
		var l := Vector3(xl, y, z)
		var r := Vector3(xr, y, z)
		mb.face("dirt", [prev_l, prev_r, r, l], Vector3.UP)
		prev_l = l
		prev_r = r
	batch.add_static(mb.commit(), Transform3D.IDENTITY, false)
	var path_rect := Rect2(_path_x - 1.6, _path_top, 3.8, z_end - _path_top + 0.6)
	pl.add_rect(P.PATH, path_rect)
	# 码头：独立甲板 + 托梁 + 木桩 + 系船柱
	_pier = Rect2(_path_x - 1.25, z_end, 2.5, 10.0)
	var pier := MB.new()
	var z := _pier.position.y
	while z < _pier.end.y - 0.05:
		pier.box("deck", Vector3(_pier.position.x, -0.04, z), Vector3(_pier.end.x, 0.05, minf(z + 0.26, _pier.end.y) - 0.035))
		z += 0.26
	for bx in [_pier.position.x + 0.15, _pier.get_center().x, _pier.end.x - 0.15]:
		pier.box("trunk", Vector3(bx - 0.08, -0.3, _pier.position.y), Vector3(bx + 0.08, -0.04, _pier.end.y), false, true)
	for pz in [_pier.position.y + 4.0, _pier.position.y + 7.0, _pier.end.y - 0.4]:
		for px in [_pier.position.x + 0.2, _pier.end.x - 0.45]:
			pier.box("trunk", Vector3(px, -4.0, pz), Vector3(px + 0.25, -0.04, pz + 0.25), false)
	for c in [Vector2(_pier.position.x + 0.15, _pier.end.y - 0.2), Vector2(_pier.end.x - 0.15, _pier.end.y - 0.2)]:
		pier.ngon_frustum("trunk", Vector3(c.x, 0, c.y), 0.05, 0.45, 0.11, 0.1, 8, 0.0, true)
	batch.add_static(pier.commit(), Transform3D.IDENTITY)
	pl.add_rect(P.PATH, _pier)
	w.overrides.append([_pier, 0.05])
	# 码头边的货物
	var spots := [["bl_crate", Vector2(_path_x + 2.6, z_end - 1.6)], ["bl_crate", Vector2(_path_x + 3.4, z_end - 0.8)],
		["bl_barrel", Vector2(_path_x - 2.6, z_end - 1.2)], ["bl_barrel", Vector2(_path_x - 3.2, z_end - 2.0)],
		["bl_barrel", Vector2(_path_x + 0.6, z_end + 4.5)]]
	for s: Array in spots:
		var p: Vector2 = s[1]
		var on_pier := _pier.has_point(p)
		if on_pier or pl.can_place(P.PROP, p, 0.45):
			var fb := func() -> Mesh: return Props.build_crate() if s[0] == "bl_crate" else Props.build_barrel()
			batch.add_static(bl_pick(s[0], fb), Transform3D(Basis(Vector3.UP, rng.randf() * 0.8), Vector3(p.x, 0.05 if on_pier else 0.0, p.y)))
			if not on_pier:
				pl.add_circle(P.PROP, p, 0.45)
			pl.solid_circles.append(Vector3(p.x, p.y, 0.45))
	return path_rect


func _build_lighthouse() -> void:
	for i in 16:
		var x := rng.randf_range(-H + 6.0, H - 6.0)
		if absf(x - _path_x) < 9.0:
			continue
		var c := Vector2(x, shore(x) + 1.2)
		if not pl.can_place(P.LANDMARK, c, 3.1, 3.2, true):
			continue
		# 灯塔用 Blender 版（门朝向小镇）；没有 Blender 资产时退回代码版
		var bl := PWAssetLibrary.blender_variants("bl_lighthouse")
		if bl.is_empty():
			batch.add_static(Props.build_lighthouse(), Transform3D(Basis(), Vector3(c.x, 0, c.y)))
		else:
			batch.add_static(bl[rng.randi_range(0, bl.size() - 1)], Transform3D(Basis(Vector3.UP, PI), Vector3(c.x, 0, c.y)))
		pl.add_circle(P.LANDMARK, c, 3.1, 3.2, true)
		pl.solid_circles.append(Vector3(c.x, c.y, 3.1))
		return


# ---------------------------------------------------------------- 房屋

func _build_houses() -> void:
	for r: Rect2 in roads.duplicate():
		var horiz := r.size.x >= r.size.y
		for side in [-1, 1]:
			var u := (r.position.x if horiz else r.position.y) + rng.randf_range(0.5, 3.0)
			var u_end := r.end.x if horiz else r.end.y
			while u < u_end - 5.0:
				var p := _house_params()
				var fp: Vector2 = p.fp
				var yr: Array = prm.get("yard_depth", [2.6, 3.4])
				var yard := rng.randf_range(yr[0], yr[1])
				if rng.randf() > clampf(0.45 + 0.4 * w.house_density, 0.0, 1.0):
					u += fp.x * 0.6
					continue
				var placed := _try_house(r, horiz, side, u, p, fp, yard)
				u += (fp.x + rng.randf_range(2.0, 5.0) / maxf(w.house_density, 0.3)) if placed else 2.0


## side：-1 = 路的北 / 西侧，1 = 南 / 东侧。u = 沿路方向的起点
func _try_house(road: Rect2, horiz: bool, side: int, u: float, p: Dictionary, fp: Vector2, yard: float) -> bool:
	# 房屋局部 +Z 是正门；转到朝向道路
	var yaw: float
	var front: Vector2  # 世界里「朝路」的方向
	if horiz:
		yaw = 0.0 if side < 0 else PI
		front = Vector2(0, 1) if side < 0 else Vector2(0, -1)
	else:
		yaw = PI * 0.5 if side < 0 else -PI * 0.5
		front = Vector2(1, 0) if side < 0 else Vector2(-1, 0)
	var edge := (road.position.y if side < 0 else road.end.y) if horiz else (road.position.x if side < 0 else road.end.x)
	var along := u + fp.x * 0.5
	var center: Vector2
	if horiz:
		center = Vector2(along, edge - front.y * (yard + fp.y * 0.5))
	else:
		center = Vector2(edge - front.x * (yard + fp.y * 0.5), along)
	var size_w := Vector2(fp.x, fp.y) if horiz else Vector2(fp.y, fp.x)
	var rect := Rect2(center - size_w * 0.5, size_w)
	if not on_land(rect, 2.0):
		return false
	if not pl.can_place_rect(P.HOUSE, rect, 0.3, true):
		return false
	# 门前通道：从房屋正面到路边（留 0.35 米），宽 1.8 米
	var door_len := yard - 0.35
	var door: Rect2
	if horiz:
		var z0 := center.y + front.y * fp.y * 0.5
		door = Rect2(along - 0.9, minf(z0, z0 + front.y * door_len), 1.8, door_len)
	else:
		var x0 := center.x + front.x * fp.y * 0.5
		door = Rect2(minf(x0, x0 + front.x * door_len), along - 0.9, door_len, 1.8)
	if not pl.can_place_rect(P.DOOR, door):
		return false
	var basis := Basis(Vector3.UP, yaw)
	batch.add_static(bl(p.get("asset", "bl_town_house"))[p.bl] if p.has("bl") else House.build(p), Transform3D(basis, Vector3(center.x, 0, center.y)))
	if p.has("special"):
		_specials.erase(p.special)
	pl.add_rect(P.HOUSE, rect, 0.3, true)
	pl.add_rect(P.DOOR, door)
	var door_pt := center + front * (fp.y * 0.5 + 0.8)  # 门前通道上、离墙 0.8 米：NPC 的家
	w.homes.append(Vector3(door_pt.x, 0.0, door_pt.y))
	var body := Vector2(p.width + 0.5, p.depth + 0.5) if horiz else Vector2(p.depth + 0.5, p.width + 0.5)
	pl.solid_rects.append(Rect2(center - body * 0.5, body))
	# 篱笆：沿前院靠路一侧，门口留缺口
	if rng.randf() < float(prm.get("yard_chance", 0.55)):
		_cur_house = p.get("asset", "")
		_house_fence(basis, center, fp, yard)
	# 门两侧的灌木
	for sx in [-1.0, 1.0]:
		if rng.randf() < 0.7:
			var lx: float = sx * rng.randf_range(1.6, maxf(1.7, p.width * 0.5 - 0.5))
			var wp3 := basis * Vector3(lx, 0, p.depth * 0.5 + 0.7)
			_try_bush(Vector2(center.x + wp3.x, center.y + wp3.z), rng.randf_range(0.8, 1.1))
	return true


func _house_fence(basis: Basis, center: Vector2, fp: Vector2, yard: float) -> void:
	if prm.get("yard", "") == "courtyard" and not bl("bl_cn_courtyard_wall").is_empty():
		_courtyard(basis, center, fp, yard)
		return
	var style_i := rng.randi_range(0, 3 if not bl("bl_fence").is_empty() else Props.FENCE_STYLES.size() - 1)
	if prm.has("fence_styles") and not bl("bl_fence").is_empty():
		var fs: Array = prm.fence_styles
		style_i = fs[rng.randi_range(0, fs.size() - 1)]
	var half := fp.x * 0.5 - 0.3
	var lz := fp.y * 0.5 + yard - 1.3
	var gap := [half - 1.05, half + 1.05]  # 相对篱笆起点（-half）；比门前通道（±0.9）宽一点
	var runs := [Vector2(0.0, gap[0]), Vector2(gap[1], half * 2.0)]
	# 每段先检查（会不会撞到已有的路灯 / 树），都能放才建
	var rects: Array[Rect2] = []
	for r: Vector2 in runs:
		var a := basis * Vector3(-half + r.x, 0, lz)
		var b := basis * Vector3(-half + r.y, 0, lz)
		var pa := center + Vector2(a.x, a.z)
		var pb := center + Vector2(b.x, b.z)
		var rr := Rect2(pa, Vector2.ZERO).expand(pb).grow(0.12)
		if not pl.can_place_rect(P.FENCE, rr):
			return
		rects.append(rr)
	var origin3 := basis * Vector3(-half, 0, lz)
	var xf := Transform3D(basis, Vector3(center.x + origin3.x, 0, center.y + origin3.z))
	if bl("bl_fence").is_empty():
		batch.add_static(Props.build_fence(half * 2.0, [gap], Props.FENCE_STYLES[style_i]), xf)
	else:
		for r: Vector2 in runs:
			fence_run(xf * Transform3D(Basis(), Vector3(r.x, 0, 0)), r.y - r.x, style_i)
	for rr in rects:
		pl.add_rect(P.FENCE, rr)
		pl.solid_rects.append(rr)


# ---------------------------------------------------------------- 路灯、长椅

func _build_lamps() -> void:
	var lamp_meshes := {}
	# 路灯用 Blender 版（铸铁路灯，单臂 / 双臂）：灯臂沿局部 +X 伸出，转到朝向路面；光斑放在灯头正下方
	var bl_lamps := PWAssetLibrary.blender_variants("bl_street_lamp")
	# 其他风格的路灯（中世纪木柱提灯、现代 LED 路灯、乡村电线杆）：横臂沿局部 +Z 伸出，朝路
	var lantern: bool = prm.has("lamp") and not bl(prm.lamp).is_empty()
	if lantern:
		bl_lamps = bl(prm.lamp)
	var with_pools: bool = prm.get("lamp_pool", true)
	var pool := PlaneMesh.new()
	pool.size = Vector2(5, 5)
	var pm := ShaderMaterial.new()
	pm.shader = POOL_SHADER
	pool.material = pm
	var pools: Array[Transform3D] = []
	for r in roads:
		var horiz := r.size.x >= r.size.y
		var length := r.size.x if horiz else r.size.y
		var spacing: float = w.lamp_spacing * float(prm.get("lamp_spacing", 1.0))
		var n := int(length / spacing)
		var sides: Array = prm.get("lamp_sides", [-1, 1])
		for i in n:
			for side in sides:
				# 两侧交错：一侧在格点上，另一侧在半格处
				var t := (i + (0.5 if side > 0 else 0.0) + 0.25) * spacing
				if t > length - 1.0:
					continue
				var p: Vector2
				var to_road: Vector2
				if horiz:
					p = Vector2(r.position.x + t, r.position.y - 0.55 if side < 0 else r.end.y + 0.55)
					to_road = Vector2(0, 1) if side < 0 else Vector2(0, -1)
				else:
					p = Vector2(r.position.x - 0.55 if side < 0 else r.end.x + 0.55, r.position.y + t)
					to_road = Vector2(1, 0) if side < 0 else Vector2(-1, 0)
				var style: String = Trees.LAMP_STYLES[rng.randi_range(0, Trees.LAMP_STYLES.size() - 1)]
				var canopy := 0.9 if style == "arm" or style == "twin" else 0.4
				var bl_mesh: Mesh = null
				var bl_light := Vector3.ZERO
				if not bl_lamps.is_empty():
					bl_mesh = bl_lamps[rng.randi_range(0, bl_lamps.size() - 1)]
					var a := bl_mesh.get_aabb()
					if lantern:
						canopy = maxf(maxf(absf(a.position.z), absf(a.end.z)), 0.4)
						bl_light = Vector3(0, 0, 0.0 if a.position.z < -0.3 else a.end.z - 0.2)
					else:
						canopy = maxf(maxf(absf(a.position.x), absf(a.end.x)), 0.4)
						# 双臂（两边都伸出）：光斑在灯柱下；单臂：在灯头下
						bl_light = Vector3(0.0 if a.position.x < -0.3 else a.end.x - 0.22, 0, 0)
				if not on_land(Rect2(p - Vector2.ONE * 0.3, Vector2.ONE * 0.6), 1.0) or on_road(p, 0.35):
					continue
				if not pl.can_place(P.LAMP, p, 0.22, canopy, true):
					continue
				# 局部 +X 朝路（悬臂灯的灯头伸向路面）：绕 Y 转 θ 后 +X → (cosθ, 0, -sinθ)
				var yaw := atan2(to_road.x, to_road.y) if lantern else atan2(-to_road.y, to_road.x)
				var basis := Basis(Vector3.UP, yaw)
				if bl_mesh != null:
					batch.add_static(bl_mesh, Transform3D(basis, Vector3(p.x, 0, p.y)))
					if with_pools:
						pools.append(Transform3D(Basis(), Vector3(p.x, 0.04, p.y) + basis * bl_light))
				else:
					var metal: String = Trees.LAMP_METALS[rng.randi_range(0, Trees.LAMP_METALS.size() - 1)]
					var key := style + "/" + metal
					if not lamp_meshes.has(key):
						lamp_meshes[key] = Trees.build_lamp(style, metal)
					batch.add_static(lamp_meshes[key], Transform3D(basis, Vector3(p.x, 0, p.y)))
					pools.append(Transform3D(Basis(), Vector3(p.x, 0.04, p.y) + basis * Trees.lamp_light_offset(style)))
				pl.add_circle(P.LAMP, p, 0.22, canopy, true)
				pl.solid_circles.append(Vector3(p.x, p.y, 0.25))
				_lamp_spots.append([p, to_road])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pool
	mm.instance_count = pools.size()
	for i in pools.size():
		mm.set_instance_transform(i, pools[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LightPools"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.content().add_child(mmi)


# ---------------------------------------------------------------- 中国乡村：院墙、庄稼地；现代小镇：路边停车

## 农家院：前院沿临街一边砌院墙，正对房门开门楼（4 米一段，门楼 4 米、门洞 3 米），两侧院墙接到房子正面
var _cur_house := ""


func _courtyard(basis: Basis, center: Vector2, fp: Vector2, yard: float) -> void:
	var walls := bl("bl_cn_courtyard_wall")
	var gates := bl("bl_cn_courtyard_gate")
	var half := fp.x * 0.5 - 0.2
	var lz := fp.y * 0.5 + yard - 0.9
	var back := fp.y * 0.5 + 0.75  # 房屋登记的占地外扩 0.3 米，再留出房屋和院墙的间距
	var rects: Array[Rect2] = []
	# 登记占地时侧墙在拐角前 0.9 米收住（和正面墙不互相「太近」；墙体本身照样砌到拐角）
	for seg: Array in [[Vector3(-half, 0, lz), Vector3(-2.0, 0, lz)], [Vector3(2.0, 0, lz), Vector3(half, 0, lz)],
			[Vector3(-half, 0, back), Vector3(-half, 0, lz - 0.9)], [Vector3(half, 0, back), Vector3(half, 0, lz - 0.9)]]:
		var a := basis * (seg[0] as Vector3)
		var b := basis * (seg[1] as Vector3)
		var rr := Rect2(center + Vector2(a.x, a.z), Vector2.ZERO).expand(center + Vector2(b.x, b.z)).grow(0.2)
		if not pl.can_place_rect(P.FENCE, rr):
			return
		rects.append(rr)
	var o := Vector3(center.x, 0, center.y)
	# 院墙和院门用同一款（0 红砖、1 灰水泥、2 石垒 + 竹门、3 红砖瓦顶门楼）；木构老屋配石垒墙
	var style_k: int = 2 if _cur_house == "bl_cn_timber_house" else [0, 0, 1, 3][rng.randi_range(0, 3)]
	if not gates.is_empty():
		var g := basis * Vector3(0, 0, lz)
		batch.add_static(gates[style_k % gates.size()], Transform3D(basis, o + g))
	var wv := walls[style_k % walls.size()]
	# 院子里的摆设：竹桌椅、晒匾、咸菜坛、柴堆、脸盆架、水缸，放在院子两侧（门口正中留出来）
	var yard_ids := ["bl_cn_bamboo_table_set", "bl_cn_drying_tray", "bl_cn_pickle_jars", "bl_cn_firewood_stack",
		"bl_cn_basin_stool", "bl_cn_water_vat", "bl_cn_drying_tray"]
	for sx2: float in [-1.0, 1.0]:
		var v := bl(yard_ids[rng.randi_range(0, yard_ids.size() - 1)])
		if v.is_empty() or half < 4.0:
			continue
		var lp := basis * Vector3(sx2 * rng.randf_range(2.6, half - 2.0), 0, (back + lz) * 0.5 + rng.randf_range(-0.4, 0.6))
		var q := center + Vector2(lp.x, lp.z)
		var pr := Rect2(q - Vector2(1.1, 1.1), Vector2(2.2, 2.2))
		var hits_wall := false
		for rr in rects:  # 院墙这时还没登记，自己查一下别贴到墙上
			if rr.grow(0.45).intersects(pr):
				hits_wall = true
		if hits_wall or not pl.can_place_rect(P.PROP, pr, 0.0, true):
			continue
		batch.add_static(v[rng.randi_range(0, v.size() - 1)], Transform3D(basis * Basis(Vector3.UP, rng.randi_range(0, 3) * PI * 0.5), Vector3(q.x, 0, q.y)))
		pl.add_rect(P.PROP, pr, 0.0, true)
		pl.solid_rects.append(pr)
	# 正面两段（局部 X 方向）、两侧两段（局部 Z 方向，转 90°，外侧朝两边）
	for seg: Array in [[-half, -2.0, 0.0], [2.0, half, 0.0], [back, lz, -half], [back, lz, half]]:
		var a0: float = seg[0]
		var a1: float = seg[1]
		var sx: float = seg[2]
		var ln := a1 - a0
		if ln < 0.6:
			continue
		var n := maxi(1, roundi(ln / 4.0))
		var k := ln / (n * 4.0)
		for i in n:
			var mid := a0 + (i + 0.5) * 4.0 * k
			var local: Transform3D
			if sx == 0.0:
				local = Transform3D(Basis().scaled(Vector3(k, 1, 1)), Vector3(mid, 0, lz))
			else:
				local = Transform3D(Basis(Vector3.UP, PI * 0.5 * signf(sx)) * Basis().scaled(Vector3(k, 1, 1)), Vector3(sx, 0, mid))
			batch.add_static(wv, Transform3D(basis, o) * local)
	for rr in rects:
		pl.add_rect(P.FENCE, rr)
		pl.solid_rects.append(rr)


## 庄稼地：空着的大块地里开几块菜地 / 麦地（一垄一垄的绿苗，地头是土）
func _build_fields() -> void:
	var n_fields := 0
	var step := 7.0
	var x := -H + 4.0
	while x < H - 10.0 and n_fields < int(prm.get("fields", 0)):
		var z := -H + 4.0
		while z < H - 8.0 and n_fields < int(prm.get("fields", 0)):
			var r := Rect2(x + rng.randf_range(-1.0, 1.0), z + rng.randf_range(-1.0, 1.0), float(rng.randi_range(4, 7)) * 2.0, float(rng.randi_range(3, 5)) * 2.0)
			if on_land(r, 1.0) and pl.can_place_rect(P.PROP, r.grow(0.8), 0.0, true) and rng.randf() < 0.6:
				_field(r)
				pl.add_rect(P.PROP, r, 0.0, true)
				n_fields += 1
			z += step
		x += step * 1.4


func _field(r: Rect2) -> void:
	var mb := MB.new()
	mb.face("dirt", [Vector3(r.position.x, 0.03, r.position.y), Vector3(r.end.x, 0.03, r.position.y),
		Vector3(r.end.x, 0.03, r.end.y), Vector3(r.position.x, 0.03, r.end.y)], Vector3.UP)
	batch.add_static(mb.commit(), Transform3D.IDENTITY)
	# 一块地种一种：玉米（变体 0 青、1 带棒子、2 矮）或麦子（0 青、1 金黄、2 混）
	var corn := rng.randf() < 0.5
	var v := bl("bl_cn_corn_patch" if corn else "bl_cn_wheat_patch")
	if v.is_empty():
		return
	var kind := rng.randi_range(0, 1)
	var x := r.position.x + 1.0
	while x < r.end.x - 0.6:
		var z := r.position.y + 1.0
		while z < r.end.y - 0.6:
			var m := v[kind if rng.randf() < 0.8 else rng.randi_range(0, v.size() - 1)]
			var sc := rng.randf_range(0.9, 1.12)
			batch.add_plant(m, Transform3D(Basis(Vector3.UP, rng.randi_range(0, 3) * PI * 0.5).scaled(Vector3(1, sc, 1)),
				Vector3(x, 0.03, z)), tint(0.06))
			z += 2.0
		x += 2.0


## 路边停车（现代小镇）：顺着路靠边停，路口附近不停
func _build_cars() -> void:
	var cars := bl("bl_car")
	if cars.is_empty():
		return
	for r in roads:
		if r == plaza:
			continue
		var horiz := r.size.x >= r.size.y
		var a := (r.position.x if horiz else r.position.y) + 4.0
		var b := (r.end.x if horiz else r.end.y) - 4.0
		var t := a
		while t < b:
			if rng.randf() < float(prm.get("cars", 0.0)):
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				var c := r.get_center()
				var p := Vector2(t, c.y + side * (ROAD_W * 0.5 - 0.95)) if horiz else Vector2(c.x + side * (ROAD_W * 0.5 - 0.95), t)
				var near := false
				for o in roads:
					if o != r and o.grow(3.5).has_point(p):
						near = true
				var ext := Vector2(2.3, 1.0) if horiz else Vector2(1.0, 2.3)
				var rect := Rect2(p - ext, ext * 2.0)
				if not near and pl.can_place_rect(P.CAR, rect, 0.0, true):
					# 车头朝 +Z：顺着路的方向（靠右行驶）
					var yaw := (PI * 0.5 if side > 0 else -PI * 0.5) if horiz else (0.0 if side < 0 else PI)
					batch.add_static(cars[rng.randi_range(0, cars.size() - 1)], Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.02, p.y)))
					pl.add_rect(P.CAR, rect, 0.0, true)
					pl.solid_rects.append(rect)
			t += rng.randf_range(6.0, 10.0)


# ---------------------------------------------------------------- 中世纪小镇：广场、城墙

## 中心广场：主街和离地图中线最近的竖向支路的路口，铺一块方形石板广场。
## 广场也加进 roads，房屋会沿它的四边朝内排；水井、摊位、旗杆之后摆在广场上（_build_plaza_props）
func _build_plaza() -> void:
	var main: Rect2 = roads[0]
	var cx := 0.0
	var bd := INF
	for r in roads:
		if r.size.y > r.size.x and r.position.y <= main.end.y + 0.1 and r.end.y >= main.position.y - 0.1:
			if absf(r.get_center().x) < bd:
				bd = absf(r.get_center().x)
				cx = r.get_center().x
	var half := Vector2(9.0, 7.0)
	var c := Vector2(cx, main.get_center().y)
	c.y = clampf(c.y, -H + 12.0, H - 12.0)
	plaza = Rect2(c - half, half * 2.0)
	pl.add_rect(P.PLAZA, plaza)  # 石板地面和道路一起铺（_build_road_surface），转角是圆的
	roads.append(plaza)


## 广场上的东西：正中一口井，四周三四个摊位（朝广场中心）、四角旗杆、一块布告栏、一个水槽
func _build_plaza_props() -> void:
	if plaza.size == Vector2.ZERO:
		return
	var c := plaza.get_center()
	var well := bl("bl_well")
	if not well.is_empty():
		batch.add_static(well[rng.randi_range(0, well.size() - 1)], Transform3D(Basis(Vector3.UP, rng.randi_range(0, 3) * PI * 0.5), Vector3(c.x, 0.026, c.y)))
		var wr := Rect2(c - Vector2(1.4, 1.4), Vector2(2.8, 2.8))
		pl.add_rect(P.STALL, wr, 0.0, true)
		pl.solid_rects.append(wr)
	# 摊位：贴着广场的南北两边，正面朝广场中心
	var stalls := bl("bl_market_stall")
	var spots: Array = []
	for sx in [-5.0, 0.5, 5.5]:
		spots.append([Vector2(c.x + sx, plaza.position.y + 1.6), 0.0])        # 北边，朝南（+Z）
		spots.append([Vector2(c.x + sx, plaza.end.y - 1.6), PI])               # 南边，朝北
	spots.shuffle()
	var n_stall := 0
	for sp: Array in spots:
		if stalls.is_empty() or n_stall >= 4:
			break
		var q: Vector2 = sp[0]
		var r := Rect2(q - Vector2(1.9, 1.0), Vector2(3.8, 2.0))
		if not pl.can_place_rect(P.STALL, r, 0.0, true):
			continue
		batch.add_static(stalls[rng.randi_range(0, stalls.size() - 1)], Transform3D(Basis(Vector3.UP, sp[1]), Vector3(q.x, 0.026, q.y)))
		# 摊主站在柜台后面，面朝广场（摊位正面是局部 +Z）
		var fwd := Basis(Vector3.UP, sp[1]) * Vector3(0, 0, 1)
		w.vendor_spots.append([Vector3(q.x, 0.026, q.y) - fwd * 1.4, fwd])
		pl.add_rect(P.STALL, r, 0.0, true)
		pl.solid_rects.append(r)
		n_stall += 1
	var banners := bl("bl_banner_pole")
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		if banners.is_empty():
			break
		var q := c + corner * (plaza.size * 0.5 - Vector2(0.9, 0.9))
		if not pl.can_place(P.STALL, q, 0.5, 0.0, true):
			continue
		batch.add_static(banners[rng.randi_range(0, banners.size() - 1)], Transform3D(Basis(Vector3.UP, atan2(-corner.x, -corner.y)), Vector3(q.x, 0.026, q.y)))
		pl.add_circle(P.STALL, q, 0.5, 0.0, true)
		pl.solid_circles.append(Vector3(q.x, q.y, 0.3))
	for id: String in ["bl_spec_notice_board", "bl_water_trough"]:
		var v := bl(id)
		if v.is_empty():
			continue
		for attempt in 12:
			var q := c + Vector2(rng.randf_range(-6.5, 6.5), rng.randf_range(-4.5, 4.5))
			var r := Rect2(q - Vector2(1.5, 0.7), Vector2(3.0, 1.4))
			if r.get_center().distance_to(c) < 3.0 or not pl.can_place_rect(P.STALL, r, 0.0, true):
				continue
			batch.add_static(v[rng.randi_range(0, v.size() - 1)], Transform3D(Basis(Vector3.UP, rng.randi_range(0, 3) * PI * 0.5), Vector3(q.x, 0.026, q.y)))
			pl.add_rect(P.STALL, r, 0.0, true)
			pl.solid_rects.append(r)
			break


## 港口（中世纪海边小镇）：几座木码头从岸边伸进水里，大帆船靠在码头旁，小船散在近岸
func _build_harbor() -> void:
	var piers := bl("bl_med_pier")
	var ships := bl("bl_med_ship")
	if piers.is_empty():
		return
	var n := 3 if H > 44.0 else 2
	for i in n:
		var x := lerpf(-H * 0.55, H * 0.55, (i + 0.5) / n) + rng.randf_range(-3.0, 3.0)
		var z := shore(x) - 0.6
		# 码头原点在靠岸一端，桥面沿 +Z 伸出 8 米；桥面比原点高 0.35，放低一点让桥面和岸齐平
		batch.add_static(piers[rng.randi_range(0, piers.size() - 1)], Transform3D(Basis(), Vector3(x, -0.3, z)))
		var deck := Rect2(x - 1.25, z, 2.5, 8.0)
		pl.add_rect(P.PATH, deck)
		w.overrides.append([deck, 0.05])
		if ships.size() >= 2:
			# 大船（变体 0 = 三桅帆船，1 = 单桅货船）靠在码头一侧，船头朝外海；水线在水面
			var k := 0 if i % 2 == 0 else 1
			var half_beam := 2.9 if k == 0 else 2.3
			var side := -1.0 if i % 2 == 0 else 1.0
			var sp := Vector3(x + side * (1.25 + half_beam + 0.4), WATER_Y, z + (17.0 if k == 0 else 12.0))
			batch.add_static(ships[k], Transform3D(Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)), sp))
	if ships.size() >= 3:
		for i in 4:
			var x := rng.randf_range(-H + 6.0, H - 6.0)
			var sp := Vector3(x, WATER_Y, shore(x) + rng.randf_range(5.0, 12.0))
			batch.add_static(ships[2], Transform3D(Basis(Vector3.UP, rng.randf() * TAU), sp))


## 城墙：沿地图四边一圈（离边 2~3 米）。路穿过城墙的地方开城门（城门 12 米 = 两段墙），
## 其余用 6 米一段的墙填满（按长度微调拉伸），四角和每隔约 24 米放一座塔楼盖住接缝。
## Blender 约定：墙 / 城门的外侧朝 Godot +Z，墙段沿局部 X、原点在中心
func _build_walls() -> void:
	var walls := bl("bl_town_wall")
	if walls.is_empty():
		return
	var gates := bl("bl_town_gate")
	var towers := bl("bl_town_wall_tower")
	var W := floorf((H - 2.0) / 3.0) * 3.0
	# 四条边：起点、方向（沿墙）、外侧朝向（yaw：局部 +Z → 外侧）
	var sides := [
		[Vector2(-W, -W), Vector2(1, 0), PI],          # 北边，外侧 -Z
		[Vector2(-W, W), Vector2(1, 0), 0.0],          # 南边，外侧 +Z
		[Vector2(-W, -W), Vector2(0, 1), -PI * 0.5],   # 西边，外侧 -X
		[Vector2(W, -W), Vector2(0, 1), PI * 0.5],     # 东边，外侧 +X
	]
	var tower_pts: Array[Vector2] = [Vector2(-W, -W), Vector2(W, -W), Vector2(-W, W), Vector2(W, W)]
	var side_len := 2.0 * W   # 东西两面墙的长度
	if w.with_lake:
		# 海边小镇：临水的南面不砌墙，东西两面砌到岸边前 5 米为止（末端各一座塔楼）
		side_len = floorf((minf(shore(-W), shore(W)) - 5.0 + W) / 6.0) * 6.0
		sides.remove_at(1)
		tower_pts = [Vector2(-W, -W), Vector2(W, -W), Vector2(-W, -W + side_len), Vector2(W, -W + side_len)]
	for sd: Array in sides:
		var o: Vector2 = sd[0]
		var dir: Vector2 = sd[1]
		var basis := Basis(Vector3.UP, sd[2])
		var ln_side := side_len if dir.y != 0.0 else 2.0 * W
		# 哪些路穿过这条边：横着的路穿过东西两边，竖着的路穿过南北两边
		var cuts: Array[float] = []
		for r: Rect2 in roads:
			if r == plaza:
				continue
			var horiz := r.size.x >= r.size.y
			if dir.x != 0.0 and not horiz:   # 南北边：看竖向的路
				var line := o.y
				if r.position.y <= line + 0.5 and r.end.y >= line - 0.5:
					cuts.append(r.get_center().x + W)
			elif dir.y != 0.0 and horiz:     # 东西边：看横向的路
				var line := o.x
				if r.position.x <= line + 0.5 and r.end.x >= line - 0.5:
					cuts.append(r.get_center().y + W)
		cuts.sort()
		# 城门（离角至少 9 米、彼此不重叠）
		var gate_at: Array[float] = []
		for t in cuts:
			if gates.is_empty() or t < 9.0 or t > ln_side - 9.0:
				continue
			if not gate_at.is_empty() and t - gate_at[-1] < 13.0:
				continue
			gate_at.append(t)
		# 墙段：[0, 2W] 去掉城门占的 [t-6, t+6]
		var segs: Array[Vector2] = []
		var start := 0.0
		for t in gate_at:
			segs.append(Vector2(start, t - 6.0))
			start = t + 6.0
		segs.append(Vector2(start, ln_side))
		for t in gate_at:
			var gp := o + dir * t
			batch.add_static(gates[rng.randi_range(0, gates.size() - 1)], Transform3D(basis, Vector3(gp.x, 0, gp.y)))
			# 城门两侧的塔是实心的，门洞（±1.6 米）留给路
			for sx: float in [-1.0, 1.0]:
				var tp := gp + dir * sx * 4.0
				pl.add_circle(P.WALL, tp, 2.0, 0.0, true)
				pl.solid_circles.append(Vector3(tp.x, tp.y, 2.0))
			for sx: float in [-1.0, 1.0]:
				var a := gp + dir * sx * 1.7
				var b := gp + dir * sx * 6.0
				var rr := Rect2(a, Vector2.ZERO).expand(b).grow(0.8)
				pl.add_rect(P.WALL, rr, 0.0, true)
				pl.solid_rects.append(rr)
		for sg: Vector2 in segs:
			var ln := sg.y - sg.x
			if ln < 0.5:
				continue
			var n := maxi(1, roundi(ln / 6.0))
			var k := ln / (n * 6.0)
			for i in n:
				var mid := o + dir * (sg.x + (i + 0.5) * 6.0 * k)
				batch.add_static(walls[rng.randi_range(0, walls.size() - 1)], Transform3D(basis * Basis().scaled(Vector3(k, 1, 1)), Vector3(mid.x, 0, mid.y)))
			var a2 := o + dir * sg.x
			var b2 := o + dir * sg.y
			var wr := Rect2(a2, Vector2.ZERO).expand(b2).grow(0.8)
			pl.add_rect(P.WALL, wr, 0.0, true)
			pl.solid_rects.append(wr)
			# 长墙段中间加塔楼（盖在墙段接缝上）
			if n >= 5 and not towers.is_empty():
				var every := int(ceil(n / 2.0))
				var tj := sg.x + every * 6.0 * k
				tower_pts.append(o + dir * tj)
	for tp in tower_pts:
		if towers.is_empty():
			break
		batch.add_static(towers[rng.randi_range(0, towers.size() - 1)], Transform3D(Basis(Vector3.UP, rng.randi_range(0, 3) * PI * 0.5), Vector3(tp.x, 0, tp.y)))
		pl.add_circle(P.WALL, tp, 2.7, 0.0, true)
		pl.solid_circles.append(Vector3(tp.x, tp.y, 2.7))


## 中世纪小镇里专门的建筑（各放一座）：教堂、酒馆、铁匠铺。放不下就留到下一个位置再试
var _specials: Array[String] = []


## 一个 Blender 建筑的参数：挑一个变体，尺寸取 variant_info（没有就用 catalog 里的占地）
func _bl_building(id: String) -> Dictionary:
	var meshes := bl(id)
	if meshes.is_empty():
		return {}
	var k := rng.randi_range(0, meshes.size() - 1)
	var info := PWAssetLibrary.blender_variant_info(id)
	var fp := Vector2(6, 6)
	var wd := Vector2.ZERO
	if info.size() == meshes.size():
		var vi: Dictionary = info[k]
		fp = Vector2(float(vi.footprint[0]), float(vi.footprint[1]))
		if vi.has("width"):
			wd = Vector2(float(vi.width), float(vi.depth))
	else:
		for it in PWAssetLibrary.blender_items():
			if it.id == id:
				var f: Array = it.get("footprint", [6, 6])
				fp = Vector2(float(f[0]), float(f[1]))
	if wd == Vector2.ZERO:
		wd = fp - Vector2(0.9, 0.9)
	return {"asset": id, "bl": k, "width": wd.x, "depth": wd.y, "fp": fp}


# ---------------------------------------------------------------- Blender 资产

var _bl_cache := {}


## Blender 资产的全部变体（缓存）；没有 Blender 资产目录时是空数组
func bl(id: String) -> Array[Mesh]:
	if not _bl_cache.has(id):
		_bl_cache[id] = PWAssetLibrary.blender_variants(id)
	return _bl_cache[id]


## 随机挑一个 Blender 变体；没有就用 fallback（Godot 代码版）造一个
func bl_pick(id: String, fallback: Callable) -> Mesh:
	var v := bl(id)
	return v[rng.randi_range(0, v.size() - 1)] if not v.is_empty() else fallback.call()


func weed_variants() -> Array[Mesh]:
	var v := bl("bl_weed")
	if v.is_empty():
		v = [Props.build_weed(5000), Props.build_weed(5001), Props.build_weed(5002)]
	return v


## 房屋参数：有 Blender 小镇房屋就随机挑一个变体（尺寸来自 catalog 的 variant_info），否则用代码版的随机参数
func _house_params() -> Dictionary:
	if prm.has("houses"):
		if not _specials.is_empty() and rng.randf() < 0.45:
			var sp := _bl_building(_specials[0])
			if not sp.is_empty():
				sp["special"] = _specials[0]
				return sp
		var hs: Array = prm.houses
		var mh := _bl_building(hs[rng.randi_range(0, hs.size() - 1)])
		if not mh.is_empty():
			return mh
	var info := PWAssetLibrary.blender_variant_info("bl_town_house")
	if info.size() == bl("bl_town_house").size() and not info.is_empty():
		var k := rng.randi_range(0, info.size() - 1)
		var vi: Dictionary = info[k]
		return {"bl": k, "width": float(vi.width), "depth": float(vi.depth),
			"fp": Vector2(float(vi.footprint[0]), float(vi.footprint[1]))}
	var p := House.random_params(rng)
	p["fp"] = House.footprint(p)
	return p


## 一排 Blender 篱笆：沿 xf 的局部 +X 从 0 到 length。每段模块 2 米（左端自带柱子），按长度微调拉伸；末尾补一根柱子。
## style：0 白栅栏、1 木栏、2 石墙、3 深色木条
func fence_run(xf: Transform3D, length: float, style: int) -> void:
	var segs := bl("bl_fence")
	var posts := bl("bl_fence_post")
	if length > 0.7:
		var n := maxi(1, roundi(length / 2.0))
		var k := length / (n * 2.0)
		for i in n:
			batch.add_static(segs[style % segs.size()], xf * Transform3D(Basis().scaled(Vector3(k, 1, 1)), Vector3((i * 2.0 + 1.0) * k, 0, 0)))
	elif not posts.is_empty():
		batch.add_static(posts[style % posts.size()], xf)
	if not posts.is_empty():
		batch.add_static(posts[style % posts.size()], xf * Transform3D(Basis(), Vector3(length, 0, 0)))


func _build_benches() -> void:
	if not prm.get("benches", true):
		return
	var bench_id: String = prm.get("bench", "bl_bench")
	var benches := {}
	for spot: Array in _lamp_spots:
		if rng.randf() > 0.35:
			continue
		var lp: Vector2 = spot[0]
		var to_road: Vector2 = spot[1]
		var along := Vector2(-to_road.y, to_road.x)
		var p := lp + along * 2.2 - to_road * 0.35
		var horiz := absf(to_road.y) > 0.5
		var rect := Rect2(p - (Vector2(0.9, 0.35) if horiz else Vector2(0.35, 0.9)), Vector2(1.8, 0.7) if horiz else Vector2(0.7, 1.8))
		if not pl.can_place_rect(P.BENCH, rect):
			continue
		var si := rng.randi_range(0, Props.BENCH_STYLES.size() - 1)
		var style: String = Props.BENCH_STYLES[si]
		if not benches.has(style):
			var bb := bl(bench_id)
			benches[style] = bb[si % bb.size()] if not bb.is_empty() else Props.build_bench(style)
		# 长椅局部 +Z 是正面：朝向道路
		var yaw := atan2(to_road.x, to_road.y)
		batch.add_static(benches[style], Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0, p.y)))
		pl.add_rect(P.BENCH, rect)
		pl.solid_rects.append(rect)


# ---------------------------------------------------------------- 植被

var _pines: Array[Mesh] = []
var _broads: Array[Mesh] = []
var _bushes: Array[Mesh] = []
var _rocks: Array[Mesh] = []
var _canopy := {}  # Mesh -> 树冠半径


func _variants() -> void:
	if not _pines.is_empty():
		return
	# 全部用 Blender 版：松树 10、橡树 8、白桦 8、杨树 6、灌木 8、石头 8 个变体。
	# 没有 Blender 资产目录时退回代码版
	_pines.append_array(bl("bl_pine"))
	if _pines.is_empty():
		for i in 10:
			_pines.append(Trees.build_pine(1000 + i))
	var styles := ["oak", "oak", "birch", "poplar", "oak", "birch", "poplar", "oak", "oak", "birch", "poplar", "oak"]
	for kind in ["oak", "birch", "poplar"]:
		var v := bl("bl_" + kind)
		if v.is_empty():
			for i in styles.size():
				if styles[i] == kind:
					_broads.append(Trees.build_broadleaf(2000 + i, kind))
		else:
			# 橡树多一些：白桦 / 杨树各取一半变体
			_broads.append_array(v if kind == "oak" else v.slice(0, maxi(2, v.size() / 2)))
	if prm.get("big_trees", false) and not bl("bl_cn_big_tree").is_empty():
		_broads.clear()
		_broads.append_array(bl("bl_cn_big_tree"))
		_broads.append_array(bl("bl_cn_big_tree"))
		_broads.append_array(bl("bl_poplar").slice(0, 2))
	_bushes.append_array(bl("bl_bush"))
	if _bushes.is_empty():
		for i in 8:
			_bushes.append(Trees.build_bush(3000 + i))
	_rocks.append_array(bl("bl_rock"))
	if _rocks.is_empty():
		for i in 8:
			_rocks.append(Trees.build_rock(4000 + i))
	for m in _pines + _broads + _bushes + _rocks:
		var a: AABB = m.get_aabb()
		_canopy[m] = maxf(maxf(absf(a.position.x), absf(a.end.x)), maxf(absf(a.position.z), absf(a.end.z)))


func tint(amount: float) -> Color:
	var k := rng.randf_range(1.0 - amount, 1.0 + amount * 0.6)
	return Color(k * rng.randf_range(0.95, 1.05), k * rng.randf_range(0.96, 1.04), k * rng.randf_range(0.93, 1.05), 1.0)


## 放一棵树（任意朝向、宽高比例、色调）；能放返回 true
func try_tree(p: Vector2, mesh: Mesh, s: float, pine: bool) -> bool:
	var sxz := s * rng.randf_range(0.9, 1.1)
	var sy := s * rng.randf_range(0.9, 1.18)
	var canopy: float = _canopy[mesh] * sxz
	var trunk := 0.3 * sxz
	if on_road(p, trunk + 0.5) or not pl.can_place(P.TREE, p, trunk, canopy, true):
		return false
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sxz, sy, sxz)), Vector3(p.x, w.ground_y(p.x, p.y), p.y))
	batch.add_plant(mesh, xf, tint(0.1))
	pl.add_circle(P.TREE, p, trunk, canopy, true)
	pl.solid_circles.append(Vector3(p.x, p.y, 0.4 if pine else 0.35))
	return true


func _try_bush(p: Vector2, s: float) -> bool:
	_variants()
	var mesh := _bushes[rng.randi_range(0, _bushes.size() - 1)]
	var r: float = _canopy[mesh] * s
	if on_road(p, r) or not pl.can_place(P.BUSH, p, r):
		return false
	var sy := s * rng.randf_range(0.85, 1.15)
	batch.add_plant(mesh, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, sy, s)), Vector3(p.x, 0, p.y)), tint(0.1))
	pl.add_circle(P.BUSH, p, r)
	pl.solid_circles.append(Vector3(p.x, p.y, r * 0.8))
	return true


func _build_trees() -> void:
	_variants()
	var attempts := int(w.size * w.size * 0.4 * w.tree_density * float(prm.get("trees", 1.0)))
	for i in attempts:
		var p := Vector2(rng.randf_range(-H + 1.0, H - 1.0), rng.randf_range(-H + 1.0, H - 1.0))
		if w.with_lake and p.y > shore(p.x) - 2.0:
			continue
		var belt := p.y < -H + 12.0  # 北边林带：更密，几乎全是松树
		if not belt and rng.randf() > 0.35:
			continue
		var pine := rng.randf() < (float(prm.get("pine_belt", 0.92)) if belt else float(prm.get("pine_ratio", 0.55)))
		var mesh: Mesh = _pines[rng.randi_range(0, _pines.size() - 1)] if pine else _broads[rng.randi_range(0, _broads.size() - 1)]
		try_tree(p, mesh, rng.randf_range(0.75, 1.2), pine)


## Blender 资产（P3 + 资产工坊）：按标签挑选——带 plaza / roadside / yard 标签的摆件放在路边（正面朝路），
## 同样经过摆放规则检查。石井 1 口、集市摊位 3 个，其余每种 1~2 个。资产工坊新生成的同类资产会自动出现在小镇里。
## 路灯、灯塔、树、房屋有各自的生成逻辑，这里不放。
func _build_blender_props() -> void:
	var counts := {"bl_well": 1, "bl_market_stall": 3}
	var exclude := ["bl_street_lamp", "bl_lighthouse", "bl_cottage", "bl_pine", "bl_oak", "bl_lantern_post",
		"bl_modern_street_lamp", "bl_cn_utility_pole", "bl_car", "bl_cn_courtyard_wall", "bl_cn_courtyard_gate", "bl_med_ship", "bl_med_pier", "bl_cn_corn_patch", "bl_cn_wheat_patch", "bl_cn_big_tree", "bl_med_round_tower"]
	var style_tag: String = prm.get("style_tag", "")
	if medieval:
		# 井和摊位已经摆在广场上；路边多放些木桶、柴堆、水槽、旗杆
		counts = {"bl_well": 0, "bl_market_stall": 1, "bl_banner_pole": 3, "bl_firewood_pile": 3, "bl_water_trough": 2}
		exclude.append("bl_spec_notice_board")
	counts.merge(prm.get("prop_counts", {}), true)
	var specs := []
	for it in PWAssetLibrary.blender_with_tags(["plaza", "roadside", "yard"], exclude):
		if it.get("semantic", "") in ["trees", "buildings", "landmarks"]:
			continue
		if not PWAssetLibrary.fits_climate(it, w.theme):
			continue
		# 风格专属的道具（modern / medieval / cn_village 标签）只出现在对应风格里
		var tags: Array = it.get("tags", [])
		var styled := false
		for st in ["modern", "medieval", "cn_village"]:
			if st in tags and st != style_tag:
				styled = true
		if styled:
			continue
		var fp: Array = it.get("footprint", [2, 2])
		specs.append([it, counts.get(it.id, rng.randi_range(1, 2)), maxf(1.6, float(fp[1]) * 0.5 + 0.9)])
	for spec: Array in specs:
		var item: Dictionary = spec[0]
		var placed := 0
		for attempt in 60:
			if placed >= spec[1]:
				break
			var r: Rect2 = roads[rng.randi_range(0, roads.size() - 1)]
			var horiz := r.size.x >= r.size.y
			var side := -1 if rng.randf() < 0.5 else 1
			var depth: float = spec[2]
			var p: Vector2
			var to_road: Vector2
			if horiz:
				p = Vector2(rng.randf_range(r.position.x + 3.0, r.end.x - 3.0), (r.position.y - depth) if side < 0 else (r.end.y + depth))
				to_road = Vector2(0, 1) if side < 0 else Vector2(0, -1)
			else:
				p = Vector2((r.position.x - depth) if side < 0 else (r.end.x + depth), rng.randf_range(r.position.y + 3.0, r.end.y - 3.0))
				to_road = Vector2(1, 0) if side < 0 else Vector2(-1, 0)
			var mesh: Mesh = item.build.call(rng.randi_range(0, 7))
			var a := mesh.get_aabb()
			var half := Vector2(maxf(absf(a.position.x), absf(a.end.x)), maxf(absf(a.position.z), absf(a.end.z)))
			var ext := half if horiz else Vector2(half.y, half.x)
			var rect := Rect2(p - ext, ext * 2.0)
			if not on_land(rect, 1.5) or on_road(rect.get_center(), 0.6) or not pl.can_place_rect(P.PROP, rect, 0.0, true):
				continue
			# 模型正面朝 +Z：转到朝向道路
			var yaw := atan2(to_road.x, to_road.y)
			batch.add_static(mesh, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0, p.y)))
			pl.add_rect(P.PROP, rect, 0.0, true)
			pl.solid_rects.append(rect)
			placed += 1
		w.stats[String(item.id)] = placed


## 草坪：密度 0.45，北边林带下 0.25；岸边碎石带和湖里没有；路、房子、门前通道等由 PWPlacement 排除
func _build_grass() -> void:
	var dens := func(p: Vector2) -> float:
		if w.with_lake and p.y > shore(p.x) - 1.2:
			return 0.0
		return 0.25 if p.y < -H + 12.0 else 0.45
	var dry := func(p: Vector2) -> float:
		return clampf(1.0 - (shore(p.x) - 1.2 - p.y) / 3.0, 0.0, 1.0) * 0.6 if w.with_lake else 0.0
	var budget := int(2600.0 * (w.size / 80.0) * (w.size / 80.0))
	w.stats["grass"] = PWGrass.scatter(pl, batch, rng, dens, func(p: Vector2) -> float: return 0.0, dry,
		{"half": H - 0.6, "budget": budget, "flowers": 0.12})


func _build_bushes_and_rocks() -> void:
	var n := int(w.size * w.size * 0.006 * w.bush_density)
	var placed := 0
	for i in n * 20:
		if placed >= n:
			break
		var p := Vector2(rng.randf_range(-H + 1.0, H - 1.0), rng.randf_range(-H + 1.0, H - 1.0))
		if w.with_lake and p.y > shore(p.x) - 1.5:
			continue
		if _try_bush(p, rng.randf_range(0.7, 1.1)):
			placed += 1
	for i in int(w.size * 0.5):
		var x := rng.randf_range(-H + 1.0, H - 1.0)
		var p := Vector2(x, shore(x) - rng.randf_range(0.4, 1.4)) if w.with_lake and i % 2 == 0 \
			else Vector2(x, rng.randf_range(-H + 1.0, -H + 14.0))
		var mesh := _rocks[rng.randi_range(0, _rocks.size() - 1)]
		var s := rng.randf_range(0.7, 1.4)
		var r: float = _canopy[mesh] * s
		if not pl.can_place(P.ROCK, p, r):
			continue
		batch.add_plant(mesh, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.1), s)), Vector3(p.x, 0, p.y)), tint(0.08))
		pl.add_circle(P.ROCK, p, r)
		pl.solid_circles.append(Vector3(p.x, p.y, r * 0.8))


# ---------------------------------------------------------------- 湖里

func _build_lake_life() -> void:
	var weeds := weed_variants()
	for i in int(w.size * 1.1):
		var x := rng.randf_range(-H, H)
		var d := rng.randf_range(1.6, 7.0)
		var p := Vector2(x, shore(x) + d)
		if _pier.grow(0.8).has_point(p):
			continue
		var s := rng.randf_range(0.8, 1.5)
		batch.add_plant(weeds[i % weeds.size()], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, w.terrain_y(p.x, p.y), p.y)))
	for i in int(w.size * 0.35):
		var x := rng.randf_range(-H, H)
		var p := Vector2(x, shore(x) + rng.randf_range(1.4, 8.0))
		if _pier.grow(0.8).has_point(p):
			continue
		var s := rng.randf_range(0.8, 1.9)
		batch.add_plant(_rocks[i % _rocks.size()], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.7, s)), Vector3(p.x, w.terrain_y(p.x, p.y) - 0.05, p.y)))
	var smin := INF
	var smax := -INF
	var x := -H
	while x <= H:
		smin = minf(smin, shore(x))
		smax = maxf(smax, shore(x))
		x += 1.0
	w.add_fish(Rect2(-H + 2.0, smin + 1.8, H * 2.0 - 4.0, smax - smin + 3.6), int(w.size * 0.22))
