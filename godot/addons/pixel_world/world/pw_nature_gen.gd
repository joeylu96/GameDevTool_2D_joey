@tool
extends RefCounted
## 自然场景生成（PWWorld 风格 generator = "nature"：森林、平原……），参数来自 PWStyles。
##
## 1. 地形：起伏的丘陵（连续高度场，始终高于水面）
## 2. 水系：1~2 个大湖（不规则轮廓、由岸向湖心平滑变深）；主湖按概率接出一条蜿蜒的河，流出地图边缘。
##    水只出现在这里——不会再有散落的小水坑；沙滩只是湖岸、河岸的一圈窄带
## 3. 地表：草 / 沙 / 岩石 / 湖底按顶点权重在 shader 里混合（陡坡、高处露岩石）
## 4. 兴趣点：营地 / 木屋 / 废墟（森林），农舍 + 田地 / 风车 / 营地（平原）；脚下压平
## 5. 小路：A* 连接兴趣点（越陡、林子越密代价越高；湖不能过，河可以——过河处自动架木桥），
##    路径平滑成曲线，铺成贴地的带状路面，边缘略有起伏
## 6. 植被：树（森林：按湿度成片；平原：零星树丛 + 灌木篱）、灌木、石头、草（PWGrass 规则）
## 7. Blender 资产（含资产工坊生成的）：按风格参数 blender 里的标签挑选、按地表条件撒放
## 太陡的坡（每米升高 > 0.75 米）不可通行。
##
## 风格专用参数（PWStyles）：
##   island（海岛半径占半边地图的比例）：外圈沉进海里，留一圈宽沙滩
##   desert：绿洲以外全是沙地，只有湖边一圈有草和椰子树
##   canyon：台地（plateau 抬高）中间蜿蜒一条两级台阶的河谷，谷底有河
##   sand_h：沙滩的高度范围；terrain_mat：地形材质（terrain / terrain_desert / terrain_canyon）

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")
const Mats := preload("res://addons/pixel_world/core/pw_materials.gd")
const House := preload("res://addons/pixel_world/assets/placeholder/pw_house_builder.gd")
const Trees := preload("res://addons/pixel_world/assets/placeholder/pw_tree_builder.gd")
const Props := preload("res://addons/pixel_world/assets/placeholder/pw_props_builder.gd")
const P := preload("res://addons/pixel_world/world/pw_placement.gd")
const Town := preload("res://addons/pixel_world/world/pw_town_gen.gd")
const Spinner := preload("res://addons/pixel_world/world/pw_spinner.gd")

enum { WATER, SAND, GRASS, FOREST, ROCK }
const WATER_Y := -0.45
const LAND_MIN := 0.35     # 陆地最低处比水面高多少（低于这个的只有湖和河）
const LAKE_D := 3.0        # 湖心最深
const RIVER_D := 0.95      # 河道最深
const SAND_H := 0.22       # 水面以上这么高之内是沙滩
const STEEP := 0.75        # 每米升高超过这个就不可通行（约 37°）
const ROCK_SLOPE := 0.55   # 每米升高超过这个就露出岩石

var w: PWWorld
var rng: RandomNumberGenerator
var batch: PWBatcher
var pl: PWPlacement
var prm: Dictionary
var H := 64.0
var n := 0
var moisture := PackedFloat32Array()
var river_mask := PackedByteArray()
var lakes: Array[Dictionary] = []       # {c: Vector2, r: float, seed: float}
var river: PackedVector2Array = PackedVector2Array()
var pois: Array[Vector2] = []
var _poi_kinds: Array[String] = []
var _poi_r: Array[float] = []
var _jitter: FastNoiseLite
var _town: Object  # 借用小镇生成器里的树 / 灌木工具函数


func _init(world: PWWorld, r: RandomNumberGenerator, b: PWBatcher, params: Dictionary) -> void:
	w = world
	rng = r
	batch = b
	pl = world.placement
	prm = params
	H = world.size * 0.5


func run() -> void:
	w.water_y = WATER_Y
	w.terraced = false
	w.init_grid(H, 0.0)
	n = w.grid_n
	w.flow = PackedVector2Array()
	w.flow.resize((n + 1) * (n + 1))
	river_mask.resize((n + 1) * (n + 1))
	_make_heights()
	_choose_pois()          # 先选兴趣点并把脚下压平，再建地形网格
	_build_terrain_mesh()
	_mark_steep()
	_town = Town.new(w, rng, batch)
	_town._variants()
	for i in pois.size():
		_build_poi(_poi_kinds[i], pois[i])
		w.homes.append(Vector3(pois[i].x, 0.0, pois[i].y))  # 野外的 NPC 以营地 / 兴趣点为家
	_connect_paths()
	_scatter_trees()
	_scatter_blender()
	_scatter_small()
	_scatter_grass()
	_lake_life()
	if pois.is_empty():
		w.spawn_point = Vector3(0, w.ground_y(0, 0), 0)
	else:
		var s := pois[0] + Vector2(_poi_r[0] - 0.5, 0)
		w.spawn_point = Vector3(s.x, w.ground_y(s.x, s.y), s.y)
	for c in [P.LANDMARK, P.TREE, P.BUSH, P.ROCK, P.PATH]:
		w.stats[String(c)] = pl.count(c)
	w.stats["lakes"] = lakes.size()
	w.stats["river"] = river.size() > 1


func idx(i: int, j: int) -> int:
	return j * (n + 1) + i


# ---------------------------------------------------------------- 高度、湖、河

func _make_heights() -> void:
	var hn := FastNoiseLite.new()
	hn.seed = rng.randi()
	hn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hn.frequency = float(prm.get("hill_freq", 0.02))
	hn.fractal_octaves = 4
	var mn := FastNoiseLite.new()
	mn.seed = rng.randi()
	mn.frequency = 0.03
	_jitter = FastNoiseLite.new()
	_jitter.seed = rng.randi()
	_jitter.frequency = 0.35
	var amp: float = prm.get("hill_amp", 3.0)
	moisture.resize((n + 1) * (n + 1))
	# 1) 丘陵
	for j in n + 1:
		for i in n + 1:
			var p := w.vert_xz(i, j)
			var e := hn.get_noise_2d(p.x, p.y) * 0.5 + 0.5
			w.set_h(i, j, WATER_Y + LAND_MIN + float(prm.get("plateau", 0.0)) + amp * pow(e, 1.3))
			moisture[idx(i, j)] = mn.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	if float(prm.get("island", 0.0)) > 0.0:
		_shape_island(float(prm.island))
		_fill_puddles()
	if prm.get("canyon", false):
		_carve_canyon()
		return
	if not w.with_lake:
		return
	# 2) 湖：互不重叠、离地图边缘有余量
	var lr: Array = prm.get("lakes", [1, 1])
	var rr: Array = prm.get("lake_r", [12.0, 18.0])
	var want := rng.randi_range(lr[0], lr[1])
	var scale := w.size / 128.0
	for attempt in 80:
		if lakes.size() >= want:
			break
		var r := rng.randf_range(rr[0], rr[1]) * scale
		var m := r * 1.45 + 4.0
		var c := Vector2(rng.randf_range(-H + m, H - m), rng.randf_range(-H + m, H - m))
		var ok := true
		for l in lakes:
			if c.distance_to(l.c) < (r + l.r) * 1.5:
				ok = false
		if ok:
			lakes.append({"c": c, "r": r, "seed": rng.randf() * 100.0})
	for l in lakes:
		_carve_lake(l)
	# 3) 河：从最大的湖流向最近的地图边缘
	if not lakes.is_empty() and rng.randf() < float(prm.get("river_chance", 0.5)):
		var main: Dictionary = lakes[0]
		for l in lakes:
			if l.r > main.r:
				main = l
		_carve_river(main)


## 湖的轮廓半径（随角度起伏）
func _lake_radius(l: Dictionary, ang: float) -> float:
	var s: float = l.seed
	return l.r * (1.0 + 0.16 * sin(ang * 2.0 + s) + 0.1 * sin(ang * 3.0 + s * 1.7) + 0.06 * sin(ang * 5.0 + s * 0.3))


func _carve_lake(l: Dictionary) -> void:
	var c: Vector2 = l.c
	var reach: float = l.r * 1.9
	for j in n + 1:
		for i in n + 1:
			var p := w.vert_xz(i, j)
			var d := p - c
			if absf(d.x) > reach or absf(d.y) > reach:
				continue
			var t := d.length() / _lake_radius(l, atan2(d.y, d.x))
			if t >= 1.5:
				continue
			var base := w.get_h(i, j)
			var hl: float
			if t < 1.0:
				var k := 1.0 - t * t
				hl = WATER_Y - 0.06 - LAKE_D * k * (0.6 + 0.4 * k)
			else:
				hl = lerpf(WATER_Y - 0.06, base, smoothstep(1.0, 1.5, t))  # 湖岸缓坡
			w.set_h(i, j, minf(base, hl))


func _carve_river(l: Dictionary) -> void:
	var c: Vector2 = l.c
	# 最近的边
	var dirs := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	var dists := [H - c.x, H + c.x, H - c.y, H + c.y]
	var best := 0
	for k in 4:
		if dists[k] < dists[best]:
			best = k
	_trace_river(c, dirs[best])
	_carve_channel(rng.randf_range(2.0, 2.9) * clampf(w.size / 128.0, 0.7, 1.0))


## 河的中心线：从 start 出发，大致朝 target 方向蜿蜒，直到流出地图
func _trace_river(start: Vector2, target: Vector2) -> void:
	var heading := atan2(target.y, target.x) + rng.randf_range(-0.5, 0.5)
	var p := start
	var meander := FastNoiseLite.new()
	meander.seed = rng.randi()
	meander.frequency = 0.04
	river.append(p)
	var inside := absf(p.x) < H and absf(p.y) < H
	for step in 400:
		var want := atan2(target.y, target.x)
		heading = lerp_angle(heading, want, 0.12) + meander.get_noise_1d(step * 2.0) * 0.55
		p += Vector2(cos(heading), sin(heading)) * 2.0
		river.append(p)
		if absf(p.x) < H and absf(p.y) < H:
			inside = true
		elif inside and (absf(p.x) > H + 6.0 or absf(p.y) > H + 6.0):
			break


## 沿 river 中心线挖河道（半宽 hw，两岸 3.5 米缓坡），记录流向
func _carve_channel(hw: float) -> void:
	var bank := 3.5
	for j in n + 1:
		for i in n + 1:
			var q := w.vert_xz(i, j)
			var hit := _nearest_on_river(q)
			var d: float = hit[0]
			if d > hw + bank:
				continue
			var base := w.get_h(i, j)
			var hr: float
			if d < hw:
				var k := 1.0 - (d / hw) * (d / hw)
				hr = WATER_Y - 0.06 - RIVER_D * k
				river_mask[idx(i, j)] = 1
				# 流向：沿河道往下游
				w.flow[idx(i, j)] = (hit[1] as Vector2) * smoothstep(0.0, 0.6, k)
			else:
				hr = lerpf(WATER_Y - 0.06, base, smoothstep(hw, hw + bank, d))
			if hr < base:
				w.set_h(i, j, hr)


## 返回 [到河道中心线的距离, 该处的流向（单位向量）]
func _nearest_on_river(q: Vector2, reach := 8.0) -> Array:
	var best := INF
	var dir := Vector2.ZERO
	for k in river.size() - 1:
		var a := river[k]
		var b := river[k + 1]
		if absf(q.x - a.x) > reach and absf(q.y - a.y) > reach:
			continue
		var ab := b - a
		var t := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := q.distance_to(a + ab * t)
		if d < best:
			best = d
			dir = ab.normalized()
	return [best, dir]


## 顶点处的坡度（每米升高多少米）
func slope_at(i: int, j: int) -> float:
	var dx := (w.get_h(i + 1, j) - w.get_h(i - 1, j)) * 0.5
	var dz := (w.get_h(i, j + 1) - w.get_h(i, j - 1)) * 0.5
	return Vector2(dx, dz).length() / w.cell


func slope(p: Vector2) -> float:
	var e := 0.5
	var dx := (w.terrain_y(p.x + e, p.y) - w.terrain_y(p.x - e, p.y)) / (2.0 * e)
	var dz := (w.terrain_y(p.x, p.y + e) - w.terrain_y(p.x, p.y - e)) / (2.0 * e)
	return Vector2(dx, dz).length()


func _moist(p: Vector2) -> float:
	var g := (p - w.origin) / w.cell
	return moisture[idx(clampi(int(round(g.x)), 0, n), clampi(int(round(g.y)), 0, n))]


## 某处的地表类型
func biome_at(p: Vector2) -> int:
	var h := w.terrain_y(p.x, p.y)
	var j := _jitter.get_noise_2d(p.x, p.y)
	if h < WATER_Y:
		return WATER
	if prm.get("desert", false):
		if slope(p) > ROCK_SLOPE + j * 0.15:
			return ROCK
		var ot := _oasis_t(p) + j * 0.12
		if ot < float(prm.get("oasis", 1.9)) and h > WATER_Y + 0.12:
			return FOREST if ot < 1.35 else GRASS
		return SAND
	if h < WATER_Y + _sand_h() + j * 0.08 or (float(prm.get("island", 0.0)) > 0.0 and h < WATER_Y + _sand_h() + 0.35):
		return SAND
	var amp: float = prm.get("hill_amp", 3.0)
	if slope(p) > ROCK_SLOPE + j * 0.15 or h > WATER_Y + LAND_MIN + float(prm.get("plateau", 0.0)) + amp * 0.82 + j * 0.3:
		return ROCK
	return FOREST if _moist(p) + j * 0.05 > float(prm.get("forest_cover", 0.5)) else GRASS


# ---------------------------------------------------------------- 地形网格

## 整片地形一个网格、一个材质（"terrain"）：每个顶点存沙 / 岩石 / 湖底的权重（顶点色 RGB），
## shader 里按权重混合，交界清晰但形状不规则。顶点法线由相邻高度差算出，光照连续
func _build_terrain_mesh() -> void:
	var count := (n + 1) * (n + 1)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	verts.resize(count)
	normals.resize(count)
	uvs.resize(count)
	cols.resize(count)
	var amp: float = prm.get("hill_amp", 3.0)
	for j in n + 1:
		for i in n + 1:
			var k := idx(i, j)
			var xz := w.vert_xz(i, j)
			var h := w.get_h(i, j)
			var dx := (w.get_h(i + 1, j) - w.get_h(i - 1, j)) * 0.5
			var dz := (w.get_h(i, j + 1) - w.get_h(i, j - 1)) * 0.5
			verts[k] = Vector3(xz.x, h, xz.y)
			normals[k] = Vector3(-dx, w.cell, -dz).normalized()
			uvs[k] = xz
			var above := h - WATER_Y
			var sand := 1.0 - smoothstep(_sand_h() - 0.1, _sand_h() + 0.1, above)
			if prm.get("desert", false):  # 绿洲以外全是沙
				sand = maxf(sand, smoothstep(float(prm.get("oasis", 1.9)) - 0.35, float(prm.get("oasis", 1.9)) + 0.05,
					_oasis_t(xz) + _jitter.get_noise_2d(xz.x, xz.y) * 0.12))
			var bed := smoothstep(0.45, 0.95, -above)
			var sl := slope_at(i, j)
			var rock := maxf(smoothstep(ROCK_SLOPE - 0.12, ROCK_SLOPE + 0.12, sl),
				smoothstep(LAND_MIN + float(prm.get("plateau", 0.0)) + amp * 0.75, LAND_MIN + float(prm.get("plateau", 0.0)) + amp * 0.9, above))
			if above < 0.0 or (float(prm.get("island", 0.0)) > 0.0 and above < _sand_h() + 0.35):
				rock = 0.0  # 海岛的海岸是沙滩落进海里，不露岩石
			cols[k] = Color(sand, rock, bed, 1.0)
	var indices := PackedInt32Array()
	for j in n:
		for i in n:
			var a := idx(i, j)
			var b := idx(i + 1, j)
			var c := idx(i + 1, j + 1)
			var d := idx(i, j + 1)
			if absf(verts[a].y - verts[c].y) <= absf(verts[b].y - verts[d].y):
				indices.append_array([a, b, c, a, c, d])
			else:
				indices.append_array([a, b, d, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, Mats.get_mat(String(prm.get("terrain_mat", "terrain"))))
	batch.add_static(mesh, Transform3D.IDENTITY, false)
	# 水域登记（树、兴趣点、草不进水）
	for j in range(0, n + 1, 2):
		for i in range(0, n + 1, 2):
			if w.get_h(i, j) < WATER_Y + 0.05:
				var p := w.vert_xz(i, j)
				pl.add_rect(P.WATER, Rect2(p - Vector2.ONE * 1.2, Vector2.ONE * 2.4))


func _mark_steep() -> void:
	w.walk_block = PackedByteArray()
	w.walk_block.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			if w.get_h(i, j) > WATER_Y and slope_at(i, j) > STEEP:
				w.walk_block[idx(i, j)] = 1


# ---------------------------------------------------------------- 兴趣点

func gentle(p: Vector2, r: float, max_slope: float) -> bool:
	for d in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r),
			Vector2(r, r) * 0.7, Vector2(-r, r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, -r) * 0.7]:
		var q: Vector2 = p + d
		if absf(q.x) > H - 1.0 or absf(q.y) > H - 1.0:
			return false
		if w.terrain_y(q.x, q.y) < WATER_Y + _sand_h() + 0.1 or slope(q) > max_slope:
			return false
	return true


func _poi_radius(kind: String) -> float:
	return {"farm": 9.0, "windmill": 5.5}.get(kind, 4.5)


func _choose_pois() -> void:
	var kinds: Array = prm.get("pois", ["camp"])
	var want := kinds.size() if w.size > 96 else mini(kinds.size(), 3)
	var min_gap := w.size * 0.26
	for attempt in 900:
		if pois.size() >= want:
			break
		var kind: String = kinds[pois.size()]
		var r := _poi_radius(kind)
		var p := Vector2(rng.randf_range(-H + r + 5.0, H - r - 5.0), rng.randf_range(-H + r + 5.0, H - r - 5.0))
		var too_close := false
		for q in pois:
			if q.distance_to(p) < min_gap:
				too_close = true
		if too_close or not gentle(p, r + 0.5, 0.3):
			continue
		var rect := Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
		if not pl.can_place_rect(P.LANDMARK, rect, 0.0, true):
			continue
		pl.add_rect(P.LANDMARK, rect, 0.0, true)
		_flatten(p, r, r + 3.5)
		_poi_kinds.append(kind)
		_poi_r.append(r)
		pois.append(p)


func _flatten(p: Vector2, r_flat: float, r_blend: float) -> void:
	var y := w.terrain_y(p.x, p.y)
	var g := (p - w.origin) / w.cell
	var rr := int(ceil(r_blend / w.cell)) + 1
	for j in range(int(g.y) - rr, int(g.y) + rr + 1):
		for i in range(int(g.x) - rr, int(g.x) + rr + 1):
			if i < 0 or j < 0 or i > n or j > n:
				continue
			var d := w.vert_xz(i, j).distance_to(p)
			if d >= r_blend:
				continue
			var k := 1.0 - smoothstep(r_flat, r_blend, d)
			w.set_h(i, j, lerpf(w.get_h(i, j), y, k))


func _build_poi(kind: String, p: Vector2) -> void:
	var y := w.ground_y(p.x, p.y)
	match kind:
		"cabin":
			# 林间小屋：Blender 农舍里挑一个不太大的（宽 ≤ 6.5 米）；没有 Blender 资产时用代码版
			var yaw := rng.randi_range(0, 3) * PI * 0.5
			var ck := _cottage(6.5)
			var sz := Vector2(6.0, 5.0)
			if ck >= 0:
				var vi: Dictionary = PWAssetLibrary.blender_variant_info("bl_cottage")[ck]
				sz = Vector2(float(vi.width), float(vi.depth))
				batch.add_static(_town.bl("bl_cottage")[ck], Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y)))
			else:
				var hp := House.random_params(rng)
				hp.width = 6.0
				hp.depth = 5.0
				hp.floors = 1
				hp.wall = "wall_wood"
				hp.chimney = true
				batch.add_static(House.build(hp), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y)))
			sz += Vector2(0.5, 0.5)
			var body := sz if int(round(yaw / (PI * 0.5))) % 2 == 0 else Vector2(sz.y, sz.x)
			pl.solid_rects.append(Rect2(p - body * 0.5, body))
		"farm":
			# 农舍 + 一块用木栏围起来的田（里面有草垛），农舍门朝田
			# Blender 农舍里最大的一个（约 8 × 6 米），房子正面贴着田边
			var ck := _cottage(99.0, true)
			var sz := Vector2(8.0, 6.0)
			var hc := p + Vector2(-4.0, -3.0)
			if ck >= 0:
				var vi: Dictionary = PWAssetLibrary.blender_variant_info("bl_cottage")[ck]
				sz = Vector2(float(vi.width), float(vi.depth))
				hc = p + Vector2(-4.0, -sz.y * 0.5)
				batch.add_static(_town.bl("bl_cottage")[ck], Transform3D(Basis(), Vector3(hc.x, y, hc.y)))
			else:
				var hp := House.random_params(rng)
				hp.width = 8.0
				hp.depth = 6.0
				hp.wall = ["wall_red", "wall_ochre", "wall_wood"][rng.randi_range(0, 2)]
				batch.add_static(House.build(hp), Transform3D(Basis(), Vector3(hc.x, y, hc.y)))
			pl.solid_rects.append(Rect2(hc - sz * 0.5 - Vector2(0.25, 0.25), sz + Vector2(0.5, 0.5)))
			var field := Rect2(p + Vector2(-8.0, 2.0), Vector2(16.0, 6.5))
			if _town.bl("bl_fence").is_empty():
				var fence := Props.build_fence(field.size.x, [[field.size.x * 0.5 - 1.0, field.size.x * 0.5 + 1.0]], "rail")
				var side := Props.build_fence(field.size.y, [], "rail")
				batch.add_static(fence, Transform3D(Basis(), Vector3(field.position.x, y, field.position.y)))
				batch.add_static(Props.build_fence(field.size.x, [], "rail"), Transform3D(Basis(), Vector3(field.position.x, y, field.end.y)))
				batch.add_static(side, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(field.position.x, y, field.position.y)))
				batch.add_static(side, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(field.end.x, y, field.position.y)))
			else:
				# Blender 木栏：前边中间留 2 米的门
				var o := Vector3(field.position.x, y, field.position.y)
				var half := field.size.x * 0.5
				_town.fence_run(Transform3D(Basis(), o), half - 1.0, 1)
				_town.fence_run(Transform3D(Basis(), o + Vector3(half + 1.0, 0, 0)), half - 1.0, 1)
				_town.fence_run(Transform3D(Basis(), Vector3(field.position.x, y, field.end.y)), field.size.x, 1)
				_town.fence_run(Transform3D(Basis(Vector3.UP, -PI * 0.5), o), field.size.y, 1)
				_town.fence_run(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(field.end.x, y, field.position.y)), field.size.y, 1)
			for rct in [Rect2(field.position.x, field.end.y - 0.15, field.size.x, 0.3),
					Rect2(field.position.x - 0.15, field.position.y, 0.3, field.size.y),
					Rect2(field.end.x - 0.15, field.position.y, 0.3, field.size.y)]:
				pl.solid_rects.append(rct)
			for k in rng.randi_range(3, 5):
				var hs := field.position + Vector2(rng.randf_range(1.5, field.size.x - 1.5), rng.randf_range(1.5, field.size.y - 1.5))
				batch.add_static(_haystack(), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(hs.x, y, hs.y)))
				pl.solid_circles.append(Vector3(hs.x, hs.y, 1.0))
		"windmill":
			batch.add_static(_town.bl_pick("bl_windmill_tower", Props.build_windmill_tower), Transform3D(Basis(), Vector3(p.x, y, p.y)))
			var blades := MeshInstance3D.new()
			blades.mesh = _town.bl_pick("bl_windmill_blades", Props.build_windmill_blades)
			blades.set_script(Spinner)
			blades.set("speed", 0.6)
			blades.position = Vector3(p.x, y, p.y) + Props.windmill_hub()
			w.content().add_child(blades)
			pl.solid_circles.append(Vector3(p.x, p.y, 2.3))
			for k in 2:
				var hs := p + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(2.5, 4.5))
				batch.add_static(_haystack(), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(hs.x, y, hs.y)))
				pl.solid_circles.append(Vector3(hs.x, hs.y, 1.0))
		"ruins":
			var mb := MB.new()
			for k in rng.randi_range(4, 6):
				var a := rng.randf() * TAU
				var c := p + Vector2(cos(a), sin(a)) * rng.randf_range(1.0, 3.0)
				var horiz := rng.randf() < 0.5
				var len := rng.randf_range(1.2, 3.0)
				var hh := rng.randf_range(0.5, 2.2)
				var half := Vector2(len * 0.5, 0.25) if horiz else Vector2(0.25, len * 0.5)
				mb.box("stone", Vector3(c.x - half.x, y - 0.2, c.y - half.y), Vector3(c.x + half.x, y + hh, c.y + half.y))
				if hh > 1.0:
					var s := half * Vector2(0.6, 0.6) if horiz else half * Vector2(1.0, 0.6)
					mb.box("stone", Vector3(c.x - s.x, y + hh, c.y - s.y), Vector3(c.x + s.x * 0.4, y + hh + 0.4, c.y + s.y * 0.4))
				pl.solid_rects.append(Rect2(c - half, half * 2.0))
			batch.add_static(mb.commit(), Transform3D(Basis(), Vector3.ZERO))
		_:
			# 营地：石圈篝火（夜里发光）+ 原木凳 + 货物
			var fire := MB.new()
			for k in 7:
				var a := TAU * k / 7.0
				fire.ngon_frustum("rock", Vector3(p.x + cos(a) * 0.55, 0, p.y + sin(a) * 0.55), y - 0.05, y + 0.18, 0.14, 0.1, 5, a, true)
			fire.tube("trunk", Vector3(p.x - 0.35, y + 0.08, p.y - 0.1), Vector3(p.x + 0.35, y + 0.12, p.y + 0.1), 0.06, 0.06, 6)
			fire.tube("trunk", Vector3(p.x - 0.1, y + 0.08, p.y + 0.35), Vector3(p.x + 0.1, y + 0.12, p.y - 0.35), 0.06, 0.06, 6)
			fire.ngon_frustum("bulb", Vector3(p.x, 0, p.y), y + 0.1, y + 0.45, 0.16, 0.0, 5, 0.0, false)
			batch.add_static(fire.commit(), Transform3D.IDENTITY)
			pl.solid_circles.append(Vector3(p.x, p.y, 0.7))
			var bb: Array[Mesh] = _town.bl("bl_bench")
			var bench: Mesh = bb[2 % bb.size()] if not bb.is_empty() else Props.build_bench("log")
			for k in 3:
				var a := TAU * k / 3.0 + rng.randf() * 0.5
				var bp := p + Vector2(cos(a), sin(a)) * 2.0
				batch.add_static(bench, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(bp.x, w.ground_y(bp.x, bp.y), bp.y)))
				pl.solid_circles.append(Vector3(bp.x, bp.y, 0.6))
			var cp := p + Vector2(2.8, -2.4)
			batch.add_static(_town.bl_pick("bl_crate", Props.build_crate), Transform3D(Basis(Vector3.UP, 0.3), Vector3(cp.x, w.ground_y(cp.x, cp.y), cp.y)))
			batch.add_static(_town.bl_pick("bl_barrel", Props.build_barrel), Transform3D(Basis(), Vector3(cp.x + 0.9, w.ground_y(cp.x + 0.9, cp.y + 0.4), cp.y + 0.4)))
			pl.solid_circles.append(Vector3(cp.x + 0.4, cp.y, 0.8))


## Blender 农舍里挑一个：宽度不超过 max_w 的随机一个；biggest = true 时挑最宽的。没有 Blender 资产返回 -1
func _cottage(max_w: float, biggest := false) -> int:
	var info := PWAssetLibrary.blender_variant_info("bl_cottage")
	if info.is_empty() or info.size() != _town.bl("bl_cottage").size():
		return -1
	var ok: Array[int] = []
	var best := 0
	for i in info.size():
		if float(info[i].width) <= max_w:
			ok.append(i)
		if float(info[i].width) > float(info[best].width):
			best = i
	if biggest:
		return best
	return ok[rng.randi_range(0, ok.size() - 1)] if not ok.is_empty() else best


func _haystack() -> Mesh:
	var v: Array[Mesh] = _town.bl("bl_haystack")
	return v[rng.randi_range(0, v.size() - 1)] if not v.is_empty() else Props.build_haystack(rng.randi())


# ---------------------------------------------------------------- 小路（A* + 平滑 + 带状路面 + 木桥）

func _cell_of(p: Vector2) -> Vector2i:
	var g := (p - w.origin) / w.cell
	return Vector2i(clampi(int(round(g.x)), 0, n), clampi(int(round(g.y)), 0, n))


func _connect_paths() -> void:
	if pois.size() < 2:
		return
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n + 1, n + 1)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for j in n + 1:
		for i in n + 1:
			var h := w.get_h(i, j)
			var c := Vector2i(i, j)
			if h < WATER_Y + 0.05:
				# 河可以架桥过去（代价高，尽量走最短的过河处）；湖不能过
				if river_mask[idx(i, j)] != 0:
					astar.set_point_weight_scale(c, 18.0)
				else:
					astar.set_point_solid(c, true)
			elif w.walk_block[idx(i, j)] != 0:
				astar.set_point_solid(c, true)
			else:
				var b := biome_at(w.vert_xz(i, j))
				astar.set_point_weight_scale(c, 1.0 + slope_at(i, j) * 6.0 + (1.5 if b == FOREST else 0.0) + (2.0 if b == ROCK else 0.0))
	var connected: Array[int] = [0]
	var left: Array[int] = []
	for k in range(1, pois.size()):
		left.append(k)
	while not left.is_empty():
		var ba := 0
		var bb := 0
		var bd := INF
		for a in connected:
			for b in left:
				var d := pois[a].distance_to(pois[b])
				if d < bd:
					bd = d
					ba = a
					bb = b
		var from := pois[ba] + (pois[bb] - pois[ba]).normalized() * (_poi_r[ba] - 0.5)
		var to := pois[bb] + (pois[ba] - pois[bb]).normalized() * (_poi_r[bb] - 0.5)
		var cells := astar.get_id_path(_cell_of(from), _cell_of(to))
		if cells.size() > 1:
			var pts := PackedVector2Array()
			pts.append(from)
			for c in cells:
				pts.append(w.vert_xz(c.x, c.y))
			pts.append(to)
			_build_path(_smooth(pts))
		connected.append(bb)
		left.erase(bb)


## 每隔一个点取样，再做两次 Chaikin 细分：网格上的直角折线变成圆滑曲线
static func _smooth(pts: PackedVector2Array) -> PackedVector2Array:
	var s := PackedVector2Array()
	for k in pts.size():
		if k % 2 == 0 or k == pts.size() - 1:
			s.append(pts[k])
	for it in 3:
		var o := PackedVector2Array()
		o.append(s[0])
		for k in s.size() - 1:
			o.append(s[k].lerp(s[k + 1], 0.25))
			o.append(s[k].lerp(s[k + 1], 0.75))
		o.append(s[s.size() - 1])
		s = o
	return s


## 带状路面：沿曲线每 0.5 米一段，宽约 1.5 米（边缘随噪声起伏），每个点都贴着地形；
## 经过水面的连续一段改成木桥
func _build_path(pts: PackedVector2Array) -> void:
	# 重新按 0.5 米等距采样
	var even := PackedVector2Array()
	even.append(pts[0])
	var carry := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var seg := a.distance_to(b)
		var t := 0.5 - carry
		while t <= seg:
			even.append(a.lerp(b, t / seg))
			t += 0.5
		carry = seg - (t - 0.5)
	if even.size() < 2:
		return
	var mb := MB.new()
	var wet: Array[bool] = []
	for p in even:
		wet.append(w.terrain_y(p.x, p.y) < WATER_Y + 0.08)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var has_prev := false
	var k := 0
	while k < even.size():
		if wet[k]:
			# 找到这一段水面，两端各往岸上延伸一点，架一座桥
			var k1 := k
			while k1 < even.size() and wet[k1]:
				k1 += 1
			var a := even[maxi(k - 2, 0)]
			var b := even[mini(k1 + 1, even.size() - 1)]
			_build_bridge(a, b)
			has_prev = false
			k = k1 + 1
			continue
		var p := even[k]
		var tan := (even[mini(k + 1, even.size() - 1)] - even[maxi(k - 1, 0)]).normalized()
		var nrm := Vector2(-tan.y, tan.x)
		var wl := 0.72 + _jitter.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.12
		var wr := 0.72 + _jitter.get_noise_2d(p.x * 3.0 + 50.0, p.y * 3.0) * 0.12
		var lp := p + nrm * wl
		var rp := p - nrm * wr
		var l3 := Vector3(lp.x, w.terrain_y(lp.x, lp.y) + 0.03, lp.y)
		var r3 := Vector3(rp.x, w.terrain_y(rp.x, rp.y) + 0.03, rp.y)
		if has_prev:
			mb.face("dirt", [prev_l, l3, r3], Vector3.UP)
			mb.face("dirt", [prev_l, r3, prev_r], Vector3.UP)
		prev_l = l3
		prev_r = r3
		has_prev = true
		if k % 2 == 0:
			pl.add_rect(P.PATH, Rect2(p - Vector2.ONE * 0.75, Vector2.ONE * 1.5))
		k += 1
	batch.add_static(mb.commit(), Transform3D.IDENTITY, false)


## 木桥：两端落在岸上，桥面水平（取两岸较高者 + 0.1，且至少高出水面 0.35），横向木板 + 两侧扶栏
func _build_bridge(a: Vector2, b: Vector2) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var deck_y := maxf(maxf(w.terrain_y(a.x, a.y), w.terrain_y(b.x, b.y)) + 0.1, WATER_Y + 0.35)
	var dir := (b - a) / len
	var yaw := atan2(dir.x, dir.y)  # 局部 +Z 沿桥
	var basis := Basis(Vector3.UP, yaw)
	var mb := MB.new()
	var z := 0.0
	while z < len - 0.05:
		mb.box("deck", Vector3(-0.85, -0.06, z), Vector3(0.85, 0.04, minf(z + 0.24, len) - 0.03))
		z += 0.27
	for sx in [-0.9, 0.9]:
		mb.box("trunk", Vector3(sx - 0.06, -0.3, 0), Vector3(sx + 0.06, -0.06, len), false, true)  # 纵梁
		var pz := 0.0
		while pz <= len + 0.01:
			mb.box("trunk", Vector3(sx - 0.05, -1.6, pz - 0.05), Vector3(sx + 0.05, 0.75, pz + 0.05))  # 桩 + 扶栏立柱
			pz += maxf(len / maxf(round(len / 1.6), 1.0), 0.8)
		mb.box("wall_wood", Vector3(sx - 0.04, 0.68, 0), Vector3(sx + 0.04, 0.78, len))  # 扶栏
	batch.add_static(mb.commit(), Transform3D(basis, Vector3(a.x, deck_y, a.y)))
	# 角色能走：沿桥每米一块覆盖高度
	var steps := int(ceil(len))
	for s in steps + 1:
		var c := a + dir * minf(float(s), len)
		w.overrides.append([Rect2(c - Vector2.ONE * 0.7, Vector2.ONE * 1.4), deck_y + 0.04])
		pl.add_rect(P.PATH, Rect2(c - Vector2.ONE * 0.9, Vector2.ONE * 1.8))


# ---------------------------------------------------------------- 植被

func _sink(p: Vector2, r: float) -> float:
	return slope(p) * r + 0.03


func _tree_at(p: Vector2, mesh: Mesh, s: float, pine: bool) -> bool:
	var y := w.ground_y(p.x, p.y) - _sink(p, 0.3 * s)
	var canopy: float = _town._canopy[mesh] * s
	if not pl.can_place(P.TREE, p, 0.3 * s, canopy, true):
		return false
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.18), s)), Vector3(p.x, y, p.y))
	batch.add_plant(mesh, xf, _town.tint(0.1))
	pl.add_circle(P.TREE, p, 0.3 * s, canopy, true)
	pl.solid_circles.append(Vector3(p.x, p.y, 0.4 if pine else 0.35))
	return true


func _random_tree(prefer_broad := false) -> Array:
	var pine := rng.randf() < (0.15 if prefer_broad else float(prm.get("pine_ratio", 0.6)))
	var mesh: Mesh = _town._pines[rng.randi_range(0, _town._pines.size() - 1)] if pine \
		else _town._broads[rng.randi_range(0, _town._broads.size() - 1)]
	return [mesh, pine]


func _plantable(p: Vector2, max_slope := 0.45) -> bool:
	var b := biome_at(p)
	return b != WATER and b != SAND and slope(p) <= max_slope


func _scatter_trees() -> void:
	var dens: float = prm.get("tree_density", 1.0) * w.tree_density
	# 成片的林子：湿度高于 forest_cover 的地方
	var attempts := int(w.size * w.size * 0.5 * dens)
	for k in attempts:
		var p := Vector2(rng.randf_range(-H + 1.0, H - 1.0), rng.randf_range(-H + 1.0, H - 1.0))
		var b := biome_at(p)
		var keep: float = {FOREST: 1.0, GRASS: float(prm.get("lone_trees", 0.06)), ROCK: 0.05, SAND: 0.0, WATER: 0.0}[b]
		if rng.randf() > keep or slope(p) > 0.45:
			continue
		# 林子有疏有密：低频噪声决定这一片是密林、疏林还是林间空地
		if _jitter.get_noise_2d(p.x * 0.12, p.y * 0.12) < float(prm.get("clearings", -1.0)):
			continue
		var t := _random_tree()
		var sr: Array = prm.get("tree_scale", [0.8, 1.25])
		var sc := rng.randf_range(sr[0], sr[1])
		_tree_at(p, t[0], sc * sc / ((sr[0] + sr[1]) * 0.5), t[1])  # 平方分布：小树多、大树少，高矮层次更自然
	# 平原：零星的小树丛（3~7 棵，阔叶为主）
	if prm.get("grove_trees", false):
		var groves := int(w.size * w.size / 1600.0 * w.tree_density)
		for g in groves:
			var c := Vector2(rng.randf_range(-H + 6.0, H - 6.0), rng.randf_range(-H + 6.0, H - 6.0))
			if not _plantable(c):
				continue
			for k in rng.randi_range(3, 7):
				var p := c + Vector2(rng.randf_range(-4.5, 4.5), rng.randf_range(-4.5, 4.5))
				if _plantable(p):
					var t := _random_tree(true)
					_tree_at(p, t[0], rng.randf_range(0.8, 1.2), t[1])
	# 平原：灌木篱（一排灌木，间或一棵树，沿缓慢弯曲的线）
	if prm.get("hedgerows", false):
		for h in int(w.size / 16.0):
			var p := Vector2(rng.randf_range(-H + 8.0, H - 8.0), rng.randf_range(-H + 8.0, H - 8.0))
			var ang := rng.randf() * TAU
			for k in rng.randi_range(10, 22):
				ang += rng.randf_range(-0.12, 0.12)
				p += Vector2(cos(ang), sin(ang)) * 1.3
				if not _plantable(p, 0.5) or rng.randf() < 0.12:
					continue
				if rng.randf() < 0.15:
					var t := _random_tree(true)
					_tree_at(p, t[0], rng.randf_range(0.7, 1.0), t[1])
				else:
					_bush_at(p, rng.randf_range(0.8, 1.15))


func _scatter_small() -> void:
	var rocks: float = prm.get("rocks", 1.0)
	for k in int(w.size * w.size * 0.03 * w.bush_density):
		var p := Vector2(rng.randf_range(-H + 1.0, H - 1.0), rng.randf_range(-H + 1.0, H - 1.0))
		var b := biome_at(p)
		if b == WATER or b == SAND or slope(p) > 0.6:
			continue
		if b == ROCK or rng.randf() < 0.22 * rocks:
			_rock_at(p, rng.randf_range(0.7, 1.6))
		elif rng.randf() < 0.5:
			_bush_at(p, rng.randf_range(0.7, 1.1))


func _bush_at(p: Vector2, s: float) -> void:
	var mesh: Mesh = _town._bushes[rng.randi_range(0, _town._bushes.size() - 1)]
	var r: float = _town._canopy[mesh] * s
	if not pl.can_place(P.BUSH, p, r):
		return
	batch.add_plant(mesh, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, w.ground_y(p.x, p.y) - _sink(p, r), p.y)), _town.tint(0.1))
	pl.add_circle(P.BUSH, p, r)
	pl.solid_circles.append(Vector3(p.x, p.y, r * 0.8))


func _rock_at(p: Vector2, s: float) -> void:
	var mesh: Mesh = _town._rocks[rng.randi_range(0, _town._rocks.size() - 1)]
	var r: float = _town._canopy[mesh] * s
	if not pl.can_place(P.ROCK, p, r):
		return
	batch.add_plant(mesh, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)), Vector3(p.x, w.ground_y(p.x, p.y) - _sink(p, r), p.y)), _town.tint(0.08) * (prm.get("rock_tint", Color.WHITE) as Color))
	pl.add_circle(P.ROCK, p, r)
	pl.solid_circles.append(Vector3(p.x, p.y, r * 0.8))


## 草：基础密度按地表（草地 1、林下 0.35），乘以风格的 grass；岩石 / 沙 / 水 / 陡坡没有
func _scatter_grass() -> void:
	var g: float = prm.get("grass", 0.5)
	if g <= 0.0:
		return
	var dens := func(p: Vector2) -> float:
		if slope(p) > 0.65:
			return 0.0
		match biome_at(p):
			GRASS:
				return g
			FOREST:
				return g * 0.35
		return 0.0
	var dry := func(p: Vector2) -> float:
		var above := w.terrain_y(p.x, p.y) - WATER_Y
		return clampf(1.0 - (above - _sand_h()) / 0.4, 0.0, 1.0) * 0.6 + smoothstep(0.35, 0.55, slope(p)) * 0.4
	var budget := int(12000.0 * g * (w.size / 128.0) * (w.size / 128.0))
	w.stats["grass"] = PWGrass.scatter(pl, batch, rng, dens, func(p: Vector2) -> float: return w.ground_y(p.x, p.y), dry,
		{"half": H - 0.6, "budget": budget, "flowers": prm.get("flowers", 0.1)})


# ---------------------------------------------------------------- 风格专用：海岛、峡谷、沙漠

func _sand_h() -> float:
	return float(prm.get("sand_h", SAND_H))


## 海岛：离中心越远越低；外圈先压成平缓的沙滩，再落进海里（海 = 全图水面）。轮廓用噪声扭曲，不是正圆
func _shape_island(frac: float) -> void:
	var wob := FastNoiseLite.new()
	wob.seed = rng.randi()
	wob.frequency = 0.045
	for j in n + 1:
		for i in n + 1:
			var p := w.vert_xz(i, j)
			var r := p.length() / (H * frac) * (1.0 + wob.get_noise_2d(p.x, p.y) * 0.2)
			var m := 1.0 - smoothstep(0.55, 1.0, r)   # 1 = 岛中心，0 = 外海
			var base := w.get_h(i, j)
			# 丘陵越靠近海越矮：起伏按 m 逐渐压平，沙滩到内陆是缓坡（不再出现一圈灰色陡坎）
			var land := WATER_Y + 0.24 + (base - (WATER_Y + 0.24)) * smoothstep(0.18, 0.9, m)
			w.set_h(i, j, lerpf(WATER_Y - 2.6, land, smoothstep(0.0, 0.18, m)))


## 填平孤立的小水坑：面积小于 min_cells 个网格点、又不是大片水域的积水抬到水面以上（海岛轮廓的扰动会在岸边留下这种小洼）
func _fill_puddles(min_cells := 60) -> void:
	var cnt := (n + 1) * (n + 1)
	var seen := PackedByteArray()
	seen.resize(cnt)
	for j0 in n + 1:
		for i0 in n + 1:
			if seen[idx(i0, j0)] != 0 or w.get_h(i0, j0) >= WATER_Y:
				continue
			var comp: Array[Vector2i] = []
			var stack: Array[Vector2i] = [Vector2i(i0, j0)]
			seen[idx(i0, j0)] = 1
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				comp.append(c)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = c + d
					if q.x < 0 or q.y < 0 or q.x > n or q.y > n or seen[idx(q.x, q.y)] != 0:
						continue
					if w.get_h(q.x, q.y) < WATER_Y:
						seen[idx(q.x, q.y)] = 1
						stack.append(q)
			if comp.size() < min_cells:
				for c in comp:
					w.set_h(c.x, c.y, WATER_Y + 0.12)


## 峡谷（自然版）。几种让地形看起来「天然」的做法组合起来：
##   1. 台地：Simplex 分形噪声（fBm）+ 两层域扭曲（domain warping，Inigo Quilez 的做法；FastNoiseLite 自带）
##      —— 起伏是弯曲、不规则的，不是一个个圆包
##   2. 峡谷网络：主河谷沿蜿蜒的河道，宽度随噪声变化；再用「反转的山脊噪声」（ridged）切出分叉的支沟
##   3. 岩层：厚度不均、略微倾斜的地层台阶（strata），每层陡坎的宽窄不同；分层前先给高度加噪声，台阶边缘不是等高线
##   4. 侵蚀：几千滴「水」顺坡流下的水力侵蚀，刻出冲沟、在坡脚堆积；再做一遍轻微的热力侵蚀（太尖的地方塌下来）
func _carve_canyon() -> void:
	var horiz := rng.randf() < 0.5
	var off := rng.randf_range(-H * 0.25, H * 0.25)
	var start := Vector2(-H - 6.0, off) if horiz else Vector2(off, -H - 6.0)
	_trace_river(start, Vector2(1, 0) if horiz else Vector2(0, 1))
	var amp: float = prm.get("hill_amp", 3.0)
	var top := WATER_Y + LAND_MIN + float(prm.get("plateau", 8.0))
	var floor_y := WATER_Y + 0.45
	var vw: float = float(prm.get("valley_w", 13.0)) * clampf(w.size / 128.0, 0.7, 1.0)
	var mesa := _noise(0.013, 5, FastNoiseLite.FRACTAL_FBM, 24.0)
	var gully := _noise(0.017, 3, FastNoiseLite.FRACTAL_RIDGED, 16.0)
	var widthn := _noise(0.028, 2, FastNoiseLite.FRACTAL_FBM, 0.0)
	var pert := _noise(0.05, 2, FastNoiseLite.FRACTAL_FBM, 0.0)
	# 地层表：从谷底往上，每层厚 0.7~2.4 米、陡坎占层厚的 15%~45%，整体略微倾斜
	var edges := PackedFloat32Array()
	var risers := PackedFloat32Array()
	var e := floor_y + 0.25
	while e < top + amp + 2.0:
		edges.append(e)
		risers.append(rng.randf_range(0.15, 0.45))
		e += rng.randf_range(0.7, 2.4)
	edges.append(e)
	var tilt := Vector2(rng.randf_range(-0.035, 0.035), rng.randf_range(-0.035, 0.035))
	for j in n + 1:
		for i in n + 1:
			var p := w.vert_xz(i, j)
			var h_top := top + amp * (mesa.get_noise_2d(p.x, p.y) * 0.5)
			var d: float = _nearest_on_river(p, vw * 3.2)[0]
			var ww := vw * (0.75 + 0.6 * (widthn.get_noise_2d(p.x, p.y) * 0.5 + 0.5))
			# 谷底平、崖壁陡：主河谷在 0.55~1.3 倍宽度之间从谷底升到台地
			var main := 1.0 - smoothstep(ww * 0.55, ww * 1.3, d)
			# ridged 噪声在「沟线」附近接近 1：取高的一截当支沟，离主河谷越远越浅，最后消失在台地上
			var g := gully.get_noise_2d(p.x, p.y) * 0.5 + 0.5
			var side := smoothstep(0.8, 0.97, g) * 0.7 * (1.0 - smoothstep(vw * 3.0, vw * 6.0, d))
			var h := lerpf(h_top, floor_y, maxf(main, side))
			var hh := h + pert.get_noise_2d(p.x, p.y) * 0.6 + tilt.dot(p)
			h = _stratify(hh, edges, risers) - (hh - h)
			w.set_h(i, j, maxf(h, floor_y - 0.15))
	_erode(int(prm.get("erosion", 3000)))
	_smooth_heights(1, 0.5)  # 侵蚀留下的单格尖刺抹掉，坡面干净（岩石 / 土的交界不会碎成斑点）
	_thermal(2, 1.7)
	_carve_channel(rng.randf_range(2.0, 2.6))
	_fill_puddles()


## 带域扭曲的分形噪声（FastNoiseLite）：warp > 0 时开启两层渐进式域扭曲
func _noise(freq: float, octaves: int, fractal: int, warp: float) -> FastNoiseLite:
	var f := FastNoiseLite.new()
	f.seed = rng.randi()
	f.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	f.frequency = freq
	f.fractal_type = fractal
	f.fractal_octaves = octaves
	if warp > 0.0:
		f.domain_warp_enabled = true
		f.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
		f.domain_warp_amplitude = warp
		f.domain_warp_frequency = freq * 0.9
		f.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
		f.domain_warp_fractal_octaves = 2
	return f


## 地层台阶：落在第 k 层里的高度，前面大部分是平台，最后一段（risers[k]）是陡坎
func _stratify(h: float, edges: PackedFloat32Array, risers: PackedFloat32Array) -> float:
	if h <= edges[0] or h >= edges[edges.size() - 1]:
		return h
	var k := edges.bsearch(h, true) - 1
	k = clampi(k, 0, edges.size() - 2)
	var e0 := edges[k]
	var e1 := edges[k + 1]
	var t := (h - e0) / (e1 - e0)
	return e0 + smoothstep(1.0 - risers[mini(k, risers.size() - 1)], 1.0, t) * (e1 - e0)


## 水力侵蚀（粒子法）：每滴水从随机位置出发顺着坡度流，带走泥沙、在流速变慢的地方沉积，几千滴下来就刻出冲沟。
## 在一份高度数组副本上算（比逐点调用 get_h / set_h 快得多），算完写回
func _erode(drops: int) -> void:
	var N := n + 1
	var hm := w.heights.duplicate()
	const INERTIA := 0.06
	const CAPACITY := 4.0
	const MIN_CAP := 0.01
	const ERODE := 0.3
	const DEPOSIT := 0.3
	const EVAP := 0.025
	const GRAVITY := 4.0
	for drop in drops:
		var x := rng.randf_range(1.0, N - 2.0)
		var y := rng.randf_range(1.0, N - 2.0)
		var dx := 0.0
		var dy := 0.0
		var speed := 1.0
		var water := 1.0
		var sed := 0.0
		for life in 32:
			var xi := int(x)
			var yi := int(y)
			var u := x - xi
			var v := y - yi
			var i0 := yi * N + xi
			var h00 := hm[i0]
			var h10 := hm[i0 + 1]
			var h01 := hm[i0 + N]
			var h11 := hm[i0 + N + 1]
			var gx := (h10 - h00) * (1.0 - v) + (h11 - h01) * v
			var gy := (h01 - h00) * (1.0 - u) + (h11 - h10) * u
			var hc := h00 * (1.0 - u) * (1.0 - v) + h10 * u * (1.0 - v) + h01 * (1.0 - u) * v + h11 * u * v
			dx = dx * INERTIA - gx * (1.0 - INERTIA)
			dy = dy * INERTIA - gy * (1.0 - INERTIA)
			var l := sqrt(dx * dx + dy * dy)
			if l < 1e-6:
				break
			dx /= l
			dy /= l
			x += dx
			y += dy
			if x < 1.0 or y < 1.0 or x >= N - 2.0 or y >= N - 2.0:
				break
			var nxi := int(x)
			var nyi := int(y)
			var nu := x - nxi
			var nv := y - nyi
			var j0 := nyi * N + nxi
			var nh := hm[j0] * (1.0 - nu) * (1.0 - nv) + hm[j0 + 1] * nu * (1.0 - nv) + hm[j0 + N] * (1.0 - nu) * nv + hm[j0 + N + 1] * nu * nv
			var dh := nh - hc
			var cap := maxf(-dh, MIN_CAP) * speed * water * CAPACITY
			if sed > cap or dh > 0.0:
				var dep := minf(dh, sed) if dh > 0.0 else (sed - cap) * DEPOSIT
				sed -= dep
				hm[i0] += dep * (1.0 - u) * (1.0 - v)
				hm[i0 + 1] += dep * u * (1.0 - v)
				hm[i0 + N] += dep * (1.0 - u) * v
				hm[i0 + N + 1] += dep * u * v
			else:
				var er := minf((cap - sed) * ERODE, -dh)
				hm[i0] -= er * (1.0 - u) * (1.0 - v)
				hm[i0 + 1] -= er * u * (1.0 - v)
				hm[i0 + N] -= er * (1.0 - u) * v
				hm[i0 + N + 1] -= er * u * v
				sed += er
			speed = sqrt(maxf(0.01, speed * speed - dh * GRAVITY))
			water *= 1.0 - EVAP
	w.heights = hm


## 平滑：每个顶点向四邻平均值靠拢 k（0..1）
func _smooth_heights(passes: int, k: float) -> void:
	var N := n + 1
	for pass_i in passes:
		var hm := w.heights.duplicate()
		for j in range(1, N - 1):
			for i in range(1, N - 1):
				var c := j * N + i
				var avg := (w.heights[c - 1] + w.heights[c + 1] + w.heights[c - N] + w.heights[c + N]) * 0.25
				hm[c] = lerpf(w.heights[c], avg, k)
		w.heights = hm


## 热力侵蚀：比 talus（每米落差）还陡的地方，把一部分高度挪给低处的邻居（太尖的棱角塌下来，崖脚形成碎石坡）
func _thermal(passes: int, talus: float) -> void:
	var N := n + 1
	for pass_i in passes:
		var hm := w.heights.duplicate()
		for j in range(1, N - 1):
			for i in range(1, N - 1):
				var k := j * N + i
				var h := w.heights[k]
				for o in [1, -1, N, -N]:
					var diff := h - w.heights[k + o]
					if diff > talus:
						var mv := (diff - talus) * 0.25
						hm[k] -= mv
						hm[k + o] += mv
		w.heights = hm


## 沙漠：离最近的湖（绿洲）有多远，以湖半径为单位（1 = 刚好在岸边）
func _oasis_t(p: Vector2) -> float:
	var best := 99.0
	for l in lakes:
		best = minf(best, p.distance_to(l.c) / maxf(l.r, 1.0))
	return best


## Blender 资产（包括资产工坊生成的）：风格参数 blender = [{tag, density（每千平方米个数）, where, semantic?, max?}]
## where：land 陆地 / beach 沙滩 / sand 沙地 / oasis 绿洲水边 / any 任何不在水里的地方
## 地标（灯塔等）每个场景最多一个。资产按 PWAssetLibrary.fits_climate 过滤（雪人只在雪原）
func _scatter_blender() -> void:
	var specs: Array = prm.get("blender", [])
	if specs.is_empty():
		return
	var landmark_done := false
	for e: Dictionary in specs:
		var items: Array[Dictionary] = []
		for it in PWAssetLibrary.blender_with_tags([e.tag]):
			if not PWAssetLibrary.fits_climate(it, w.theme):
				continue
			if e.has("semantic") and not (it.get("semantic", "") in e.semantic):
				continue
			items.append(it)
		if items.is_empty():
			continue
		var want := int(float(e.get("density", 0.5)) * w.size * w.size / 1000.0)
		if e.has("max"):
			want = mini(want, int(e.max))
		var placed := 0
		for attempt in want * 60:
			if placed >= want:
				break
			var it: Dictionary = items[rng.randi_range(0, items.size() - 1)]
			var sem: String = it.get("semantic", "")
			if sem == "landmarks" and landmark_done:
				continue
			var p := Vector2(rng.randf_range(-H + 2.0, H - 2.0), rng.randf_range(-H + 2.0, H - 2.0))
			if String(e.get("where", "")) == "oasis" and not lakes.is_empty():  # 绿洲：直接在湖边那一圈取点
				var l: Dictionary = lakes[rng.randi_range(0, lakes.size() - 1)]
				var ang := rng.randf() * TAU
				p = (l.c as Vector2) + Vector2(cos(ang), sin(ang)) * float(l.r) * rng.randf_range(1.05, 1.55)
			if not _where_ok(p, String(e.get("where", "land"))):
				continue
			var mesh: Mesh = it.build.call(rng.randi_range(0, 7))
			var a := mesh.get_aabb()
			var r := maxf(a.size.x, a.size.z) * 0.5
			var y := w.ground_y(p.x, p.y) - _sink(p, minf(r, 1.0) * 0.4)
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			if it.get("plant", false):
				var sc := rng.randf_range(0.85, 1.15)
				basis = basis.scaled(Vector3(sc, sc * rng.randf_range(0.92, 1.12), sc))
				r *= sc
			if sem == "trees":
				if not pl.can_place(P.TREE, p, 0.3, r, true):
					continue
				batch.add_plant(mesh, Transform3D(basis, Vector3(p.x, y, p.y)), _town.tint(0.1))
				pl.add_circle(P.TREE, p, 0.3, r, true)
				pl.solid_circles.append(Vector3(p.x, p.y, 0.35))
			else:
				var cat := P.LANDMARK if sem == "landmarks" else P.ROCK
				if not pl.can_place(cat, p, r * 0.8):
					continue
				if it.get("plant", false):
					batch.add_plant(mesh, Transform3D(basis, Vector3(p.x, y, p.y)), _town.tint(0.08))
				else:
					batch.add_static(mesh, Transform3D(basis, Vector3(p.x, y, p.y)))
				pl.add_circle(cat, p, r * 0.8)
				pl.solid_circles.append(Vector3(p.x, p.y, r * 0.6))
				landmark_done = landmark_done or sem == "landmarks"
			placed += 1
		w.stats["bl:" + String(e.tag)] = int(w.stats.get("bl:" + String(e.tag), 0)) + placed


func _where_ok(p: Vector2, where: String) -> bool:
	var above := w.terrain_y(p.x, p.y) - WATER_Y
	if above < 0.06:
		return false
	var sl := slope(p)
	match where:
		"beach":
			return above < _sand_h() + 0.25 and sl < 0.3
		"sand":
			return biome_at(p) == SAND and sl < 0.35
		"oasis":
			var ot := _oasis_t(p)
			return ot > 1.02 and ot < 1.6 and sl < 0.35
		"land":
			var b := biome_at(p)
			return b != SAND and b != WATER and sl < 0.4
	return sl < 0.45


# ---------------------------------------------------------------- 湖里

func _lake_life() -> void:
	if lakes.is_empty():
		return
	var weeds: Array[Mesh] = _town.weed_variants()
	var main: Dictionary = lakes[0]
	for l in lakes:
		if l.r > main.r:
			main = l
	for l in lakes:
		var c: Vector2 = l.c
		for k in int(l.r * 4.0):
			var a := rng.randf() * TAU
			var q: Vector2 = c + Vector2(cos(a), sin(a)) * _lake_radius(l, a) * rng.randf_range(0.6, 0.95)
			var depth := WATER_Y - w.terrain_y(q.x, q.y)
			if depth < 0.3 or depth > 2.2:
				continue
			var s := rng.randf_range(0.8, 1.5)
			batch.add_plant(weeds[rng.randi_range(0, 2)], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)),
				Vector3(q.x, w.terrain_y(q.x, q.y) - 0.03, q.y)))
	var r: float = main.r * 1.1
	w.add_fish(Rect2(main.c - Vector2(r, r), Vector2(r, r) * 2.0), clampi(int(main.r * 1.4), 10, 30))
	w.stats["deepest_lake"] = main.c
