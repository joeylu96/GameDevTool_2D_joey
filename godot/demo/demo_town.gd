extends Node3D
## 演示用的简易小镇（手写布局）。正式的小镇/野外生成器在 P2 实现，
## 这里只为验证天气、昼夜、统一材质，以及角色在场景里走动。
##
## 对外查询（给角色、鱼群用）：ground_y(x, z)、water_depth(x, z)、can_stand(Vector2)、bed_y(d)

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")
const House := preload("res://addons/pixel_world/assets/placeholder/pw_house_builder.gd")
const Trees := preload("res://addons/pixel_world/assets/placeholder/pw_tree_builder.gd")
const Props := preload("res://addons/pixel_world/assets/placeholder/pw_props_builder.gd")
const WATER_SHADER := preload("res://addons/pixel_world/shaders/water.gdshader")
const POOL_SHADER := preload("res://addons/pixel_world/shaders/light_pool.gdshader")

const HALF := 40.0
const SHORE_Z := 22.0
const ROAD_W := 2.0  # 半宽
const CURB := 0.25   # 路缘石宽
const CURB_H := 0.1
const WATER_Y := -0.45
## 湖底剖面（必须和 water.gdshader 的 slope1/bend1/slope2/bend2 一致）
const BED_SLOPE1 := 0.35
const BED_BEND1 := 3.0
const BED_SLOPE2 := 0.4
const BED_BEND2 := 9.0
## 角色能走进的最大水深（米）
const WADE_DEPTH := 0.65
const PIER := Rect2(8.0, SHORE_Z - 1.0, 2.5, 10.0)

var _rng := RandomNumberGenerator.new()
## 装饰物（灌木、石头、土路边缘）用单独的随机数，不打乱房屋和树的布局
var _deco := RandomNumberGenerator.new()
var _blocked: Array[Rect2] = []   # 摆放用：这些区域不再种树 / 放东西
var _bush_spots: Array[Vector3] = []
var _lamp_spots: Array[Vector3] = []
# 碰撞（角色用）：矩形 + 圆（x, z, 半径）
var _solid_rects: Array[Rect2] = []
var _solid_circles: Array[Vector3] = []

var fish: PWFishSchool


func build(seed_value := 7) -> void:
	_rng.seed = seed_value
	_deco.seed = seed_value * 7919
	_build_ground()
	_build_lake()
	_build_roads()
	_build_houses()
	_build_lighthouse()
	_build_lamps()
	_build_props()
	_build_trees()


func _add_mesh(mesh: Mesh, xf := Transform3D.IDENTITY, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# ---------------------------------------------------------------- 查询

## 湖底高度：d = 离岸距离（z - SHORE_Z）。近岸缓坡浅滩，往外逐渐变深
static func bed_y(d: float) -> float:
	if d <= 0.0:
		return 0.0
	if d < BED_BEND1:
		return -BED_SLOPE1 * d
	var y1 := -BED_SLOPE1 * BED_BEND1
	if d < BED_BEND2:
		return y1 - BED_SLOPE2 * (d - BED_BEND1)
	return y1 - BED_SLOPE2 * (BED_BEND2 - BED_BEND1) - 0.05 * minf(d - BED_BEND2, 6.0)


func ground_y(x: float, z: float) -> float:
	if PIER.has_point(Vector2(x, z)):
		return 0.05
	return bed_y(z - SHORE_Z)


func water_depth(x: float, z: float) -> float:
	if PIER.has_point(Vector2(x, z)):
		return 0.0
	return maxf(WATER_Y - bed_y(z - SHORE_Z), 0.0)


func can_stand(p: Vector2) -> bool:
	if p.x < -HALF + 0.5 or p.x > HALF - 0.5 or p.y < -HALF + 0.5:
		return false
	if water_depth(p.x, p.y) > WADE_DEPTH:
		return false
	for r in _solid_rects:
		if r.has_point(p):
			return false
	for c in _solid_circles:
		if Vector2(c.x, c.y).distance_squared_to(p) < c.z * c.z:
			return false
	return true


# ---------------------------------------------------------------- 地面 / 湖

func _build_ground() -> void:
	var mb := MB.new()
	mb.box("grass", Vector3(-HALF, -0.5, -HALF), Vector3(HALF, 0.0, SHORE_Z), true, false, false)
	_add_mesh(mb.commit())
	# 岸边碎石带：内侧边缘每半米错开几个像素（独立随机数，不影响其他布局）
	var srng := RandomNumberGenerator.new()
	srng.seed = 515
	var sh := MB.new()
	var sy := 0.015
	var xx := -HALF
	var prev_in := Vector3(xx, sy, SHORE_Z - 0.9)
	while xx < HALF - 0.01:
		var nx := minf(xx + 0.5, HALF)
		var cur_in := Vector3(nx, sy, SHORE_Z - 0.9 + srng.randi_range(-6, 6) * MB.SNAP)
		sh.face("shore", [prev_in, cur_in, Vector3(nx, sy, SHORE_Z), Vector3(xx, sy, SHORE_Z)], Vector3.UP)
		prev_in = cur_in
		xx = nx
	_add_mesh(sh.commit(), Transform3D.IDENTITY, false)
	# 码头（木桩一直插到湖底）
	var pier := MB.new()
	pier.box("boards", Vector3(PIER.position.x, -0.2, PIER.position.y), Vector3(PIER.end.x, 0.05, PIER.end.y))
	for z in [SHORE_Z + 3.0, SHORE_Z + 6.0, SHORE_Z + 8.6]:
		for x in [8.2, 10.1]:
			pier.box("trunk", Vector3(x, -4.0, z), Vector3(x + 0.25, 0.25, z + 0.25))
	_add_mesh(pier.commit())


## 湖：沙质缓坡浅滩 → 泥质深水的湖底网格 + 半透明水面 + 水草、水下石头、鱼群
func _build_lake() -> void:
	var lr := RandomNumberGenerator.new()
	lr.seed = 616
	var ds := [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 11.0, 14.0, 20.0, 30.0, 40.0]
	var x0 := -HALF - 20.0
	var cols := int((HALF * 2.0 + 40.0) / 2.0) + 1
	var ys := []
	for j in ds.size():
		var row := PackedFloat32Array()
		for i in cols:
			var y := bed_y(ds[j])
			if ds[j] > 0.4:
				y += lr.randf_range(-0.07, 0.07)
			row.append(y)
		ys.append(row)
	var bed := MB.new()
	for j in ds.size() - 1:
		for i in cols - 1:
			var xa := x0 + i * 2.0
			var xb := xa + 2.0
			var za: float = SHORE_Z + ds[j]
			var zb: float = SHORE_Z + ds[j + 1]
			var pts := [Vector3(xa, ys[j][i], za), Vector3(xb, ys[j][i + 1], za),
				Vector3(xb, ys[j + 1][i + 1], zb), Vector3(xa, ys[j + 1][i], zb)]
			var dmid: float = (ds[j] + ds[j + 1]) * 0.5
			bed.face("sand" if dmid < 4.5 + lr.randf_range(-1.6, 1.6) else "lakebed", pts, Vector3.UP)
	_add_mesh(bed.commit(), Transform3D.IDENTITY, false)
	# 水面：告诉 shader 岸线和湖底剖面，用来算水深（透明度、颜色）、画浪花、由岸向外结冰
	var water := PlaneMesh.new()
	water.size = Vector2(HALF * 2.0 + 40.0, 40.0)
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	wm.set_shader_parameter("shore_z", SHORE_Z)
	wm.set_shader_parameter("slope1", BED_SLOPE1)
	wm.set_shader_parameter("bend1", BED_BEND1)
	wm.set_shader_parameter("slope2", BED_SLOPE2)
	wm.set_shader_parameter("bend2", BED_BEND2)
	water.material = wm
	_add_mesh(water, Transform3D(Basis(), Vector3(0, WATER_Y, SHORE_Z + 20.0)), false)
	# 水草和水下石头
	var weeds: Array[Mesh] = [Props.build_weed(5000), Props.build_weed(5001), Props.build_weed(5002)]
	var rocks: Array[Mesh] = [Trees.build_rock(4100), Trees.build_rock(4101)]
	var xforms := {}
	for i in 90:
		var d := lr.randf_range(1.6, 7.0)
		var x := lr.randf_range(-HALF, HALF)
		if x > 7.0 and x < 11.5:
			continue  # 码头下面留空
		var s := lr.randf_range(0.8, 1.5)
		var xf := Transform3D(Basis(Vector3.UP, lr.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, bed_y(d), SHORE_Z + d))
		_push(xforms, weeds[i % weeds.size()], xf)
	for i in 28:
		var d := lr.randf_range(1.4, 8.0)
		var x := lr.randf_range(-HALF, HALF)
		var s := lr.randf_range(0.8, 1.9)
		var xf := Transform3D(Basis(Vector3.UP, lr.randf() * TAU).scaled(Vector3(s, s * 0.7, s)), Vector3(x, bed_y(d) - 0.05, SHORE_Z + d))
		_push(xforms, rocks[i % rocks.size()], xf)
	_flush_multimesh(xforms, false)
	# 鱼群：在浅水带游动
	fish = PWFishSchool.new()
	fish.name = "Fish"
	fish.area = Rect2(-HALF + 2.0, SHORE_Z + 1.8, HALF * 2.0 - 4.0, 3.4)
	fish.water_y = WATER_Y
	fish.bed_height = func(x: float, z: float) -> float: return bed_y(z - SHORE_Z)
	add_child(fish)


# ---------------------------------------------------------------- 道路 / 房屋

func _build_roads() -> void:
	var mb := MB.new()
	var y := 0.02
	# 东西主街
	mb.face("cobble", [Vector3(-HALF, y, -ROAD_W), Vector3(HALF, y, -ROAD_W), Vector3(HALF, y, ROAD_W), Vector3(-HALF, y, ROAD_W)], Vector3.UP)
	# 南北支路
	mb.face("cobble", [Vector3(-ROAD_W, y, -HALF), Vector3(ROAD_W, y, -HALF), Vector3(ROAD_W, y, -ROAD_W), Vector3(-ROAD_W, y, -ROAD_W)], Vector3.UP)
	# 土路（通往码头）：分段拼接，两侧边缘逐段错开几个像素，不再是一条笔直的线
	var steps := 40
	var prev_l := Vector3(ROAD_W, y, ROAD_W)
	var prev_r := Vector3(ROAD_W + 3.0, y, ROAD_W)
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var z := lerpf(ROAD_W, SHORE_Z - 1.0, t)
		var xl := lerpf(ROAD_W, 8.0, t)
		var xr := lerpf(ROAD_W + 3.0, 10.5, t)
		if i < steps:
			xl += _deco.randi_range(-2, 2) * MB.SNAP * 2.0
			xr += _deco.randi_range(-2, 2) * MB.SNAP * 2.0
		var l := Vector3(xl, y, z)
		var r := Vector3(xr, y, z)
		mb.face("dirt", [prev_l, prev_r, r, l], Vector3.UP)
		prev_l = l
		prev_r = r
	_add_mesh(mb.commit(), Transform3D.IDENTITY, false)
	# 路缘石：主街两侧 + 支路两侧，转角处连成 L 形；南侧在土路路口断开
	var curb := MB.new()
	var c := CURB
	curb.box("curb", Vector3(-HALF, 0, -ROAD_W - c), Vector3(-ROAD_W, CURB_H, -ROAD_W))
	curb.box("curb", Vector3(ROAD_W, 0, -ROAD_W - c), Vector3(HALF, CURB_H, -ROAD_W))
	curb.box("curb", Vector3(-HALF, 0, ROAD_W), Vector3(ROAD_W, CURB_H, ROAD_W + c))
	curb.box("curb", Vector3(ROAD_W + 3.0, 0, ROAD_W), Vector3(HALF, CURB_H, ROAD_W + c))
	curb.box("curb", Vector3(-ROAD_W - c, 0, -HALF), Vector3(-ROAD_W, CURB_H, -ROAD_W - c))
	curb.box("curb", Vector3(ROAD_W, 0, -HALF), Vector3(ROAD_W + c, CURB_H, -ROAD_W - c))
	_add_mesh(curb.commit())
	_blocked.append(Rect2(-HALF, -ROAD_W - 0.5, HALF * 2.0, ROAD_W * 2.0 + 1.0))
	_blocked.append(Rect2(-ROAD_W - 0.5, -HALF, ROAD_W * 2.0 + 1.0, HALF))
	_blocked.append(Rect2(ROAD_W, ROAD_W, 9.0, SHORE_Z))


func _build_houses() -> void:
	# 北侧两排、南侧一排，门朝主街
	var rows := [
		{"z_front": -ROAD_W - 2.0, "side": -1},
		{"z_front": -ROAD_W - 14.0, "side": -1},
		{"z_front": ROAD_W + 2.0, "side": 1},
	]
	for row: Dictionary in rows:
		var x := -HALF + 3.0
		while x < HALF - 6.0:
			var p := House.random_params(_rng)
			var fp := House.footprint(p)
			var cx := x + fp.x * 0.5
			if absf(cx) < ROAD_W + fp.x * 0.5 + 1.0 and row.side < 0:
				x = ROAD_W + 1.5
				continue
			if row.side > 0 and cx > ROAD_W - fp.x * 0.5 - 1.0 and cx < 13.0:
				x = 13.0
				continue
			var cz: float = row.z_front + row.side * fp.y * 0.5
			var rect := Rect2(cx - fp.x * 0.5, cz - fp.y * 0.5, fp.x, fp.y)
			if row.side > 0 and rect.end.y > SHORE_Z - 2.0:
				break
			var rot := 0.0 if row.side < 0 else PI
			# side<0：门朝 +Z（主街）；side>0：旋转 180° 朝 -Z
			_add_mesh(House.build(p), Transform3D(Basis(Vector3.UP, rot), Vector3(cx, 0, cz)))
			_blocked.append(rect.grow(1.0))
			_solid_rects.append(Rect2(cx - p.width * 0.5 - 0.25, cz - p.depth * 0.5 - 0.25, p.width + 0.5, p.depth + 0.5))
			# 门前院子留空（不种树），一直到路边
			if row.side < 0:
				_blocked.append(Rect2(rect.position.x, rect.end.y, fp.x, 2.5))
			else:
				_blocked.append(Rect2(rect.position.x, rect.position.y - 1.9, fp.x, 1.9))
			_build_house_fence(row.side, rect, cx)
			# 门两侧的灌木（避开门前台阶）
			var dir := -float(row.side)
			var zf: float = cz + dir * (p.depth * 0.5 + 0.6)
			for sx in [-1.0, 1.0]:
				if _deco.randf() < 0.75:
					var bx: float = cx + sx * _deco.randf_range(1.8, maxf(1.9, p.width * 0.5 - 0.6))
					_bush_spots.append(Vector3(bx, 0, zf))
			x += fp.x + _rng.randf_range(2.0, 5.0)


func _build_lamps() -> void:
	var lamp := Trees.build_lamp()
	var pool := PlaneMesh.new()
	pool.size = Vector2(5, 5)
	var pm := ShaderMaterial.new()
	pm.shader = POOL_SHADER
	pool.material = pm
	var spots: Array[Vector3] = []
	var x := -HALF + 5.0
	while x < HALF:
		if absf(x) > ROAD_W + 1.5:
			spots.append(Vector3(x, 0, -ROAD_W - 0.6))
			spots.append(Vector3(x + 4.5, 0, ROAD_W + 0.6))
		x += 9.0
	var z := -HALF + 6.0
	while z < -ROAD_W - 2.0:
		spots.append(Vector3(ROAD_W + 0.6, 0, z))
		z += 9.0
	for s in spots:
		_add_mesh(lamp, Transform3D(Basis(), s))
		_add_mesh(pool, Transform3D(Basis(), s + Vector3(0, 0.04, 0)), false)
		_solid_circles.append(Vector3(s.x, s.z, 0.25))
	_lamp_spots = spots


## 房屋篱笆：北侧房屋在门前围一道（门口留缺口），南侧房屋在后院（朝海一侧）围一道
func _build_house_fence(side: int, rect: Rect2, door_x: float) -> void:
	var x0 := rect.position.x + 0.3
	var length := rect.size.x - 0.6
	if side < 0:
		if _deco.randf() > 0.6:
			return
		var z := rect.end.y + 1.15  # 灌木和路灯之间
		var gap := [door_x - x0 - 0.8, door_x - x0 + 0.8]
		_add_mesh(Props.build_fence(length, [gap]), Transform3D(Basis(), Vector3(x0, 0, z)))
		_solid_rects.append(Rect2(x0, z - 0.15, gap[0], 0.3))
		_solid_rects.append(Rect2(x0 + gap[1], z - 0.15, length - gap[1], 0.3))
	else:
		var z := rect.end.y + 1.0
		if z > SHORE_Z - 2.2 or _deco.randf() > 0.7:
			return
		_add_mesh(Props.build_fence(length), Transform3D(Basis(), Vector3(x0, 0, z)))
		_blocked.append(Rect2(x0, z - 0.6, length, 1.2))
		_solid_rects.append(Rect2(x0, z - 0.15, length, 0.3))


## 灯塔：放在岸边、一半伸进湖里；从几个候选位置里挑第一个不和房屋 / 道路重叠的
func _build_lighthouse() -> void:
	var z := SHORE_Z + 1.4
	for x in [-9.0, -15.0, -4.0, -21.0, 18.0, 24.0]:
		var r := Rect2(x - 3.2, z - 3.2, 6.4, 6.4)
		var ok := true
		for b in _blocked:
			if b.intersects(r):
				ok = false
				break
		if ok:
			_add_mesh(Props.build_lighthouse(), Transform3D(Basis(), Vector3(x, 0, z)))
			_blocked.append(r)
			_solid_circles.append(Vector3(x, z, 3.1))
			return


## 长椅（主街南侧，两盏路灯之间，背对房屋面朝街道）+ 码头边的木箱和木桶
func _build_props() -> void:
	var bench := Props.build_bench()
	for s in _lamp_spots:
		if s.z < 0.0:
			continue
		var p := Vector3(s.x + 4.5, 0, ROAD_W + CURB + 0.55)
		if p.x > HALF - 1.5 or (p.x > -0.5 and p.x < ROAD_W + 4.5) or _deco.randf() > 0.6:
			continue  # 出界 / 挡住土路口 / 随机留空
		_add_mesh(bench, Transform3D(Basis(Vector3.UP, PI), p))
		_blocked.append(Rect2(p.x - 1.0, p.z - 0.5, 2.0, 1.0))
		_solid_rects.append(Rect2(p.x - 0.85, p.z - 0.3, 1.7, 0.6))
	var crate := Props.build_crate()
	var crate_s := Props.build_crate(0.5)
	var barrel := Props.build_barrel()
	var items := [
		[crate, Vector3(11.6, 0, 19.6), 0.2],
		[crate_s, Vector3(11.6, 0.7, 19.6), -0.35],
		[crate, Vector3(12.5, 0, 20.5), 0.5],
		[barrel, Vector3(7.0, 0, 20.4), 0.0],
		[barrel, Vector3(6.4, 0, 19.6), 0.0],
		[barrel, Vector3(10.0, 0.05, 25.6), 0.0],
		[crate, Vector3(8.65, 0.05, 28.2), 0.1],
	]
	for it: Array in items:
		_add_mesh(it[0], Transform3D(Basis(Vector3.UP, it[2]), it[1]))
		var pos: Vector3 = it[1]
		_solid_circles.append(Vector3(pos.x, pos.z, 0.5))
	_blocked.append(Rect2(10.8, 18.8, 2.6, 2.6))
	_blocked.append(Rect2(5.8, 19.0, 1.8, 2.0))


# ---------------------------------------------------------------- 植被

func _build_trees() -> void:
	var pines: Array[Mesh] = [Trees.build_pine(1000), Trees.build_pine(1001), Trees.build_pine(1002)]
	var broads: Array[Mesh] = [Trees.build_broadleaf(2000), Trees.build_broadleaf(2001)]
	var bushes: Array[Mesh] = [Trees.build_bush(3000), Trees.build_bush(3001), Trees.build_bush(3002)]
	var rocks: Array[Mesh] = [Trees.build_rock(4000), Trees.build_rock(4001), Trees.build_rock(4002)]
	var xforms := {}  # Mesh -> Array[Transform3D]
	var placed: Array[Vector2] = []
	for attempt in 2500:
		var p := Vector2(_rng.randf_range(-HALF + 1.0, HALF - 1.0), _rng.randf_range(-HALF + 1.0, SHORE_Z - 1.5))
		# 北边是林带：越往北越密
		var keep := 0.35 if p.y > -28.0 else 1.0
		if _rng.randf() > keep:
			continue
		if not _free(p, placed, 3.2):
			continue
		placed.append(p)
		var s := _rng.randf_range(0.75, 1.2)
		var b := Basis(Vector3.UP, _rng.randi_range(0, 3) * PI * 0.5).scaled(Vector3(s, s, s))
		var variant := _rng.randi_range(0, 2)
		# 林带几乎全是松树；镇子里松树和阔叶树混种
		var broad_chance := 0.08 if p.y < -28.0 else 0.45
		var is_broad := _deco.randf() < broad_chance
		var mesh: Mesh = broads[variant % broads.size()] if is_broad else pines[variant]
		_push(xforms, mesh, Transform3D(b, Vector3(p.x, 0, p.y)))
		_solid_circles.append(Vector3(p.x, p.y, 0.35 if is_broad else 0.9 * s))
	# 灌木：房门两侧 + 空地上零星几丛
	for spot in _bush_spots:
		_push(xforms, bushes[_deco.randi_range(0, bushes.size() - 1)], _rand_xf(spot, 0.8, 1.15))
		_solid_circles.append(Vector3(spot.x, spot.z, 0.5))
	var scattered := 0
	for attempt in 600:
		if scattered >= 30:
			break
		var p := Vector2(_deco.randf_range(-HALF + 1.0, HALF - 1.0), _deco.randf_range(-HALF + 1.0, SHORE_Z - 1.0))
		if not _free(p, placed, 1.8):
			continue
		placed.append(p)
		scattered += 1
		_push(xforms, bushes[_deco.randi_range(0, bushes.size() - 1)], _rand_xf(Vector3(p.x, 0, p.y), 0.7, 1.1))
		_solid_circles.append(Vector3(p.x, p.y, 0.5))
	# 石头：沿岸一排 + 林间几块
	for i in 40:
		var z := SHORE_Z - _deco.randf_range(0.4, 1.4) if i < 24 else _deco.randf_range(-HALF + 1.0, -10.0)
		var p := Vector2(_deco.randf_range(-HALF + 1.0, HALF - 1.0), z)
		if not _free(p, placed, 1.2):
			continue
		placed.append(p)
		_push(xforms, rocks[_deco.randi_range(0, rocks.size() - 1)], _rand_xf(Vector3(p.x, 0, p.y), 0.7, 1.4))
		_solid_circles.append(Vector3(p.x, p.y, 0.45))
	_flush_multimesh(xforms, true)


## MultiMesh 批量渲染（Web 性能）：每种网格一个
func _flush_multimesh(xforms: Dictionary, shadows: bool) -> void:
	for mesh: Mesh in xforms:
		var list: Array = xforms[mesh]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## p 不在道路 / 房屋范围内，且离已放置的物体至少 min_dist
func _free(p: Vector2, placed: Array[Vector2], min_dist: float) -> bool:
	for r in _blocked:
		if r.has_point(p):
			return false
	for q in placed:
		if q.distance_squared_to(p) < min_dist * min_dist:
			return false
	return true


func _push(xforms: Dictionary, mesh: Mesh, xf: Transform3D) -> void:
	if not xforms.has(mesh):
		xforms[mesh] = []
	xforms[mesh].append(xf)


## 随机朝向 + 等比缩放
func _rand_xf(pos: Vector3, s_min: float, s_max: float) -> Transform3D:
	var s := _deco.randf_range(s_min, s_max)
	return Transform3D(Basis(Vector3.UP, _deco.randf() * TAU).scaled(Vector3(s, s, s)), pos)
