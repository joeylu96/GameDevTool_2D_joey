@tool
extends RefCounted
## 占位小摆件：白色尖头篱笆、长椅、木箱、木桶，以及地标灯塔。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")
const Parts := preload("res://addons/pixel_world/assets/placeholder/pw_parts.gd")


const FENCE_STYLES := ["picket", "rail", "stone"]
const BENCH_STYLES := ["slat", "park", "log"]


## 篱笆：沿 +X 从 0 到 length。gaps = [[x0, x1], ...]，这些区间不放篱笆（门口）。
## style：picket（白色尖头栅栏）/ rail（乡村木栏）/ stone（矮石墙）
static func build_fence(length: float, gaps: Array = [], style := "picket") -> ArrayMesh:
	var mb := MB.new()
	# 连续的段（去掉缺口）
	var runs: Array[Vector2] = []
	var start := 0.0
	for g: Array in gaps:
		if g[0] > start:
			runs.append(Vector2(start, g[0]))
		start = maxf(start, g[1])
	if start < length:
		runs.append(Vector2(start, length))
	for r in runs:
		if style == "rail":
			# 粗木桩 + 两道横木
			var n := maxi(1, roundi((r.y - r.x) / 2.0))
			for i in n + 1:
				var px := lerpf(r.x, r.y, float(i) / n)
				mb.box("trunk", Vector3(px - 0.08, 0, -0.08), Vector3(px + 0.08, 0.95, 0.08))
			for y in [0.35, 0.7]:
				mb.box("wall_wood", Vector3(r.x, y, -0.04), Vector3(r.y, y + 0.11, 0.05))
			continue
		if style == "stone":
			# 矮石墙 + 浅色压顶
			mb.box("stone", Vector3(r.x, 0, -0.16), Vector3(r.y, 0.48, 0.16))
			mb.box("curb", Vector3(r.x - 0.03, 0.48, -0.2), Vector3(r.y + 0.03, 0.58, 0.2))
			continue
		# 两根横档（在栅条后面）
		for y in [0.28, 0.6]:
			mb.box("trim", Vector3(r.x, y, -0.07), Vector3(r.y, y + 0.07, -0.025))
		# 立柱：两端 + 每 1.5 米
		var n := maxi(1, roundi((r.y - r.x) / 1.5))
		for i in n + 1:
			var px := lerpf(r.x, r.y, float(i) / n)
			mb.box("trim", Vector3(px - 0.06, 0, -0.08), Vector3(px + 0.06, 0.9, 0.04))
			mb.frustum("trim", Vector3(px, 0, -0.02), 0.9, 1.0, 0.06, 0.0, false)
		# 尖头栅条
		var x := r.x + 0.18
		while x < r.y - 0.12:
			mb.box("trim", Vector3(x - 0.045, 0.05, -0.025), Vector3(x + 0.045, 0.76, 0.02), false)
			mb.frustum("trim", Vector3(x, 0, 0), 0.76, 0.84, 0.045, 0.0, false)
			x += 0.21
	return mb.commit()


## 长椅：面朝 +Z，长约 1.6 米。style：slat（木条 + 铁艺腿）/ park（带扶手的绿漆长椅）/ log（原木长凳，无靠背）
static func build_bench(style := "slat") -> ArrayMesh:
	var mb := MB.new()
	match style:
		"park":
			for i in 3:
				var z := -0.18 + i * 0.14
				mb.box("deck", Vector3(-0.85, 0.42, z), Vector3(0.85, 0.48, z + 0.11))
			for i in 2:
				var y := 0.62 + i * 0.16
				mb.box("deck", Vector3(-0.85, y, -0.3), Vector3(0.85, y + 0.11, -0.24))
			for x in [-0.8, 0.8]:
				mb.box("metal_green", Vector3(x - 0.05, 0, -0.26), Vector3(x + 0.05, 0.95, -0.2), false)
				mb.box("metal_green", Vector3(x - 0.05, 0, 0.12), Vector3(x + 0.05, 0.42, 0.18), false)
				mb.box("metal_green", Vector3(x - 0.05, 0.62, -0.26), Vector3(x + 0.05, 0.67, 0.2))  # 扶手
		"log":
			mb.box("trunk", Vector3(-0.8, 0.32, -0.18), Vector3(0.8, 0.48, 0.18))
			for x in [-0.55, 0.55]:
				mb.ngon_frustum("rock", Vector3(x, 0, 0), 0.0, 0.32, 0.2, 0.17, 6, 0.3, false)
		_:
			mb.box("boards", Vector3(-0.8, 0.42, -0.2), Vector3(0.8, 0.5, 0.22))
			mb.box("boards", Vector3(-0.8, 0.6, -0.28), Vector3(0.8, 0.95, -0.21))
			for x in [-0.66, 0.66]:
				mb.box("metal", Vector3(x - 0.05, 0, -0.18), Vector3(x + 0.05, 0.42, 0.2), false)
				mb.box("metal", Vector3(x - 0.04, 0.42, -0.3), Vector3(x + 0.04, 0.98, -0.2))
	return mb.commit()


## 木箱：边长 size，四角深色木条
static func build_crate(size := 0.7) -> ArrayMesh:
	var mb := MB.new()
	var h := size * 0.5
	mb.box("crate", Vector3(-h, 0, -h), Vector3(h, size, h))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * h, 0, sz * h)
			mb.box("trunk", Vector3(c.x - 0.05, 0, c.z - 0.05), Vector3(c.x + 0.05, size, c.z + 0.05), false)
	return mb.commit()


## 木桶：中间鼓、上下收口的十边形，两道铁箍
static func build_barrel() -> ArrayMesh:
	var mb := MB.new()
	mb.ngon_frustum("barrel", Vector3.ZERO, 0.0, 0.45, 0.3, 0.36, 10, 0.0, false)
	mb.ngon_frustum("barrel", Vector3.ZERO, 0.45, 0.9, 0.36, 0.3, 10, 0.0, true)
	for y in [0.14, 0.7]:
		var r := 0.345 if y < 0.4 else 0.335
		mb.ngon_frustum("metal", Vector3.ZERO, y, y + 0.07, r, r, 10, 0.0, false)
	return mb.commit()


## 一丛水草：4~6 片细长的三棱叶，随风（水流）摆动
static func build_weed(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mb := MB.new()
	for i in rng.randi_range(4, 6):
		var c := Vector3(rng.randf_range(-0.18, 0.18), 0, rng.randf_range(-0.18, 0.18))
		var h := rng.randf_range(0.35, 0.8)
		mb.ngon_frustum("weed", c, 0.0, h, 0.045, 0.0, 3, rng.randf() * TAU, false)
	return mb.commit()


## 小鱼：菱形身体 + 背鳍 + 双面尾鳍，头朝 +Z，长约 0.3 米
static func build_fish(mat: String) -> ArrayMesh:
	var mb := MB.new()
	var nose := Vector3(0, 0, 0.16)
	var tail := Vector3(0, 0, -0.12)
	var ring := [Vector3(0, 0.05, 0.02), Vector3(0.04, 0, 0.02), Vector3(0, -0.04, 0.02), Vector3(-0.04, 0, 0.02)]
	var center := Vector3(0, 0, 0.02)
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		mb.face(mat, [nose, a, b], (nose + a + b) / 3.0 - center)
		mb.face(mat, [tail, a, b], (tail + a + b) / 3.0 - center)
	var fin := [Vector3(0, 0, -0.1), Vector3(0, 0.07, -0.2), Vector3(0, -0.07, -0.2)]
	mb.face(mat, fin, Vector3.RIGHT)
	mb.face(mat, fin, Vector3.LEFT)
	var dorsal := [Vector3(0, 0.045, 0.05), Vector3(0, 0.085, -0.02), Vector3(0, 0.04, -0.04)]
	mb.face(mat, dorsal, Vector3.RIGHT)
	mb.face(mat, dorsal, Vector3.LEFT)
	return mb.commit()


## 风车塔身：石砌八边形锥塔 + 白色腰线 + 门窗 + 木质锥形顶 + 朝 +Z 伸出的轮轴。叶片另外建（会转）。
## 叶片的轮轴中心在 windmill_hub() 处。
static func build_windmill_tower() -> ArrayMesh:
	var mb := MB.new()
	var rot := PI / 8.0
	mb.ngon_frustum("stone", Vector3.ZERO, -0.2, 0.4, 2.4, 2.3, 8, rot, true)
	mb.ngon_frustum("plaster_white", Vector3.ZERO, 0.4, 6.4, 2.0, 1.45, 8, rot, false)
	mb.ngon_frustum("trim", Vector3.ZERO, 3.3, 3.5, 1.82, 1.8, 8, rot, false)
	mb.ngon_frustum("roof_cap", Vector3.ZERO, 6.4, 6.6, 1.65, 1.6, 8, rot, false, true)
	mb.ngon_frustum("roof_red", Vector3.ZERO, 6.6, 8.6, 1.6, 0.0, 8, rot, false)
	var ap := 2.0 * cos(PI / 8.0) + 0.01
	Parts.door(mb, Vector3(0, 0.4, ap - 0.06), Vector3.BACK, {"w": 0.9, "h": 1.8, "mat": "door_wood", "glass_top": false})
	for y in [3.9]:
		var r := lerpf(2.0, 1.45, (y - 0.4) / 6.0) * cos(PI / 8.0) + 0.01
		Parts.window(mb, Vector3(0, y, r), Vector3.BACK, 0.25, 0.6, {"panes_x": 2, "panes_y": 2, "rnd": 0.8})
	mb.tube("trunk", Vector3(0, 6.9, 0.6), windmill_hub() + Vector3(0, 0, 0.25), 0.18, 0.16, 8)
	return mb.commit()


static func windmill_hub() -> Vector3:
	return Vector3(0, 6.9, 1.85)


## 风车叶片：四片格栅叶片，中心在原点，在 XY 平面内（绕 Z 轴转）
static func build_windmill_blades() -> ArrayMesh:
	var mb := MB.new()
	mb.ngon_frustum("roof_cap", Vector3.ZERO, -0.05, 0.05, 0.3, 0.3, 8, 0.0, true, true)
	for k in 4:
		var a := TAU * k / 4.0 + 0.3
		var dir := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-sin(a), cos(a), 0)
		mb.tube("trunk", Vector3.ZERO, dir * 5.2, 0.07, 0.05, 4)
		# 格栅：沿叶片的两根边框 + 若干横档，再铺一片白帆布
		for s in [0.15, 0.85]:
			mb.tube("wall_wood", dir * 1.0 + side * s, dir * 5.0 + side * s, 0.03, 0.03, 4)
		for t in range(0, 9):
			var d := 1.0 + t * 0.5
			mb.tube("wall_wood", dir * d + side * 0.15, dir * d + side * 0.85, 0.025, 0.025, 4)
		var c0 := dir * 1.05 + side * 0.18
		var c1 := dir * 4.95 + side * 0.18
		var c2 := dir * 4.95 + side * 0.82
		var c3 := dir * 1.05 + side * 0.82
		mb.face("plaster_white", [c0 + Vector3(0, 0, -0.02), c1 + Vector3(0, 0, -0.02), c2 + Vector3(0, 0, -0.02), c3 + Vector3(0, 0, -0.02)], Vector3.BACK)
		mb.face("plaster_white", [c0 + Vector3(0, 0, -0.03), c3 + Vector3(0, 0, -0.03), c2 + Vector3(0, 0, -0.03), c1 + Vector3(0, 0, -0.03)], Vector3.FORWARD)
	return mb.commit()


## 草垛：圆柱形的干草卷（躺倒）或圆锥形的草堆
static func build_haystack(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mb := MB.new()
	if rng.randf() < 0.5:
		var r := rng.randf_range(0.6, 0.75)
		var l := rng.randf_range(1.0, 1.3)
		mb.tube("hay", Vector3(-l * 0.5, r, 0), Vector3(l * 0.5, r, 0), r, r, 10, 0.0, true, true)
	else:
		var r := rng.randf_range(1.1, 1.5)
		mb.ngon_frustum("hay", Vector3.ZERO, 0.0, r * 0.9, r, r * 0.8, 9, rng.randf(), false)
		mb.ngon_frustum("hay", Vector3.ZERO, r * 0.9, r * 1.9, r * 0.8, 0.12, 9, rng.randf(), false)
	return mb.commit()


## 灯塔：八边形石台 + 红白相间的锥形塔身 + 门窗 + 环形走廊和栏杆 + 发光灯室 + 深色圆顶。
## 门朝 +Z。总高约 13.5 米。灯室用 "beacon" 材质，夜里自动发光。
static func build_lighthouse() -> ArrayMesh:
	var mb := MB.new()
	var n := 12
	var rot := PI * 0.5 - PI / n  # 让塔身的一个面正对 +Z（放门）
	var base_y := 0.4
	var h := 9.0
	var r0 := 1.55
	var r1 := 1.1
	# 石台（一半伸进水里）
	mb.ngon_frustum("stone", Vector3.ZERO, -3.8, base_y, 3.0, 2.7, 8, PI / 8.0, true)
	# 塔身：6 段红白相间
	var bands := 6
	for i in bands:
		var ya := base_y + h * i / bands
		var yb := base_y + h * (i + 1) / bands
		var ra := lerpf(r0, r1, float(i) / bands)
		var rb := lerpf(r0, r1, float(i + 1) / bands)
		mb.ngon_frustum("plaster_red" if i % 2 == 0 else "plaster_white", Vector3.ZERO, ya, yb, ra, rb, n, rot, false)
	# 门（正对 +Z 的那个面）
	var ap0 := r0 * cos(PI / n) + 0.01
	Parts.door(mb, Vector3(0, base_y, ap0), Vector3.BACK, {"w": 0.62, "h": 1.65, "mat": "door_teal", "glass_top": false})
	mb.box("stone", Vector3(-0.6, base_y - 0.15, ap0 - 0.2), Vector3(0.6, base_y, ap0 + 0.5))
	# 小窗：沿塔身往上错落排布（塔身微微内收，窗户贴在当前高度的面上）
	var rnd := [0.9, 0.2, 0.7]
	var k := 0
	for y in [3.4, 5.9, 8.0]:
		var ap := lerpf(r0, r1, (y - base_y) / h) * cos(PI / n) + 0.02
		Parts.window(mb, Vector3(0, y, ap), Vector3.BACK, 0.2, 0.5, {"panes_x": 2, "panes_y": 2, "rnd": rnd[k]})
		k += 1
	var top := base_y + h
	# 环形走廊 + 栏杆
	mb.ngon_frustum("roof_cap", Vector3.ZERO, top, top + 0.15, 1.75, 1.75, n, rot, true, true)
	var posts := 16
	for i in posts:
		var a := TAU * i / posts
		var p := Vector3(cos(a), 0, sin(a)) * 1.66
		mb.box("metal", Vector3(p.x - 0.03, top + 0.15, p.z - 0.03), Vector3(p.x + 0.03, top + 0.68, p.z + 0.03), false)
	mb.ngon_frustum("metal", Vector3.ZERO, top + 0.62, top + 0.7, 1.69, 1.69, posts, 0.0, false)
	# 灯室：底座 + 发光玻璃 + 窗棂
	mb.ngon_frustum("metal", Vector3.ZERO, top + 0.15, top + 0.45, 0.88, 0.88, n, rot, false)
	mb.ngon_frustum("beacon", Vector3.ZERO, top + 0.45, top + 1.35, 0.8, 0.8, n, rot, false)
	for i in 6:
		var a := rot + TAU * i / 6.0
		var p := Vector3(cos(a), 0, sin(a)) * 0.82
		mb.box("metal", Vector3(p.x - 0.04, top + 0.45, p.z - 0.04), Vector3(p.x + 0.04, top + 1.35, p.z + 0.04), false)
	# 圆顶 + 顶尖
	mb.ngon_frustum("roof_cap", Vector3.ZERO, top + 1.35, top + 1.45, 1.0, 0.86, n, rot, false, true)
	mb.ngon_frustum("roof_cap", Vector3.ZERO, top + 1.45, top + 2.15, 0.86, 0.22, n, rot, true)
	mb.box("metal", Vector3(-0.04, top + 2.15, -0.04), Vector3(0.04, top + 2.75, 0.04))
	mb.ngon_frustum("plaster_red", Vector3.ZERO, top + 2.2, top + 2.32, 0.12, 0.12, 6, 0.0, true)
	return mb.commit()
