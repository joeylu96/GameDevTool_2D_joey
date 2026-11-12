@tool
extends RefCounted
## 占位植被与路灯。每个函数按种子生成不同的形状，配合实例的随机朝向 / 缩放 / 色调，
## 场景里不会出现一模一样的树和灯。
## - 松树：层数、粗细、收分、坡度随机；约三成是更窄更高的冷杉
## - 阔叶树：橡树（圆冠）、白桦（白树干、小冠）、杨树（竖长卵形）、秋色树
## - 灌木（部分开花）、石头
## - 路灯：灯笼式、悬臂式、球形、双头四种款式，三种金属颜色

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")

const BROADLEAF_STYLES := ["oak", "birch", "poplar", "autumn"]
const LAMP_STYLES := ["lantern", "arm", "globe", "twin"]
const LAMP_METALS := ["metal", "metal_green", "metal_red"]


## 松树 / 冷杉：八边形层层叠起，相邻层错开；每层 = 深色陡裙边 + 浅色缓顶盖（顶盖坡度固定，积雪成块）
static func build_pine(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mb := MB.new()
	var fir := rng.randf() < 0.3
	var tiers := rng.randi_range(6, 8) if fir else rng.randi_range(4, 6)
	var base_r := rng.randf_range(0.75, 0.95) if fir else rng.randf_range(1.0, 1.4)
	var shrink := rng.randf_range(0.7, 0.82)
	var slope := rng.randf_range(0.78, 0.95)
	var skirt := rng.randf_range(0.3, 0.4)
	var y := MB.snap(rng.randf_range(0.4, 0.7))  # 第一层下沿，露出一截树干
	mb.box("trunk", Vector3(-0.15, 0, -0.15), Vector3(0.15, y + 1.0, 0.15), false)
	var twist := rng.randf() * PI
	for i in tiers:
		var k := float(i) / tiers
		var r := base_r * (1.0 - k * shrink) * rng.randf_range(0.94, 1.06)
		var rot := twist + PI / 8.0 * (i % 2) + rng.randf_range(-0.15, 0.15)
		var last := i == tiers - 1
		var y_hem := MB.snap(y + r * skirt)
		var r_hem := MB.snap(r * 0.86)
		var r_top := 0.0 if last else MB.snap(r * 0.18)
		var rise := (r_hem - r_top) * (1.05 if last else slope)
		mb.ngon_frustum("pine_skirt", Vector3.ZERO, y, y_hem, MB.snap(r), r_hem, 8, rot, false)
		mb.ngon_frustum("pine", Vector3.ZERO, y_hem, MB.snap(y_hem + rise), r_hem, r_top, 8, rot, false)
		if last:
			var y_tip := MB.snap(y_hem + rise)
			mb.ngon_frustum("pine_skirt", Vector3.ZERO, y_tip - 0.15, y_tip + rng.randf_range(0.35, 0.6), 0.14, 0.0, 4, rot, false)
		y = y_hem + rise * 0.55
	return mb.commit()


## 阔叶树。style 为空时按种子选：oak / birch / poplar / autumn
static func build_broadleaf(seed_value: int, style := "") -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if style == "":
		style = BROADLEAF_STYLES[rng.randi_range(0, BROADLEAF_STYLES.size() - 1)]
	var mb := MB.new()
	match style:
		"birch":
			# 细长白树干，微微倾斜；树冠是几团偏小的嫩绿叶团，沿树干上部错落
			var h := rng.randf_range(2.6, 3.2)
			var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
			mb.ngon_frustum("birch_bark", Vector3.ZERO, 0.0, h * 0.5, 0.11, 0.09, 6, 0.0, false)
			mb.ngon_frustum("birch_bark", lean * 0.5, h * 0.5, h + 0.4, 0.09, 0.06, 6, 0.0, false)
			for i in rng.randi_range(3, 4):
				var t := float(i) / 3.0
				var c := lean * (0.5 + t * 0.5) + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
				var r := rng.randf_range(0.55, 0.8) * (1.0 - t * 0.3)
				_blob(mb, c, h * 0.62 + t * h * 0.42, r, r * 1.25, rng.randf() * PI, "leaf_birch", "leaf_birch_dark")
		"poplar":
			# 竖长的卵形树冠：三四团由大到小往上叠
			var trunk_h := rng.randf_range(1.2, 1.6)
			mb.box("trunk", Vector3(-0.15, 0, -0.15), Vector3(0.15, trunk_h + 1.2, 0.15), false)
			var r0 := rng.randf_range(0.85, 1.05)
			var cy := trunk_h + r0 * 0.6
			for i in rng.randi_range(3, 4):
				var r := r0 * (1.0 - i * 0.18)
				_blob(mb, Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1)), cy, r, r * 1.35, rng.randf() * PI, "leaf", "leaf_dark")
				cy += r * 0.95
		_:
			# 橡树 / 秋色树：一个主树冠团 + 2~3 个小团
			var light := "leaf_autumn" if style == "autumn" else "leaf"
			var dark := "leaf_autumn_dark" if style == "autumn" else "leaf_dark"
			var trunk_h := rng.randf_range(1.6, 2.2)
			mb.box("trunk", Vector3(-0.18, 0, -0.18), Vector3(0.18, trunk_h + 0.6, 0.18), false)
			var main_r := rng.randf_range(1.15, 1.5)
			_blob(mb, Vector3.ZERO, trunk_h + main_r * 0.55, main_r, main_r * rng.randf_range(1.15, 1.4), rng.randf() * PI, light, dark)
			var n := rng.randi_range(2, 3)
			var a0 := rng.randf() * TAU
			for i in n:
				var a := a0 + TAU * i / n + rng.randf_range(-0.4, 0.4)
				var r := main_r * rng.randf_range(0.5, 0.72)
				var off := Vector3(cos(a), 0, sin(a)) * main_r * rng.randf_range(0.55, 0.8)
				_blob(mb, off, trunk_h + main_r * rng.randf_range(0.25, 1.0), r, r * 1.3, rng.randf() * PI, light, dark)
	return mb.commit()


## 灌木：贴地的 2~3 个团块；约三成开花（顶面是花）
static func build_bush(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mb := MB.new()
	var top := "flowers" if rng.randf() < 0.3 else "leaf"
	var r := rng.randf_range(0.5, 0.8)
	_blob(mb, Vector3.ZERO, r * 0.55, r, r * rng.randf_range(0.95, 1.2), rng.randf() * PI, top, "leaf_dark")
	for i in rng.randi_range(1, 2):
		var a := rng.randf() * TAU
		var r2 := r * rng.randf_range(0.55, 0.8)
		_blob(mb, Vector3(cos(a), 0, sin(a)) * r * 0.75, r2 * 0.5, r2, r2, rng.randf() * PI, top, "leaf_dark")
	return mb.commit()


## 石头：两段多边形棱台，边数和扁平程度随机；有时旁边带一块小石头
static func build_rock(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mb := MB.new()
	var count := 2 if rng.randf() < 0.35 else 1
	for i in count:
		var c := Vector3.ZERO if i == 0 else Vector3(rng.randf_range(0.4, 0.6), 0, rng.randf_range(-0.3, 0.3))
		var r := rng.randf_range(0.35, 0.6) * (1.0 if i == 0 else 0.5)
		var h := r * rng.randf_range(0.6, 1.1)
		var sides := rng.randi_range(5, 7)
		var rot := rng.randf() * PI
		mb.ngon_frustum("rock", c, -0.05, MB.snap(h * 0.55), r, MB.snap(r * 0.85), sides, rot, false)
		mb.ngon_frustum("rock", c, MB.snap(h * 0.55), MB.snap(h), MB.snap(r * 0.85), MB.snap(r * rng.randf_range(0.3, 0.55)), sides, rot + 0.3, true)
	return mb.commit()


## 树冠团块：下收口（暗）+ 腰（暗）+ 上收口（亮，能积雪）。cy 为团块中心高度，h 为总高
static func _blob(mb: MB, c: Vector3, cy: float, r: float, h: float, rot: float,
		light := "leaf", dark := "leaf_dark") -> void:
	var y0 := MB.snap(cy - h * 0.5)
	var y1 := MB.snap(cy - h * 0.12)
	var y2 := MB.snap(cy + h * 0.15)
	var y3 := MB.snap(cy + h * 0.5)
	mb.ngon_frustum(dark, c, y0, y1, MB.snap(r * 0.6), r, 8, rot, false, true)
	mb.ngon_frustum(dark, c, y1, y2, r, r, 8, rot, false)
	mb.ngon_frustum(light, c, y2, y3, r, MB.snap(r * 0.5), 8, rot, true)


## 路灯。style：lantern（方灯箱）/ arm（悬臂吊灯）/ globe（球形灯）/ twin（双头）；metal：金属材质键
static func build_lamp(style := "lantern", metal := "metal") -> ArrayMesh:
	var mb := MB.new()
	match style:
		"arm":
			mb.box(metal, Vector3(-0.17, 0, -0.17), Vector3(0.17, 0.35, 0.17))
			mb.box(metal, Vector3(-0.07, 0.35, -0.07), Vector3(0.07, 3.1, 0.07), false)
			mb.frustum(metal, Vector3.ZERO, 3.1, 3.25, 0.1, 0.0)
			mb.box(metal, Vector3(0.0, 2.85, -0.04), Vector3(0.75, 2.93, 0.04))       # 横臂
			mb.box(metal, Vector3(0.05, 2.55, -0.03), Vector3(0.11, 2.85, 0.03), false)  # 斜撑
			mb.box(metal, Vector3(0.62, 2.62, -0.02), Vector3(0.66, 2.85, 0.02), false)  # 吊杆
			mb.box(metal, Vector3(0.48, 2.58, -0.16), Vector3(0.8, 2.62, 0.16))
			mb.box("bulb", Vector3(0.51, 2.26, -0.13), Vector3(0.77, 2.58, 0.13), false)
			mb.box(metal, Vector3(0.5, 2.22, -0.15), Vector3(0.78, 2.26, 0.15))
		"globe":
			mb.ngon_frustum(metal, Vector3.ZERO, 0.0, 0.25, 0.22, 0.16, 8, 0.0, true)
			mb.ngon_frustum(metal, Vector3.ZERO, 0.25, 0.45, 0.1, 0.07, 8, 0.0, false)
			mb.box(metal, Vector3(-0.055, 0.45, -0.055), Vector3(0.055, 2.55, 0.055), false)
			mb.ngon_frustum(metal, Vector3.ZERO, 2.55, 2.62, 0.12, 0.12, 8, 0.0, true)
			mb.ngon_frustum("bulb", Vector3.ZERO, 2.62, 2.8, 0.13, 0.21, 10, 0.0, false)
			mb.ngon_frustum("bulb", Vector3.ZERO, 2.8, 3.0, 0.21, 0.1, 10, 0.0, true)
			mb.ngon_frustum(metal, Vector3.ZERO, 3.0, 3.1, 0.06, 0.0, 6, 0.0, false)
		"twin":
			mb.box(metal, Vector3(-0.15, 0, -0.15), Vector3(0.15, 0.3, 0.15))
			mb.box(metal, Vector3(-0.06, 0.3, -0.06), Vector3(0.06, 2.7, 0.06), false)
			mb.box(metal, Vector3(-0.5, 2.55, -0.04), Vector3(0.5, 2.62, 0.04))
			for sx in [-1.0, 1.0]:
				var x: float = sx * 0.45
				mb.box(metal, Vector3(x - 0.12, 2.62, -0.12), Vector3(x + 0.12, 2.66, 0.12))
				mb.box("bulb", Vector3(x - 0.1, 2.66, -0.1), Vector3(x + 0.1, 2.9, 0.1), false)
				mb.frustum(metal, Vector3(x, 0, 0), 2.9, 3.03, 0.16, 0.0)
			mb.frustum(metal, Vector3.ZERO, 2.7, 2.85, 0.07, 0.0)
		_:
			mb.box(metal, Vector3(-0.15, 0, -0.15), Vector3(0.15, 0.3, 0.15))
			mb.box(metal, Vector3(-0.06, 0.3, -0.06), Vector3(0.06, 2.5, 0.06), false)
			mb.box(metal, Vector3(-0.19, 2.5, -0.19), Vector3(0.19, 2.56, 0.19))
			mb.box("bulb", Vector3(-0.15, 2.56, -0.15), Vector3(0.15, 2.9, 0.15), false)
			mb.frustum(metal, Vector3.ZERO, 2.9, 3.08, 0.24, 0.0)
	return mb.commit()


## 灯光落在地面的中心相对灯杆的偏移（悬臂灯的灯箱不在灯杆正上方）
static func lamp_light_offset(style: String) -> Vector3:
	return Vector3(0.64, 0, 0) if style == "arm" else Vector3.ZERO
