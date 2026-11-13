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


func _init(world: PWWorld, r: RandomNumberGenerator, b: PWBatcher) -> void:
	w = world
	rng = r
	batch = b
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
	var curb_gaps: Array[Rect2] = []
	if w.with_lake:
		curb_gaps.append(_build_path_and_pier())
		_build_lighthouse()
	_build_curbs(curb_gaps)
	_build_houses()
	_build_lamps()
	_build_benches()
	_build_blender_props()
	_build_trees()
	_build_bushes_and_rocks()
	_build_grass()
	if w.with_lake:
		_build_lake_life()
	var sp := Vector2(_path_x, _path_top + 3.0) if w.with_lake else roads[0].get_center()
	# 出生点必须能站人：沿土路（或主街）往前找第一个空地
	for k in 40:
		if w.can_stand(sp):
			break
		sp += Vector2(0, 0.5) if w.with_lake else Vector2(0.5, 0)
	w.spawn_point = Vector3(sp.x, w.ground_y(sp.x, sp.y), sp.y)
	for c in [P.HOUSE, P.LAMP, P.TREE, P.BUSH, P.ROCK, P.FENCE, P.BENCH, P.ROAD]:
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
	var mb := MB.new()
	var y := 0.02
	for r in roads:
		mb.face("cobble", [Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y),
			Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y)], Vector3.UP)
		pl.add_rect(P.ROAD, r)
	batch.add_static(mb.commit(), Transform3D.IDENTITY, false)


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
	var curb := MB.new()
	for r in roads:
		var horiz := r.size.x >= r.size.y
		for side in [-1, 1]:
			var strip: Rect2
			if horiz:
				strip = Rect2(r.position.x, r.position.y - CURB if side < 0 else r.end.y, r.size.x, CURB)
			else:
				strip = Rect2(r.position.x - CURB if side < 0 else r.end.x, r.position.y, CURB, r.size.y)
			var cuts: Array[Vector2] = []
			for o in roads + extra_gaps:
				if o == r:
					continue
				var g := o.grow(0.3)
				if g.intersects(strip):
					cuts.append(Vector2(g.position.x, g.end.x) if horiz else Vector2(g.position.y, g.end.y))
			for seg in _subtract(Vector2(strip.position.x, strip.end.x) if horiz else Vector2(strip.position.y, strip.end.y), cuts):
				if seg.y - seg.x < 0.4:
					continue
				var s := Rect2(seg.x, strip.position.y, seg.y - seg.x, CURB) if horiz else Rect2(strip.position.x, seg.x, CURB, seg.y - seg.x)
				curb.box("curb", Vector3(s.position.x, 0, s.position.y), Vector3(s.end.x, CURB_H, s.end.y))
	batch.add_static(curb.commit(), Transform3D.IDENTITY)


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
	var crate := Props.build_crate()
	var barrel := Props.build_barrel()
	var spots := [[crate, Vector2(_path_x + 2.6, z_end - 1.6)], [crate, Vector2(_path_x + 3.4, z_end - 0.8)],
		[barrel, Vector2(_path_x - 2.6, z_end - 1.2)], [barrel, Vector2(_path_x - 3.2, z_end - 2.0)],
		[barrel, Vector2(_path_x + 0.6, z_end + 4.5)]]
	for s: Array in spots:
		var p: Vector2 = s[1]
		var on_pier := _pier.has_point(p)
		if on_pier or pl.can_place(P.PROP, p, 0.45):
			batch.add_static(s[0], Transform3D(Basis(Vector3.UP, rng.randf() * 0.8), Vector3(p.x, 0.05 if on_pier else 0.0, p.y)))
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
		batch.add_static(Props.build_lighthouse(), Transform3D(Basis(), Vector3(c.x, 0, c.y)))
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
				var p := House.random_params(rng)
				var fp := House.footprint(p)
				var yard := rng.randf_range(2.6, 3.4)
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
	batch.add_static(House.build(p), Transform3D(basis, Vector3(center.x, 0, center.y)))
	pl.add_rect(P.HOUSE, rect, 0.3, true)
	pl.add_rect(P.DOOR, door)
	var body := Vector2(p.width + 0.5, p.depth + 0.5) if horiz else Vector2(p.depth + 0.5, p.width + 0.5)
	pl.solid_rects.append(Rect2(center - body * 0.5, body))
	# 篱笆：沿前院靠路一侧，门口留缺口
	if rng.randf() < 0.55:
		_house_fence(basis, center, fp, yard)
	# 门两侧的灌木
	for sx in [-1.0, 1.0]:
		if rng.randf() < 0.7:
			var lx: float = sx * rng.randf_range(1.6, maxf(1.7, p.width * 0.5 - 0.5))
			var wp3 := basis * Vector3(lx, 0, p.depth * 0.5 + 0.7)
			_try_bush(Vector2(center.x + wp3.x, center.y + wp3.z), rng.randf_range(0.8, 1.1))
	return true


func _house_fence(basis: Basis, center: Vector2, fp: Vector2, yard: float) -> void:
	var style: String = Props.FENCE_STYLES[rng.randi_range(0, Props.FENCE_STYLES.size() - 1)]
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
	batch.add_static(Props.build_fence(half * 2.0, [gap], style), Transform3D(basis, Vector3(center.x + origin3.x, 0, center.y + origin3.z)))
	for rr in rects:
		pl.add_rect(P.FENCE, rr)
		pl.solid_rects.append(rr)


# ---------------------------------------------------------------- 路灯、长椅

func _build_lamps() -> void:
	var lamp_meshes := {}
	var pool := PlaneMesh.new()
	pool.size = Vector2(5, 5)
	var pm := ShaderMaterial.new()
	pm.shader = POOL_SHADER
	pool.material = pm
	var pools: Array[Transform3D] = []
	for r in roads:
		var horiz := r.size.x >= r.size.y
		var length := r.size.x if horiz else r.size.y
		var n := int(length / w.lamp_spacing)
		for i in n:
			for side in [-1, 1]:
				# 两侧交错：一侧在格点上，另一侧在半格处
				var t := (i + (0.5 if side > 0 else 0.0) + 0.25) * w.lamp_spacing
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
				if not on_land(Rect2(p - Vector2.ONE * 0.3, Vector2.ONE * 0.6), 1.0):
					continue
				if not pl.can_place(P.LAMP, p, 0.22, canopy, true):
					continue
				var metal: String = Trees.LAMP_METALS[rng.randi_range(0, Trees.LAMP_METALS.size() - 1)]
				var key := style + "/" + metal
				if not lamp_meshes.has(key):
					lamp_meshes[key] = Trees.build_lamp(style, metal)
				# 局部 +X 朝路（悬臂灯的灯头伸向路面）：绕 Y 转 θ 后 +X → (cosθ, 0, -sinθ)
				var yaw := atan2(-to_road.y, to_road.x)
				var basis := Basis(Vector3.UP, yaw)
				batch.add_static(lamp_meshes[key], Transform3D(basis, Vector3(p.x, 0, p.y)))
				pl.add_circle(P.LAMP, p, 0.22, canopy, true)
				pl.solid_circles.append(Vector3(p.x, p.y, 0.25))
				pools.append(Transform3D(Basis(), Vector3(p.x, 0.04, p.y) + basis * Trees.lamp_light_offset(style)))
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


func _build_benches() -> void:
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
		var style: String = Props.BENCH_STYLES[rng.randi_range(0, Props.BENCH_STYLES.size() - 1)]
		if not benches.has(style):
			benches[style] = Props.build_bench(style)
		# 长椅局部 +Z 是正面：朝向道路
		var yaw := atan2(to_road.x, to_road.y)
		batch.add_static(benches[style], Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0, p.y)))
		pl.add_rect(P.BENCH, rect)
		pl.solid_rects.append(rect)


# ---------------------------------------------------------------- 植被

var _pines: Array[ArrayMesh] = []
var _broads: Array[ArrayMesh] = []
var _bushes: Array[ArrayMesh] = []
var _rocks: Array[ArrayMesh] = []
var _canopy := {}  # Mesh -> 树冠半径


func _variants() -> void:
	if not _pines.is_empty():
		return
	for i in 10:
		_pines.append(Trees.build_pine(1000 + i))
	var styles := ["oak", "oak", "birch", "poplar", "oak", "birch", "poplar", "oak", "oak", "birch", "poplar", "oak"]
	for i in styles.size():
		_broads.append(Trees.build_broadleaf(2000 + i, styles[i]))
	for i in 8:
		_bushes.append(Trees.build_bush(3000 + i))
	for i in 8:
		_rocks.append(Trees.build_rock(4000 + i))
	for m in _pines + _broads + _bushes + _rocks:
		var a := m.get_aabb()
		_canopy[m] = maxf(maxf(absf(a.position.x), absf(a.end.x)), maxf(absf(a.position.z), absf(a.end.z)))


func tint(amount: float) -> Color:
	var k := rng.randf_range(1.0 - amount, 1.0 + amount * 0.6)
	return Color(k * rng.randf_range(0.95, 1.05), k * rng.randf_range(0.96, 1.04), k * rng.randf_range(0.93, 1.05), 1.0)


## 放一棵树（任意朝向、宽高比例、色调）；能放返回 true
func try_tree(p: Vector2, mesh: ArrayMesh, s: float, pine: bool) -> bool:
	var sxz := s * rng.randf_range(0.9, 1.1)
	var sy := s * rng.randf_range(0.9, 1.18)
	var canopy: float = _canopy[mesh] * sxz
	var trunk := 0.3 * sxz
	if not pl.can_place(P.TREE, p, trunk, canopy, true):
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
	if not pl.can_place(P.BUSH, p, r):
		return false
	var sy := s * rng.randf_range(0.85, 1.15)
	batch.add_plant(mesh, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, sy, s)), Vector3(p.x, 0, p.y)), tint(0.1))
	pl.add_circle(P.BUSH, p, r)
	pl.solid_circles.append(Vector3(p.x, p.y, r * 0.8))
	return true


func _build_trees() -> void:
	_variants()
	var attempts := int(w.size * w.size * 0.4 * w.tree_density)
	for i in attempts:
		var p := Vector2(rng.randf_range(-H + 1.0, H - 1.0), rng.randf_range(-H + 1.0, H - 1.0))
		if w.with_lake and p.y > shore(p.x) - 2.0:
			continue
		var belt := p.y < -H + 12.0  # 北边林带：更密，几乎全是松树
		if not belt and rng.randf() > 0.35:
			continue
		var pine := rng.randf() < (0.92 if belt else 0.55)
		var mesh: ArrayMesh = _pines[rng.randi_range(0, _pines.size() - 1)] if pine else _broads[rng.randi_range(0, _broads.size() - 1)]
		try_tree(p, mesh, rng.randf_range(0.75, 1.2), pine)


## Blender 资产（P3）：有资产目录时，在路边放一口石井和几个集市摊位（正面朝路），同样经过摆放规则检查
func _build_blender_props() -> void:
	if not PWAssetLibrary._blender_loaded:
		PWAssetLibrary.load_blender_catalog()
	var specs := [["bl_well", 1, 2.6], ["bl_market_stall", 3, 2.0]]
	for spec: Array in specs:
		var item: Dictionary = {}
		for it in PWAssetLibrary.in_category("blender"):
			if it.id == spec[0]:
				item = it
		if item.is_empty():
			continue
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
			if not on_land(rect, 1.5) or not pl.can_place_rect(P.PROP, rect, 0.0, true):
				continue
			# 模型正面朝 +Z：转到朝向道路
			var yaw := atan2(to_road.x, to_road.y)
			batch.add_static(mesh, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0, p.y)))
			pl.add_rect(P.PROP, rect, 0.0, true)
			pl.solid_rects.append(rect)
			placed += 1
		w.stats[String(spec[0])] = placed


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
	var weeds: Array[ArrayMesh] = [Props.build_weed(5000), Props.build_weed(5001), Props.build_weed(5002)]
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
