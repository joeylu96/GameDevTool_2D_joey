@tool
extends RefCounted
## 占位植被与小物件：松树、阔叶树、灌木、石头、路灯。
## 树冠用八边形棱台，相邻层错开 22.5°，轮廓比方块更圆润；每层 = 深色陡裙边 + 浅色缓顶盖，
## 晴天有明暗层次，下雪时顶盖整块积白，形成一圈圈雪檐。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")


static func build_pine(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mb := MB.new()
	var tiers := rng.randi_range(5, 6)
	var base_r := rng.randf_range(1.1, 1.35)
	var y := MB.snap(rng.randf_range(0.45, 0.6))  # 第一层下沿，露出一截树干
	mb.box("trunk", Vector3(-0.16, 0, -0.16), Vector3(0.16, y + 1.0, 0.16), false)
	# 每层按自身半径等比缩放：裙边高 0.35r，顶盖坡度固定（约 40°），
	# 所以每一层的顶盖都能整块积雪，不会因为上层更陡而只剩零星雪点。
	for i in tiers:
		var k := float(i) / tiers
		var r := base_r * (1.0 - k * 0.76)
		var rot := PI / 8.0 * (i % 2) + rng.randf_range(-0.12, 0.12)
		var last := i == tiers - 1
		var y_hem := MB.snap(y + r * 0.35)
		var r_hem := MB.snap(r * 0.86)
		var r_top := 0.0 if last else MB.snap(r * 0.18)
		var rise := (r_hem - r_top) * (1.4 if last else 0.85)
		mb.ngon_frustum("pine_skirt", Vector3.ZERO, y, y_hem, MB.snap(r), r_hem, 8, rot, false)
		mb.ngon_frustum("pine", Vector3.ZERO, y_hem, MB.snap(y_hem + rise), r_hem, r_top, 8, rot, false)
		y = y_hem + rise * 0.55  # 下一层压住本层顶盖的上半部分
	return mb.commit()


## 阔叶树：树干 + 一个主树冠团块 + 2~3 个小团块
static func build_broadleaf(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mb := MB.new()
	var trunk_h := rng.randf_range(1.7, 2.1)
	mb.box("trunk", Vector3(-0.18, 0, -0.18), Vector3(0.18, trunk_h + 0.6, 0.18), false)
	var main_r := rng.randf_range(1.2, 1.45)
	_blob(mb, Vector3.ZERO, trunk_h + main_r * 0.55, main_r, main_r * 1.3, rng.randf() * PI)
	var n := rng.randi_range(2, 3)
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * i / n + rng.randf_range(-0.4, 0.4)
		var r := main_r * rng.randf_range(0.55, 0.7)
		var off := Vector3(cos(a), 0, sin(a)) * main_r * rng.randf_range(0.55, 0.75)
		var cy := trunk_h + main_r * rng.randf_range(0.3, 1.0)
		_blob(mb, off, cy, r, r * 1.3, rng.randf() * PI)
	return mb.commit()


## 灌木：贴地的一大一小两个团块
static func build_bush(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mb := MB.new()
	var r := rng.randf_range(0.55, 0.75)
	_blob(mb, Vector3.ZERO, r * 0.55, r, r * 1.1, rng.randf() * PI)
	var a := rng.randf() * TAU
	var r2 := r * 0.7
	_blob(mb, Vector3(cos(a), 0, sin(a)) * r * 0.7, r2 * 0.5, r2, r2 * 1.0, rng.randf() * PI)
	return mb.commit()


## 石头：两段六边形棱台，顶面能积雪
static func build_rock(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mb := MB.new()
	var r := rng.randf_range(0.35, 0.6)
	var h := r * rng.randf_range(0.8, 1.1)
	var rot := rng.randf() * PI
	mb.ngon_frustum("rock", Vector3.ZERO, -0.05, MB.snap(h * 0.55), r, MB.snap(r * 0.85), 6, rot, false)
	mb.ngon_frustum("rock", Vector3.ZERO, MB.snap(h * 0.55), MB.snap(h), MB.snap(r * 0.85), MB.snap(r * 0.45), 6, rot + 0.3, true)
	return mb.commit()


## 树冠团块：下收口（暗）+ 腰（暗）+ 上收口（亮，能积雪）。cy 为团块中心高度，h 为总高。
static func _blob(mb: MB, c: Vector3, cy: float, r: float, h: float, rot: float) -> void:
	var y0 := MB.snap(cy - h * 0.5)
	var y1 := MB.snap(cy - h * 0.12)
	var y2 := MB.snap(cy + h * 0.15)
	var y3 := MB.snap(cy + h * 0.5)
	mb.ngon_frustum("leaf_dark", c, y0, y1, MB.snap(r * 0.6), r, 8, rot, false, true)
	mb.ngon_frustum("leaf_dark", c, y1, y2, r, r, 8, rot, false)
	mb.ngon_frustum("leaf", c, y2, y3, r, MB.snap(r * 0.5), 8, rot, true)


## 路灯：灯杆 + 玻璃灯箱（夜间发光）+ 小顶
static func build_lamp() -> ArrayMesh:
	var mb := MB.new()
	mb.box("metal", Vector3(-0.15, 0, -0.15), Vector3(0.15, 0.3, 0.15))
	mb.box("metal", Vector3(-0.06, 0.3, -0.06), Vector3(0.06, 2.5, 0.06), false)
	mb.box("metal", Vector3(-0.19, 2.5, -0.19), Vector3(0.19, 2.56, 0.19))
	mb.box("bulb", Vector3(-0.15, 2.56, -0.15), Vector3(0.15, 2.9, 0.15), false)
	mb.frustum("metal", Vector3.ZERO, 2.9, 3.08, 0.24, 0.0)
	return mb.commit()
