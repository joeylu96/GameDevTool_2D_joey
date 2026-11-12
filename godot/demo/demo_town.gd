extends Node3D
## 演示用的简易小镇（手写布局）。正式的小镇/野外生成器在 P2 实现，
## 这里只为验证天气、昼夜和统一材质。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")
const House := preload("res://addons/pixel_world/assets/placeholder/pw_house_builder.gd")
const Trees := preload("res://addons/pixel_world/assets/placeholder/pw_tree_builder.gd")
const WATER_SHADER := preload("res://addons/pixel_world/shaders/water.gdshader")
const POOL_SHADER := preload("res://addons/pixel_world/shaders/light_pool.gdshader")

const HALF := 40.0
const SHORE_Z := 22.0
const ROAD_W := 2.0  # 半宽

var _rng := RandomNumberGenerator.new()
var _blocked: Array[Rect2] = []


func build(seed_value := 7) -> void:
	_rng.seed = seed_value
	_build_ground()
	_build_roads()
	_build_houses()
	_build_lamps()
	_build_trees()


func _add_mesh(mesh: Mesh, xf := Transform3D.IDENTITY, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_ground() -> void:
	var mb := MB.new()
	mb.box("grass", Vector3(-HALF, -0.5, -HALF), Vector3(HALF, 0.0, SHORE_Z), true, false, false)
	# 岸边立面
	mb.face("earth", [Vector3(-HALF, 0, SHORE_Z), Vector3(HALF, 0, SHORE_Z), Vector3(HALF, -1.5, SHORE_Z), Vector3(-HALF, -1.5, SHORE_Z)], Vector3.BACK)
	_add_mesh(mb.commit())
	# 水面
	var water := PlaneMesh.new()
	water.size = Vector2(HALF * 2.0 + 40.0, 40.0)
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	water.material = wm
	_add_mesh(water, Transform3D(Basis(), Vector3(0, -0.45, SHORE_Z + 20.0)), false)
	# 码头
	var pier := MB.new()
	pier.box("wall_wood", Vector3(8, -0.2, SHORE_Z - 1.0), Vector3(10.5, 0.05, SHORE_Z + 9.0))
	for z in [SHORE_Z + 3.0, SHORE_Z + 6.0, SHORE_Z + 8.6]:
		for x in [8.2, 10.1]:
			pier.box("trunk", Vector3(x, -1.5, z), Vector3(x + 0.25, 0.25, z + 0.25))
	_add_mesh(pier.commit())


func _build_roads() -> void:
	var mb := MB.new()
	var y := 0.02
	# 东西主街
	mb.face("cobble", [Vector3(-HALF, y, -ROAD_W), Vector3(HALF, y, -ROAD_W), Vector3(HALF, y, ROAD_W), Vector3(-HALF, y, ROAD_W)], Vector3.UP)
	# 南北支路（通往码头）
	mb.face("cobble", [Vector3(-ROAD_W, y, -HALF), Vector3(ROAD_W, y, -HALF), Vector3(ROAD_W, y, -ROAD_W), Vector3(-ROAD_W, y, -ROAD_W)], Vector3.UP)
	mb.face("dirt", [Vector3(ROAD_W, y, ROAD_W), Vector3(8.0, y, SHORE_Z - 1.0), Vector3(10.5, y, SHORE_Z - 1.0), Vector3(ROAD_W + 3.0, y, ROAD_W)], Vector3.UP)
	_add_mesh(mb.commit(), Transform3D.IDENTITY, false)
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


func _build_trees() -> void:
	var variants: Array[ArrayMesh] = []
	for i in 3:
		variants.append(Trees.build_pine(1000 + i))
	var xforms: Array = [[], [], []]
	var placed: Array[Vector2] = []
	for attempt in 2500:
		var p := Vector2(_rng.randf_range(-HALF + 1.0, HALF - 1.0), _rng.randf_range(-HALF + 1.0, SHORE_Z - 1.5))
		# 北边是林带：越往北越密
		var keep := 0.35 if p.y > -28.0 else 1.0
		if _rng.randf() > keep:
			continue
		var ok := true
		for r in _blocked:
			if r.has_point(p):
				ok = false
				break
		if not ok:
			continue
		for q in placed:
			if q.distance_squared_to(p) < 3.2 * 3.2:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var s := _rng.randf_range(0.75, 1.2)
		var b := Basis(Vector3.UP, _rng.randi_range(0, 3) * PI * 0.5).scaled(Vector3(s, s, s))
		xforms[_rng.randi_range(0, 2)].append(Transform3D(b, Vector3(p.x, 0, p.y)))
	# MultiMesh 批量渲染（Web 性能）
	for i in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[i]
		mm.instance_count = xforms[i].size()
		for j in xforms[i].size():
			mm.set_instance_transform(j, xforms[i][j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
