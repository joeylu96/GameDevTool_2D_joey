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

## 静态合批：不会动的模型按「区块 × 是否投影」分组，同一材质的几何合并进一个 surface，
## 几百个物体的绘制调用降到几十个（性能）。区块边长 CHUNK 米，保留一定的视锥剔除。
const CHUNK := 40.0
var _batches := {}  # "ix,iz,shadow" -> {Material: SurfaceTool}


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
	_flush_static()


## 放一个静态模型。程序生成的 ArrayMesh 进入合批；其它（水面等内置网格）直接实例化
func _add_mesh(mesh: Mesh, xf := Transform3D.IDENTITY, shadows := true) -> void:
	if mesh is ArrayMesh:
		var o := xf.origin
		var key := "%d,%d,%s" % [floori((o.x + 60.0) / CHUNK), floori((o.z + 60.0) / CHUNK), shadows]
		if not _batches.has(key):
			_batches[key] = {}
		var groups: Dictionary = _batches[key]
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if not groups.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[mat] = st
			(groups[mat] as SurfaceTool).append_from(mesh, s, xf)
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _flush_static() -> void:
	for key: String in _batches:
		var groups: Dictionary = _batches[key]
		var mesh := ArrayMesh.new()
		for mat: Material in groups:
			mesh = (groups[mat] as SurfaceTool).commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		var mi := MeshInstance3D.new()
		mi.name = "Static_" + key.replace(",", "_")
		mi.mesh = mesh
		if key.ends_with("false"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_batches.clear()


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
	_add_mesh(mb.commit(), Transform3D.IDENTITY, false)  # 平地投不出可见的影子，不进阴影贴图
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
	# 码头：一块块独立的甲板（板间留缝，低对比木纹，不晃眼）+ 三根托梁 + 插到湖底的木桩 + 系船柱
	var pier := MB.new()
	var z := PIER.position.y
	while z < PIER.end.y - 0.05:
		var z1 := minf(z + 0.26, PIER.end.y)
		pier.box("deck", Vector3(PIER.position.x, -0.04, z), Vector3(PIER.end.x, 0.05, z1 - 0.035))
		z += 0.26
	for bx in [PIER.position.x + 0.15, PIER.get_center().x, PIER.end.x - 0.15]:
		pier.box("trunk", Vector3(bx - 0.08, -0.3, PIER.position.y), Vector3(bx + 0.08, -0.04, PIER.end.y), false, true)
	for pz in [SHORE_Z + 3.0, SHORE_Z + 6.0, SHORE_Z + 8.6]:
		for px in [8.2, 10.1]:
			pier.box("trunk", Vector3(px, -4.0, pz), Vector3(px + 0.25, -0.04, pz + 0.25), false)
	for c in [Vector2(PIER.position.x + 0.15, PIER.end.y - 0.2), Vector2(PIER.end.x - 0.15, PIER.end.y - 0.2),
			Vector2(PIER.position.x + 0.15, SHORE_Z + 4.5), Vector2(PIER.end.x - 0.15, SHORE_Z + 4.5)]:
		pier.ngon_frustum("trunk", Vector3(c.x, 0, c.y), 0.05, 0.45, 0.11, 0.1, 8, 0.0, true)
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
	# 每个款式 × 颜色只生成一次网格（合批后没有额外开销）；每盏灯随机挑款式、颜色和朝向
	var lamp_meshes := {}
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
	var pools := MultiMesh.new()
	pools.transform_format = MultiMesh.TRANSFORM_3D
	pools.mesh = pool
	pools.instance_count = spots.size()
	for i in spots.size():
		var s := spots[i]
		var style: String = Trees.LAMP_STYLES[_deco.randi_range(0, Trees.LAMP_STYLES.size() - 1)]
		var metal: String = Trees.LAMP_METALS[_deco.randi_range(0, Trees.LAMP_METALS.size() - 1)]
		var key := style + "/" + metal
		if not lamp_meshes.has(key):
			lamp_meshes[key] = Trees.build_lamp(style, metal)
		# 悬臂灯把灯箱伸向道路一侧（绕 Y 转 θ 后，局部 +X 指向 (cosθ, 0, -sinθ)）
		var yaw := 0.0
		if style == "arm":
			if absf(s.x - (ROAD_W + 0.6)) < 0.1 and s.z < -ROAD_W - 1.0:
				yaw = PI           # 支路东侧：伸向 -X
			elif s.z < 0.0:
				yaw = -PI * 0.5    # 主街北侧：伸向 +Z
			else:
				yaw = PI * 0.5     # 主街南侧：伸向 -Z
		var basis := Basis(Vector3.UP, yaw)
		_add_mesh(lamp_meshes[key], Transform3D(basis, s))
		pools.set_instance_transform(i, Transform3D(Basis(), s + basis * Trees.lamp_light_offset(style) + Vector3(0, 0.04, 0)))
		_solid_circles.append(Vector3(s.x, s.z, 0.25))
	var pmi := MultiMeshInstance3D.new()
	pmi.name = "LightPools"
	pmi.multimesh = pools
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pmi)
	_lamp_spots = spots


## 房屋篱笆：北侧房屋在门前围一道（门口留缺口），南侧房屋在后院（朝海一侧）围一道
func _build_house_fence(side: int, rect: Rect2, door_x: float) -> void:
	var x0 := rect.position.x + 0.3
	var length := rect.size.x - 0.6
	var style: String = Props.FENCE_STYLES[_deco.randi_range(0, Props.FENCE_STYLES.size() - 1)]
	if side < 0:
		if _deco.randf() > 0.6:
			return
		var z := rect.end.y + 1.15  # 灌木和路灯之间
		var gap := [door_x - x0 - 0.8, door_x - x0 + 0.8]
		_add_mesh(Props.build_fence(length, [gap], style), Transform3D(Basis(), Vector3(x0, 0, z)))
		_solid_rects.append(Rect2(x0, z - 0.15, gap[0], 0.3))
		_solid_rects.append(Rect2(x0 + gap[1], z - 0.15, length - gap[1], 0.3))
	else:
		var z := rect.end.y + 1.0
		if z > SHORE_Z - 2.2 or _deco.randf() > 0.7:
			return
		_add_mesh(Props.build_fence(length, [], style), Transform3D(Basis(), Vector3(x0, 0, z)))
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
	var benches := {}
	for s in _lamp_spots:
		if s.z < 0.0:
			continue
		var p := Vector3(s.x + 4.5, 0, ROAD_W + CURB + 0.55)
		if p.x > HALF - 1.5 or (p.x > -0.5 and p.x < ROAD_W + 4.5) or _deco.randf() > 0.6:
			continue  # 出界 / 挡住土路口 / 随机留空
		var bstyle: String = Props.BENCH_STYLES[_deco.randi_range(0, Props.BENCH_STYLES.size() - 1)]
		if not benches.has(bstyle):
			benches[bstyle] = Props.build_bench(bstyle)
		_add_mesh(benches[bstyle], Transform3D(Basis(Vector3.UP, PI), p))
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
	# 变体池：每种都按不同种子生成不同的形状；再加上每棵独立的朝向、宽高比例和色调，场景里不会有两棵一样的树
	var pines: Array[Mesh] = []
	for i in 10:
		pines.append(Trees.build_pine(1000 + i))
	var broad_styles := ["oak", "oak", "birch", "poplar", "autumn", "oak", "birch", "poplar", "oak", "autumn", "birch", "poplar"]
	var broads: Array[Mesh] = []
	for i in broad_styles.size():
		broads.append(Trees.build_broadleaf(2000 + i, broad_styles[i]))
	var bushes: Array[Mesh] = []
	for i in 8:
		bushes.append(Trees.build_bush(3000 + i))
	var rocks: Array[Mesh] = []
	for i in 8:
		rocks.append(Trees.build_rock(4000 + i))
	var xforms := {}  # Mesh -> [[Transform3D, 色调], ...]
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
		var yaw := _rng.randi_range(0, 3) * PI * 0.5 + _deco.randf() * TAU
		_rng.randi_range(0, 2)  # 保留原来的随机数消耗，树的位置和以前一致
		# 林带几乎全是松树；镇子里松树和阔叶树混种
		var broad_chance := 0.08 if p.y < -28.0 else 0.45
		var is_broad := _deco.randf() < broad_chance
		var mesh: Mesh = broads[_deco.randi_range(0, broads.size() - 1)] if is_broad else pines[_deco.randi_range(0, pines.size() - 1)]
		var sxz := s * _deco.randf_range(0.88, 1.12)
		var sy := s * _deco.randf_range(0.88, 1.2)
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sxz, sy, sxz))
		_push(xforms, mesh, Transform3D(b, Vector3(p.x, 0, p.y)), _tint(0.1))
		_solid_circles.append(Vector3(p.x, p.y, 0.35 if is_broad else 0.9 * sxz))
	# 灌木：房门两侧 + 空地上零星几丛
	for spot in _bush_spots:
		_push(xforms, bushes[_deco.randi_range(0, bushes.size() - 1)], _rand_xf(spot, 0.8, 1.15), _tint(0.1))
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
		_push(xforms, bushes[_deco.randi_range(0, bushes.size() - 1)], _rand_xf(Vector3(p.x, 0, p.y), 0.7, 1.1), _tint(0.1))
		_solid_circles.append(Vector3(p.x, p.y, 0.5))
	# 石头：沿岸一排 + 林间几块
	for i in 40:
		var z := SHORE_Z - _deco.randf_range(0.4, 1.4) if i < 24 else _deco.randf_range(-HALF + 1.0, -10.0)
		var p := Vector2(_deco.randf_range(-HALF + 1.0, HALF - 1.0), z)
		if not _free(p, placed, 1.2):
			continue
		placed.append(p)
		_push(xforms, rocks[_deco.randi_range(0, rocks.size() - 1)], _rand_xf(Vector3(p.x, 0, p.y), 0.7, 1.4), _tint(0.08))
		_solid_circles.append(Vector3(p.x, p.y, 0.45))
	_flush_multimesh(xforms, true)


## 植被合批（性能）：所有实例按区块、按材质合并成静态网格——几十种变体 × 每种 2~3 个材质
## 不再各占一次绘制调用（WebGL 上每次绘制调用开销很大）。
## 每个实例的色调写进顶点色 RGB，摇摆相位写进 UV2.x，所以合并后每棵树仍然颜色不同、各摆各的。
## 顶点变换用 Transform3D * PackedVector3Array（引擎内批量计算），启动开销很小。
func _flush_multimesh(xforms: Dictionary, shadows: bool) -> void:
	var chunks := {}  # "ix,iz" -> {Material: {"v": [...], "n": [...], "uv": [...], "uv2": [...], "c": [...]}}
	for mesh: Mesh in xforms:
		var surfaces := []
		for s in mesh.get_surface_count():
			surfaces.append([mesh.surface_get_arrays(s), mesh.surface_get_material(s)])
		for item: Array in xforms[mesh]:
			var xf: Transform3D = item[0]
			var tint: Color = item[1]
			tint = Color(tint.r, tint.g, tint.b, 1.0) if tint.a > 0.5 else Color.WHITE
			var key := "%d,%d" % [floori((xf.origin.x + 60.0) / CHUNK), floori((xf.origin.z + 60.0) / CHUNK)]
			if not chunks.has(key):
				chunks[key] = {}
			var groups: Dictionary = chunks[key]
			var nxf := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
			var phase := fposmod(xf.origin.x * 0.37 + xf.origin.z * 0.29, TAU) + 0.01
			for sf: Array in surfaces:
				var arr: Array = sf[0]
				var mat: Material = sf[1]
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
				cols.fill(tint)
				g.c.append(cols)
	for key: String in chunks:
		var groups: Dictionary = chunks[key]
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
		mi.name = "Plants_" + key.replace(",", "_")
		mi.mesh = mesh
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## p 不在道路 / 房屋范围内，且离已放置的物体至少 min_dist
func _free(p: Vector2, placed: Array[Vector2], min_dist: float) -> bool:
	for r in _blocked:
		if r.has_point(p):
			return false
	for q in placed:
		if q.distance_squared_to(p) < min_dist * min_dist:
			return false
	return true


func _push(xforms: Dictionary, mesh: Mesh, xf: Transform3D, tint := Color(1, 1, 1, 0)) -> void:
	if not xforms.has(mesh):
		xforms[mesh] = []
	xforms[mesh].append([xf, tint])


## 每个实例的随机色调：整体明暗 ± amount，三个通道各自再微调一点（偏黄 / 偏蓝 / 偏暗）
func _tint(amount: float) -> Color:
	var k := _deco.randf_range(1.0 - amount, 1.0 + amount * 0.6)
	return Color(k * _deco.randf_range(0.95, 1.05), k * _deco.randf_range(0.96, 1.04), k * _deco.randf_range(0.93, 1.05), 1.0)


## 随机朝向 + 等比缩放（高度再单独随机一点）
func _rand_xf(pos: Vector3, s_min: float, s_max: float) -> Transform3D:
	var s := _deco.randf_range(s_min, s_max)
	var sy := s * _deco.randf_range(0.85, 1.15)
	return Transform3D(Basis(Vector3.UP, _deco.randf() * TAU).scaled(Vector3(s, sy, s)), pos)
