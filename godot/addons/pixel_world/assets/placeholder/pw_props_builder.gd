@tool
extends RefCounted
## 占位小摆件：白色尖头篱笆、长椅、木箱、木桶，以及地标灯塔。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")


## 白色尖头篱笆：沿 +X 从 0 到 length。gaps = [[x0, x1], ...]，这些区间不放篱笆（门口）。
static func build_fence(length: float, gaps: Array = []) -> ArrayMesh:
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


## 长椅：面朝 +Z，长 1.6 米。木板座面 + 靠背，铁艺腿
static func build_bench() -> ArrayMesh:
	var mb := MB.new()
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
	mb.ngon_frustum("stone", Vector3.ZERO, -1.6, base_y, 2.9, 2.7, 8, PI / 8.0, true)
	# 塔身：6 段红白相间
	var bands := 6
	for i in bands:
		var ya := base_y + h * i / bands
		var yb := base_y + h * (i + 1) / bands
		var ra := lerpf(r0, r1, float(i) / bands)
		var rb := lerpf(r0, r1, float(i + 1) / bands)
		mb.ngon_frustum("plaster_red" if i % 2 == 0 else "plaster_white", Vector3.ZERO, ya, yb, ra, rb, n, rot, false)
	# 门（正对 +Z 的那个面）
	var ap0 := r0 * cos(PI / n) + 0.03
	mb.quad01("door", Vector3(-0.36, base_y + 1.6, ap0), Vector3(0.36, base_y + 1.6, ap0),
		Vector3(0.36, base_y, ap0), Vector3(-0.36, base_y, ap0), Vector3.BACK)
	mb.box("stone", Vector3(-0.6, base_y - 0.15, ap0 - 0.2), Vector3(0.6, base_y, ap0 + 0.5))
	# 小窗：沿塔身往上错落排布
	for y in [3.4, 5.9, 8.0]:
		var ap := lerpf(r0, r1, (y - base_y) / h) * cos(PI / n) + 0.04
		mb.quad01("window", Vector3(-0.22, y + 0.55, ap), Vector3(0.22, y + 0.55, ap),
			Vector3(0.22, y, ap), Vector3(-0.22, y, ap), Vector3.BACK)
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
