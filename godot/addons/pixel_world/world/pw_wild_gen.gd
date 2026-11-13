@tool
extends RefCounted
## 野外生成（PWWorld theme = "wild"）。
##
## 1. 地形：两层 FastNoiseLite 噪声得到连续的高度场——湖底、岸边、草地、山坡之间都是平滑的坡，没有台阶。
##    湖底在岸线处斜率为 0（慢慢变浅），上岸后近似线性抬升，湖边是一圈窄沙滩，高处形成山丘。
## 2. 地表：按「高度 × 湿度 × 坡度」划分 湖 / 沙滩 / 草地 / 森林 / 岩石（陡坡和高处是岩石）；
##    地形网格顶点连续、法线平滑，材质边界用噪声打乱，不是沿着方格走的直角台阶。
## 3. 兴趣点：营地（篝火 + 原木凳 + 货物）、木屋、废墟，放在坡度小的地方，脚下平整成一块平台，向外平滑过渡。
## 4. 小路：A* 在网格上把兴趣点连起来（越陡、林子越密代价越高；太陡和水里不能走），路面贴着地形起伏。
## 5. 植被：森林以松树为主、草地零星阔叶树和灌木、岩石区多石头；全部经过 PWPlacement 规则检查，只种在缓坡上。
## 太陡的坡（每米升高 > 0.75 米）标为不可通行。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")
const Mats := preload("res://addons/pixel_world/core/pw_materials.gd")
const House := preload("res://addons/pixel_world/assets/placeholder/pw_house_builder.gd")
const Trees := preload("res://addons/pixel_world/assets/placeholder/pw_tree_builder.gd")
const Props := preload("res://addons/pixel_world/assets/placeholder/pw_props_builder.gd")
const P := preload("res://addons/pixel_world/world/pw_placement.gd")
const Town := preload("res://addons/pixel_world/world/pw_town_gen.gd")

enum { WATER, SAND, GRASS, FOREST, ROCK }
const WATER_Y := -0.45
const SEA := 0.34          # 噪声值低于这个是湖
const LAND_H := 5.0        # 最高处比水面高多少米
const LAKE_D := 3.0        # 最深处比水面低多少米
const SAND_H := 0.22       # 水面以上这么高之内是沙滩
const STEEP := 0.75        # 每米升高超过这个就不可通行（约 37°）
const ROCK_SLOPE := 0.55   # 每米升高超过这个就露出岩石

var w: PWWorld
var rng: RandomNumberGenerator
var batch: PWBatcher
var pl: PWPlacement
var H := 64.0
var n := 0
var moisture := PackedFloat32Array()
var path_cells := {}  # Vector2i -> true
var pois: Array[Vector2] = []
var _poi_kinds: Array[String] = []
var _jitter: FastNoiseLite
var _town: Object  # 借用小镇生成器里的树 / 灌木工具函数


func _init(world: PWWorld, r: RandomNumberGenerator, b: PWBatcher) -> void:
	w = world
	rng = r
	batch = b
	pl = world.placement
	H = world.size * 0.5


func run() -> void:
	w.water_y = WATER_Y
	w.terraced = false
	w.init_grid(H, 0.0)
	n = w.grid_n
	_make_heights()
	_choose_pois()          # 先选兴趣点并把脚下压平，再建地形网格
	_build_terrain_mesh()
	_mark_steep()
	for i in pois.size():
		_build_poi(_poi_kinds[i], pois[i])
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


# ---------------------------------------------------------------- 高度

## 噪声值 → 高度（米）。岸线（e = SEA）两侧的斜率都是 0，所以湖底到沙滩、沙滩到草地都是缓坡
static func height_of(e: float) -> float:
	if e < SEA:
		var t := clampf((SEA - e) / 0.09, 0.0, 1.0)
		return WATER_Y - LAKE_D * t * t * (3.0 - 2.0 * t)
	# 上岸后高度近似线性抬升（坡度适中），沙滩只是湖边窄窄一圈；高处再略微加速，形成山丘
	var u := clampf((e - SEA) / (1.0 - SEA), 0.0, 1.0)
	return WATER_Y + LAND_H * (u * 0.75 + u * u * 0.5)


func _make_heights() -> void:
	var hn := FastNoiseLite.new()
	hn.seed = rng.randi()
	hn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hn.frequency = 0.022 * 80.0 / maxf(w.size, 40.0)
	hn.fractal_octaves = 4
	var mn := FastNoiseLite.new()
	mn.seed = rng.randi()
	mn.frequency = 0.03
	_jitter = FastNoiseLite.new()
	_jitter.seed = rng.randi()
	_jitter.frequency = 0.35
	moisture.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var p := w.vert_xz(i, j)
			var e := hn.get_noise_2d(p.x, p.y) * 0.5 + 0.5
			# 地图边缘稍微抬高，湖不会被切在边界上
			var edge := maxf(absf(p.x), absf(p.y)) / H
			e += smoothstep(0.75, 1.0, edge) * 0.18
			if not w.with_lake:
				e = maxf(e, SEA + 0.02)
			w.set_h(i, j, height_of(e))
			moisture[idx(i, j)] = mn.get_noise_2d(p.x, p.y) * 0.5 + 0.5


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


## 某处的地表类型。边界加一点噪声，避免材质分界沿着方格走成直角台阶
func biome_at(p: Vector2) -> int:
	var h := w.terrain_y(p.x, p.y)
	var j := _jitter.get_noise_2d(p.x, p.y)
	if h < WATER_Y:
		return WATER
	if h < WATER_Y + SAND_H + j * 0.12:
		return SAND
	if slope(p) > ROCK_SLOPE + j * 0.15 or h > WATER_Y + LAND_H * 0.72 + j * 0.4:
		return ROCK
	var g := (p - w.origin) / w.cell
	var m := moisture[idx(clampi(int(round(g.x)), 0, n), clampi(int(round(g.y)), 0, n))]
	return FOREST if m + j * 0.05 > 0.55 else GRASS


func _surface_mat(p: Vector2) -> String:
	var b := biome_at(p)
	match b:
		WATER:
			return "sand" if WATER_Y - w.terrain_y(p.x, p.y) < 0.7 + _jitter.get_noise_2d(p.x * 0.7, p.y * 0.7) * 0.4 else "lakebed"
		SAND:
			return "sand"
		ROCK:
			return "rock"
	return "grass"


# ---------------------------------------------------------------- 地形网格

## 整片地形一个网格、一个材质（"terrain"）：每个顶点存沙 / 岩石 / 湖底的权重（顶点色 RGB），
## shader 里按权重混合草地 / 沙 / 岩石 / 湖底贴图，交界清晰但形状不规则，不会沿三角形走成锯齿。
## 顶点法线由相邻高度差算出，整片地形光照连续
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
			var sand := 1.0 - smoothstep(SAND_H - 0.1, SAND_H + 0.1, above)
			var bed := smoothstep(0.45, 0.95, -above)
			var sl := slope_at(i, j)
			var rock := maxf(smoothstep(ROCK_SLOPE - 0.12, ROCK_SLOPE + 0.12, sl),
				smoothstep(LAND_H * 0.68, LAND_H * 0.8, above))
			if above < 0.0:
				rock = 0.0
			cols[k] = Color(sand, rock, bed, 1.0)
	var indices := PackedInt32Array()
	for j in n:
		for i in n:
			var a := idx(i, j)
			var b := idx(i + 1, j)
			var c := idx(i + 1, j + 1)
			var d := idx(i, j + 1)
			# 对角线选高度差小的那条，坡面更平顺。绕序与 MB.tri 一致：从上方看是正面
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
	mesh.surface_set_material(0, Mats.get_mat("terrain"))
	batch.add_static(mesh, Transform3D.IDENTITY, false)
	# 水域登记（树、兴趣点不进水）
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

## 以 p 为中心、半径 r 内坡度都小于 max_slope，且在陆地上
func gentle(p: Vector2, r: float, max_slope: float) -> bool:
	for d in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r),
			Vector2(r, r) * 0.7, Vector2(-r, r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, -r) * 0.7]:
		var q: Vector2 = p + d
		if absf(q.x) > H - 1.0 or absf(q.y) > H - 1.0:
			return false
		if w.terrain_y(q.x, q.y) < WATER_Y + SAND_H or slope(q) > max_slope:
			return false
	return true


func _choose_pois() -> void:
	var kinds: Array[String] = ["camp", "cabin", "ruins", "camp"]
	var want := 3 if w.size <= 112 else 4
	var min_gap := w.size * 0.28
	for attempt in 800:
		if pois.size() >= want:
			break
		var p := Vector2(rng.randf_range(-H + 9.0, H - 9.0), rng.randf_range(-H + 9.0, H - 9.0))
		var too_close := false
		for q in pois:
			if q.distance_to(p) < min_gap:
				too_close = true
		if too_close or not gentle(p, 5.0, 0.3):
			continue
		var rect := Rect2(p - Vector2(4.0, 4.0), Vector2(8.0, 8.0))
		if not pl.can_place_rect(P.LANDMARK, rect, 0.0, true):
			continue
		pl.add_rect(P.LANDMARK, rect, 0.0, true)
		_flatten(p, 4.5, 8.0)
		_poi_kinds.append(kinds[pois.size() % kinds.size()])
		pois.append(p)


## 半径 r_flat 内压平成中心高度，r_flat 到 r_blend 之间平滑过渡回原地形
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
				mb.box("stone", Vector3(c.x - half.x, y - 0.2, c.y - half.y), Vector3(c.x + half.x, y + hh, c.y + half.y))
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
				fire.ngon_frustum("rock", Vector3(p.x + cos(a) * 0.55, 0, p.y + sin(a) * 0.55), y - 0.05, y + 0.18, 0.14, 0.1, 5, a, true)
			fire.tube("trunk", Vector3(p.x - 0.35, y + 0.08, p.y - 0.1), Vector3(p.x + 0.35, y + 0.12, p.y + 0.1), 0.06, 0.06, 6)
			fire.tube("trunk", Vector3(p.x - 0.1, y + 0.08, p.y + 0.35), Vector3(p.x + 0.1, y + 0.12, p.y - 0.35), 0.06, 0.06, 6)
			fire.ngon_frustum("bulb", Vector3(p.x, 0, p.y), y + 0.1, y + 0.45, 0.16, 0.0, 5, 0.0, false)
			batch.add_static(fire.commit(), Transform3D.IDENTITY)
			pl.solid_circles.append(Vector3(p.x, p.y, 0.7))
			var bench := Props.build_bench("log")
			for k in 3:
				var a := TAU * k / 3.0 + rng.randf() * 0.5
				var bp := p + Vector2(cos(a), sin(a)) * 2.0
				batch.add_static(bench, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(bp.x, w.ground_y(bp.x, bp.y), bp.y)))
				pl.solid_circles.append(Vector3(bp.x, bp.y, 0.6))
			var crate := Props.build_crate()
			var cp := p + Vector2(2.8, -2.4)
			batch.add_static(crate, Transform3D(Basis(Vector3.UP, 0.3), Vector3(cp.x, w.ground_y(cp.x, cp.y), cp.y)))
			batch.add_static(Props.build_barrel(), Transform3D(Basis(), Vector3(cp.x + 0.9, w.ground_y(cp.x + 0.9, cp.y + 0.4), cp.y + 0.4)))
			pl.solid_circles.append(Vector3(cp.x + 0.4, cp.y, 0.8))


func _scatter_rocks_around(p: Vector2, count: int, radius: float) -> void:
	var rocks := [Trees.build_rock(4100), Trees.build_rock(4101), Trees.build_rock(4102)]
	for k in count:
		var a := rng.randf() * TAU
		var q := p + Vector2(cos(a), sin(a)) * rng.randf_range(radius * 0.5, radius)
		var s := rng.randf_range(0.6, 1.1)
		batch.add_plant(rocks[k % rocks.size()], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.8, s)), Vector3(q.x, w.ground_y(q.x, q.y) - 0.05, q.y)))


# ---------------------------------------------------------------- 小路（A*）

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
			var sl := slope_at(i, j)
			if h < WATER_Y + 0.05 or w.walk_block[idx(i, j)] != 0:
				astar.set_point_solid(Vector2i(i, j), true)
			else:
				var b := biome_at(w.vert_xz(i, j))
				astar.set_point_weight_scale(Vector2i(i, j), 1.0 + sl * 6.0 + (1.5 if b == FOREST else 0.0) + (2.0 if b == ROCK else 0.0))
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
	# 画小路：每格一块土路面片，四个角贴着地形（跟着起伏），略高出地面
	var mb := MB.new()
	for c: Vector2i in path_cells:
		var p := w.vert_xz(c.x, c.y)
		var r := 0.62
		var q := [p + Vector2(-r, -r), p + Vector2(r, -r), p + Vector2(r, r), p + Vector2(-r, r)]
		var pts: Array = []
		for v: Vector2 in q:
			pts.append(Vector3(v.x, w.terrain_y(v.x, v.y) + 0.025, v.y))
		mb.face("dirt", [pts[0], pts[1], pts[2]], Vector3.UP)
		mb.face("dirt", [pts[0], pts[2], pts[3]], Vector3.UP)
		pl.add_rect(P.PATH, Rect2(p - Vector2.ONE * 0.6, Vector2.ONE * 1.2))
	batch.add_static(mb.commit(), Transform3D.IDENTITY, false)


# ---------------------------------------------------------------- 植被

func _scatter() -> void:
	_town._variants()
	var attempts := int(w.size * w.size * 0.5 * w.tree_density)
	for k in attempts:
		var p := Vector2(rng.randf_range(-H + 1.0, H - 1.0), rng.randf_range(-H + 1.0, H - 1.0))
		var b := biome_at(p)
		var keep: float = {FOREST: 1.0, GRASS: 0.12, ROCK: 0.05, SAND: 0.0, WATER: 0.0}[b]
		if rng.randf() > keep or slope(p) > 0.45:
			continue
		var pine := rng.randf() < (0.8 if b == FOREST else 0.35)
		var mesh: ArrayMesh = _town._pines[rng.randi_range(0, _town._pines.size() - 1)] if pine \
			else _town._broads[rng.randi_range(0, _town._broads.size() - 1)]
		_tree_at(p, mesh, rng.randf_range(0.8, 1.25), pine)
	# 灌木和石头
	for k in int(w.size * w.size * 0.03 * w.bush_density):
		var p := Vector2(rng.randf_range(-H + 1.0, H - 1.0), rng.randf_range(-H + 1.0, H - 1.0))
		var b := biome_at(p)
		if b == WATER or b == SAND or slope(p) > 0.6:
			continue
		if b == ROCK or rng.randf() < 0.25:
			_rock_at(p, rng.randf_range(0.7, 1.6))
		elif rng.randf() < 0.5:
			_bush_at(p, rng.randf_range(0.7, 1.1))


## 物体放在坡上时往下埋一点，避免底部一侧悬空
func _sink(p: Vector2, r: float) -> float:
	return slope(p) * r + 0.03


func _tree_at(p: Vector2, mesh: ArrayMesh, s: float, pine: bool) -> void:
	var y := w.ground_y(p.x, p.y) - _sink(p, 0.3 * s)
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
	batch.add_plant(mesh, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, w.ground_y(p.x, p.y) - _sink(p, r), p.y)), _town.tint(0.1))
	pl.add_circle(P.BUSH, p, r)
	pl.solid_circles.append(Vector3(p.x, p.y, r * 0.8))


func _rock_at(p: Vector2, s: float) -> void:
	var mesh: ArrayMesh = _town._rocks[rng.randi_range(0, _town._rocks.size() - 1)]
	var r: float = _town._canopy[mesh] * s
	if not pl.can_place(P.ROCK, p, r):
		return
	batch.add_plant(mesh, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)), Vector3(p.x, w.ground_y(p.x, p.y) - _sink(p, r), p.y)), _town.tint(0.08))
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
				var q := p + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
				batch.add_plant(weeds[rng.randi_range(0, 2)], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)),
					Vector3(q.x, w.terrain_y(q.x, q.y) - 0.03, q.y)))
	if count > 60:
		w.add_fish(Rect2(lo, hi - lo), clampi(count / 25, 8, 30))
