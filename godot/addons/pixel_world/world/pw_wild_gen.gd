@tool
extends RefCounted
## 野外生成（PWWorld theme = "wild"）。
##
## 1. 地形：两层 FastNoiseLite 噪声得到高度，按 0.5 米一级做成阶梯（体素感）；最低处是湖，湖底由浅到深
## 2. 地表：按「高度 × 湿度」划分 湖 / 沙滩 / 草地 / 森林 / 岩石
## 3. 兴趣点：营地（篝火 + 原木凳 + 货物）、木屋、废墟，放在平坦处、彼此离得够远
## 4. 小路：A* 在网格上把兴趣点连起来（坡越陡、林子越密代价越高，不能过湖）
## 5. 植被：森林以松树为主、草地零星阔叶树和灌木、岩石区多石头；全部经过 PWPlacement 规则检查，
##    且只种在平坦处（不会悬在台阶边上）
## 悬崖边（相邻落差 > 0.55 米）标为不可通行，角色不会从悬崖上走下去。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")
const House := preload("res://addons/pixel_world/assets/placeholder/pw_house_builder.gd")
const Trees := preload("res://addons/pixel_world/assets/placeholder/pw_tree_builder.gd")
const Props := preload("res://addons/pixel_world/assets/placeholder/pw_props_builder.gd")
const P := preload("res://addons/pixel_world/world/pw_placement.gd")
const Town := preload("res://addons/pixel_world/world/pw_town_gen.gd")

enum { WATER, SAND, GRASS, FOREST, ROCK }
const STEP := 0.5
const WATER_Y := -0.45
const SEA := 0.34       # 低于这个高度值是湖
const LEVELS := 7

var w: PWWorld
var rng: RandomNumberGenerator
var batch: PWBatcher
var pl: PWPlacement
var H := 64.0
var n := 0
var biome := PackedByteArray()
var path_cells := {}  # Vector2i -> true
var pois: Array[Vector2] = []
var _town: Object  # 借用小镇生成器里的树 / 灌木工具函数


func _init(world: PWWorld, r: RandomNumberGenerator, b: PWBatcher) -> void:
	w = world
	rng = r
	batch = b
	pl = world.placement
	H = world.size * 0.5


func run() -> void:
	w.water_y = WATER_Y
	w.terraced = true
	w.init_grid(H, 0.0)
	n = w.grid_n
	_make_heights()
	_build_terrain_mesh()
	_mark_cliffs()
	_place_pois()
	_connect_paths()
	_town = Town.new(w, rng, batch)
	_scatter()
	_lake_life()
	if pois.is_empty():
		w.spawn_point = Vector3(0, w.ground_y(0, 0), 0)
	else:
		var s := pois[0] + Vector2(3.5, 0)
		w.spawn_point = Vector3(s.x, w.ground_y(s.x, s.y), s.y)
	for c in [P.LANDMARK, P.TREE, P.BUSH, P.ROCK, P.PATH]:
		w.stats[String(c)] = pl.count(c)


func idx(i: int, j: int) -> int:
	return j * (n + 1) + i


# ---------------------------------------------------------------- 高度与地表

func _make_heights() -> void:
	var hn := FastNoiseLite.new()
	hn.seed = rng.randi()
	hn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hn.frequency = 0.022 * 80.0 / maxf(w.size, 40.0)
	hn.fractal_octaves = 4
	var mn := FastNoiseLite.new()
	mn.seed = rng.randi()
	mn.frequency = 0.03
	biome.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var p := w.vert_xz(i, j)
			var e := hn.get_noise_2d(p.x, p.y) * 0.5 + 0.5
			# 地图边缘稍微抬高，湖不会被切在边界上
			var edge := maxf(absf(p.x), absf(p.y)) / H
			e += smoothstep(0.75, 1.0, edge) * 0.18
			if not w.with_lake:
				e = maxf(e, SEA + 0.01)
			var m := mn.get_noise_2d(p.x, p.y) * 0.5 + 0.5
			var h: float
			var b: int
			if e < SEA:
				# 水下也做成等高台阶（每级 0.4 米），和陆地的阶梯风格一致，湖底不会碎成一格一格的小台阶
				var depth := clampf((SEA - e) / 0.16, 0.0, 1.0)
				h = WATER_Y - 0.15 - floorf(depth * depth * 2.8 / 0.4) * 0.4
				b = WATER
			else:
				var lv := floori((e - SEA) / (1.0 - SEA) * LEVELS)
				h = lv * STEP
				if e < SEA + 0.03:
					b = SAND
				elif lv >= 5:
					b = ROCK
				elif m > 0.55:
					b = FOREST
				else:
					b = GRASS
			w.set_h(i, j, h)
			biome[idx(i, j)] = b


func _top_mat(b: int, depth: float) -> String:
	match b:
		WATER:
			return "sand" if depth < 1.0 else "lakebed"
		SAND:
			return "sand"
		ROCK:
			return "rock"
	return "grass"


## 地形网格：每个网格顶点是一个 1×1 米的方格（中心在顶点上）；同一行连续、等高、同材质的方格合并成一个面；
## 与较低邻居之间补竖直的侧面
func _build_terrain_mesh() -> void:
	var top := MB.new()
	var side := MB.new()
	var half := w.cell * 0.5
	for j in n + 1:
		var i := 0
		while i <= n:
			var h := w.get_h(i, j)
			var mat := _top_mat(biome[idx(i, j)], WATER_Y - h)
			var k := i
			while k + 1 <= n and is_equal_approx(w.get_h(k + 1, j), h) and _top_mat(biome[idx(k + 1, j)], WATER_Y - w.get_h(k + 1, j)) == mat:
				k += 1
			var a := w.vert_xz(i, j) - Vector2(half, half)
			var b := w.vert_xz(k, j) + Vector2(half, half)
			top.face(mat, [Vector3(a.x, h, a.y), Vector3(b.x, h, a.y), Vector3(b.x, h, b.y), Vector3(a.x, h, b.y)], Vector3.UP)
			i = k + 1
	# 侧面
	for j in n + 1:
		for i in n + 1:
			var h := w.get_h(i, j)
			var c := w.vert_xz(i, j)
			var mat := "rock" if biome[idx(i, j)] == ROCK else "earth"
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni: int = i + d.x
				var nj: int = j + d.y
				var nh := w.get_h(ni, nj) if ni >= 0 and nj >= 0 and ni <= n and nj <= n else h - 3.0
				if nh >= h - 0.001:
					continue
				var o := Vector2(d.x, d.y) * half
				var t := Vector2(-d.y, d.x) * half
				var p0 := c + o - t
				var p1 := c + o + t
				side.face(mat, [Vector3(p0.x, h, p0.y), Vector3(p1.x, h, p1.y), Vector3(p1.x, nh, p1.y), Vector3(p0.x, nh, p0.y)], Vector3(d.x, 0, d.y))
	batch.add_static(top.commit(), Transform3D.IDENTITY, false)
	batch.add_static(side.commit(), Transform3D.IDENTITY)
	# 水域登记（树、兴趣点不进水）
	for j in range(0, n + 1, 2):
		for i in range(0, n + 1, 2):
			if biome[idx(i, j)] == WATER:
				var p := w.vert_xz(i, j)
				pl.add_rect(P.WATER, Rect2(p - Vector2.ONE * 1.2, Vector2.ONE * 2.4))


func _mark_cliffs() -> void:
	w.walk_block = PackedByteArray()
	w.walk_block.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var h := w.get_h(i, j)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nh := w.get_h(i + d.x, j + d.y)
				if absf(nh - h) > 0.55 and h > WATER_Y and nh > WATER_Y:
					w.walk_block[idx(i, j)] = 1


## 以 p 为中心、半径 r 内是否平坦（等高、在陆地上、不是岩石）
func flat(p: Vector2, r: float, allow_rock := false) -> bool:
	var h := w.ground_y(p.x, p.y)
	if h < WATER_Y + 0.01:
		return false
	for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2(r, r) * 0.7, Vector2(-r, r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, -r) * 0.7]:
		var q: Vector2 = p + d
		if absf(q.x) > H - 1.0 or absf(q.y) > H - 1.0:
			return false
		if not is_equal_approx(w.ground_y(q.x, q.y), h):
			return false
		if not allow_rock and _biome_at(q) == ROCK:
			return false
	return true


func _biome_at(p: Vector2) -> int:
	var g := (p - w.origin) / w.cell
	return biome[idx(clampi(int(floor(g.x + 0.5)), 0, n), clampi(int(floor(g.y + 0.5)), 0, n))]


func _cell_of(p: Vector2) -> Vector2i:
	var g := (p - w.origin) / w.cell
	return Vector2i(clampi(int(floor(g.x + 0.5)), 0, n), clampi(int(floor(g.y + 0.5)), 0, n))


# ---------------------------------------------------------------- 兴趣点

func _place_pois() -> void:
	var kinds := ["camp", "cabin", "ruins", "camp"]
	var want := 3 if w.size <= 112 else 4
	var min_gap := w.size * 0.28
	for attempt in 600:
		if pois.size() >= want:
			break
		var p := Vector2(rng.randf_range(-H + 8.0, H - 8.0), rng.randf_range(-H + 8.0, H - 8.0))
		var too_close := false
		for q in pois:
			if q.distance_to(p) < min_gap:
				too_close = true
		if too_close or not flat(p, 4.5):
			continue
		var rect := Rect2(p - Vector2(4.0, 4.0), Vector2(8.0, 8.0))
		if not pl.can_place_rect(P.LANDMARK, rect, 0.0, true):
			continue
		pl.add_rect(P.LANDMARK, rect, 0.0, true)
		_build_poi(kinds[pois.size() % kinds.size()], p)
		pois.append(p)


func _build_poi(kind: String, p: Vector2) -> void:
	var y := w.ground_y(p.x, p.y)
	match kind:
		"cabin":
			var hp := House.random_params(rng)
			hp.width = 6.0
			hp.depth = 5.0
			hp.floors = 1
			hp.wall = "wall_wood"
			hp.chimney = true
			var yaw := rng.randi_range(0, 3) * PI * 0.5
			batch.add_static(House.build(hp), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y)))
			var body := Vector2(6.5, 5.5) if int(round(yaw / (PI * 0.5))) % 2 == 0 else Vector2(5.5, 6.5)
			pl.solid_rects.append(Rect2(p - body * 0.5, body))
		"ruins":
			var mb := MB.new()
			for k in rng.randi_range(4, 6):
				var a := rng.randf() * TAU
				var c := p + Vector2(cos(a), sin(a)) * rng.randf_range(1.0, 3.0)
				var horiz := rng.randf() < 0.5
				var len := rng.randf_range(1.2, 3.0)
				var hh := rng.randf_range(0.5, 2.2)
				var half := Vector2(len * 0.5, 0.25) if horiz else Vector2(0.25, len * 0.5)
				mb.box("stone", Vector3(c.x - half.x, y, c.y - half.y), Vector3(c.x + half.x, y + hh, c.y + half.y))
				# 塌了一半的墙头：上面再叠一小截错开的石块
				if hh > 1.0:
					var s := half * Vector2(0.6, 0.6) if horiz else half * Vector2(1.0, 0.6)
					mb.box("stone", Vector3(c.x - s.x, y + hh, c.y - s.y), Vector3(c.x + s.x * 0.4, y + hh + 0.4, c.y + s.y * 0.4))
				pl.solid_rects.append(Rect2(c - half, half * 2.0))
			batch.add_static(mb.commit(), Transform3D(Basis(), Vector3.ZERO))
			_scatter_rocks_around(p, 4, 3.5)
		_:
			# 营地：石圈篝火（夜里发光）+ 原木凳 + 货物
			var fire := MB.new()
			for k in 7:
				var a := TAU * k / 7.0
				fire.ngon_frustum("rock", Vector3(p.x + cos(a) * 0.55, 0, p.y + sin(a) * 0.55), y, y + 0.18, 0.14, 0.1, 5, a, true)
			fire.tube("trunk", Vector3(p.x - 0.35, y + 0.08, p.y - 0.1), Vector3(p.x + 0.35, y + 0.12, p.y + 0.1), 0.06, 0.06, 6)
			fire.tube("trunk", Vector3(p.x - 0.1, y + 0.08, p.y + 0.35), Vector3(p.x + 0.1, y + 0.12, p.y - 0.35), 0.06, 0.06, 6)
			fire.ngon_frustum("bulb", Vector3(p.x, 0, p.y), y + 0.1, y + 0.45, 0.16, 0.0, 5, 0.0, false)
			batch.add_static(fire.commit(), Transform3D.IDENTITY)
			pl.solid_circles.append(Vector3(p.x, p.y, 0.7))
			var bench := Props.build_bench("log")
			for k in 3:
				var a := TAU * k / 3.0 + rng.randf() * 0.5
				var bp := p + Vector2(cos(a), sin(a)) * 2.0
				batch.add_static(bench, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(bp.x, y, bp.y)))
				pl.solid_circles.append(Vector3(bp.x, bp.y, 0.6))
			var crate := Props.build_crate()
			var cp := p + Vector2(2.8, -2.4)
			batch.add_static(crate, Transform3D(Basis(Vector3.UP, 0.3), Vector3(cp.x, y, cp.y)))
			batch.add_static(Props.build_barrel(), Transform3D(Basis(), Vector3(cp.x + 0.9, y, cp.y + 0.4)))
			pl.solid_circles.append(Vector3(cp.x + 0.4, cp.y, 0.8))


func _scatter_rocks_around(p: Vector2, count: int, radius: float) -> void:
	var rocks := [Trees.build_rock(4100), Trees.build_rock(4101), Trees.build_rock(4102)]
	for k in count:
		var a := rng.randf() * TAU
		var q := p + Vector2(cos(a), sin(a)) * rng.randf_range(radius * 0.5, radius)
		var s := rng.randf_range(0.6, 1.1)
		batch.add_plant(rocks[k % rocks.size()], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.8, s)), Vector3(q.x, w.ground_y(q.x, q.y), q.y)))


# ---------------------------------------------------------------- 小路（A*）

func _connect_paths() -> void:
	if pois.size() < 2:
		return
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n + 1, n + 1)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for j in n + 1:
		for i in n + 1:
			var b := biome[idx(i, j)]
			if b == WATER or w.walk_block[idx(i, j)] != 0:
				astar.set_point_solid(Vector2i(i, j), true)
			else:
				astar.set_point_weight_scale(Vector2i(i, j), 1.0 + (1.5 if b == FOREST else 0.0) + (3.0 if b == ROCK else 0.0))
	# 每个兴趣点连到离它最近的、已经连上的兴趣点（最小生成树的贪心近似）
	var connected: Array[Vector2] = [pois[0]]
	var left := pois.slice(1)
	while not left.is_empty():
		var best_a := Vector2.ZERO
		var best_b := Vector2.ZERO
		var best_d := INF
		for a in connected:
			for b: Vector2 in left:
				if a.distance_to(b) < best_d:
					best_d = a.distance_to(b)
					best_a = a
					best_b = b
		var cells := astar.get_id_path(_cell_of(best_a + Vector2(4.6, 0)), _cell_of(best_b - Vector2(4.6, 0)))
		for c in cells:
			path_cells[c] = true
		connected.append(best_b)
		left.erase(best_b)
	# 画小路：每格一块土路面片，贴在地形上方；同时登记，不让树长在路上
	var mb := MB.new()
	for c: Vector2i in path_cells:
		var p := w.vert_xz(c.x, c.y)
		var y := w.get_h(c.x, c.y) + 0.015
		var r := 0.62
		mb.face("dirt", [Vector3(p.x - r, y, p.y - r), Vector3(p.x + r, y, p.y - r), Vector3(p.x + r, y, p.y + r), Vector3(p.x - r, y, p.y + r)], Vector3.UP)
		pl.add_rect(P.PATH, Rect2(p - Vector2.ONE * 0.6, Vector2.ONE * 1.2))
	batch.add_static(mb.commit(), Transform3D.IDENTITY, false)


# ---------------------------------------------------------------- 植被

func _scatter() -> void:
	_town._variants()
	var attempts := int(w.size * w.size * 0.5 * w.tree_density)
	for k in attempts:
		var p := Vector2(rng.randf_range(-H + 1.0, H - 1.0), rng.randf_range(-H + 1.0, H - 1.0))
		var b := _biome_at(p)
		var keep: float = {FOREST: 1.0, GRASS: 0.12, ROCK: 0.05, SAND: 0.0, WATER: 0.0}[b]
		if rng.randf() > keep or not flat(p, 0.9, b == ROCK):
			continue
		var pine := rng.randf() < (0.8 if b == FOREST else 0.35)
		var mesh: ArrayMesh = _town._pines[rng.randi_range(0, _town._pines.size() - 1)] if pine \
			else _town._broads[rng.randi_range(0, _town._broads.size() - 1)]
		_tree_at(p, mesh, rng.randf_range(0.8, 1.25), pine)
	# 灌木和石头
	for k in int(w.size * w.size * 0.03 * w.bush_density):
		var p := Vector2(rng.randf_range(-H + 1.0, H - 1.0), rng.randf_range(-H + 1.0, H - 1.0))
		var b := _biome_at(p)
		if b == WATER or b == SAND or not flat(p, 0.6, true):
			continue
		if b == ROCK or rng.randf() < 0.25:
			_rock_at(p, rng.randf_range(0.7, 1.6))
		elif rng.randf() < 0.5:
			_bush_at(p, rng.randf_range(0.7, 1.1))


func _tree_at(p: Vector2, mesh: ArrayMesh, s: float, pine: bool) -> void:
	var y := w.ground_y(p.x, p.y)
	var canopy: float = _town._canopy[mesh] * s
	if not pl.can_place(P.TREE, p, 0.3 * s, canopy, true):
		return
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.18), s)), Vector3(p.x, y, p.y))
	batch.add_plant(mesh, xf, _town.tint(0.1))
	pl.add_circle(P.TREE, p, 0.3 * s, canopy, true)
	pl.solid_circles.append(Vector3(p.x, p.y, 0.4 if pine else 0.35))


func _bush_at(p: Vector2, s: float) -> void:
	var mesh: ArrayMesh = _town._bushes[rng.randi_range(0, _town._bushes.size() - 1)]
	var r: float = _town._canopy[mesh] * s
	if not pl.can_place(P.BUSH, p, r):
		return
	batch.add_plant(mesh, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, w.ground_y(p.x, p.y), p.y)), _town.tint(0.1))
	pl.add_circle(P.BUSH, p, r)
	pl.solid_circles.append(Vector3(p.x, p.y, r * 0.8))


func _rock_at(p: Vector2, s: float) -> void:
	var mesh: ArrayMesh = _town._rocks[rng.randi_range(0, _town._rocks.size() - 1)]
	var r: float = _town._canopy[mesh] * s
	if not pl.can_place(P.ROCK, p, r):
		return
	batch.add_plant(mesh, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)), Vector3(p.x, w.ground_y(p.x, p.y), p.y)), _town.tint(0.08))
	pl.add_circle(P.ROCK, p, r)
	pl.solid_circles.append(Vector3(p.x, p.y, r * 0.8))


# ---------------------------------------------------------------- 湖里

func _lake_life() -> void:
	var weeds: Array[ArrayMesh] = [Props.build_weed(5000), Props.build_weed(5001), Props.build_weed(5002)]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var count := 0
	var deepest := -1.0
	for j in n + 1:
		for i in n + 1:
			var depth := WATER_Y - w.get_h(i, j)
			if depth < 0.4:
				continue
			var p := w.vert_xz(i, j)
			if depth > deepest:
				deepest = depth
				w.stats["deepest_lake"] = p
			lo = lo.min(p)
			hi = hi.max(p)
			count += 1
			if depth < 2.0 and rng.randf() < 0.08:
				var s := rng.randf_range(0.8, 1.5)
				batch.add_plant(weeds[rng.randi_range(0, 2)], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)),
					Vector3(p.x + rng.randf_range(-0.4, 0.4), w.get_h(i, j), p.y + rng.randf_range(-0.4, 0.4))))
	if count > 60:
		w.add_fish(Rect2(lo, hi - lo), clampi(count / 25, 8, 30))
