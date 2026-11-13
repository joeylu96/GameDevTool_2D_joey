@tool
extends RefCounted
## 占位植被与路灯。每个函数按种子生成不同的形状，配合实例的随机朝向 / 缩放 / 色调，
## 场景里不会出现一模一样的树和灯。
## - 松树：层数、粗细、收分、坡度随机；约三成是更窄更高的冷杉
## - 阔叶树：橡树（分叉枝 + 圆冠）、白桦（白树干、黑色皮孔、细枝、通透小叶团）、杨树（竖长卵形）
## - 乔木一律露出树干：俯视 40° 时，树冠向外伸出多少，就会挡住下面多高的树干，
##   所以树冠底部至少比「树冠外伸量 × 0.85 + 0.5 米」高
## - 灌木（部分开花）、石头：没有树干
## - 路灯：灯笼式、悬臂式、球形、双头四种款式，三种金属颜色

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")

const BROADLEAF_STYLES := ["oak", "birch", "poplar"]
const LAMP_STYLES := ["lantern", "arm", "globe", "twin"]
const LAMP_METALS := ["metal", "metal_green", "metal_red"]


## 树冠最低能放多高才露得出树干（r = 树冠水平半径）
static func _clear_height(r: float) -> float:
	return r * 0.85 + 0.55


## 松树 / 冷杉：八边形层层叠起，相邻层错开；每层 = 深色陡裙边 + 浅色缓顶盖（顶盖坡度固定，积雪成块）。
## 下部是一段裸露的树干，根部略粗。
static func build_pine(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mb := MB.new()
	var fir := rng.randf() < 0.3
	var tiers := rng.randi_range(6, 8) if fir else rng.randi_range(4, 6)
	var base_r := rng.randf_range(0.7, 0.88) if fir else rng.randf_range(0.95, 1.25)
	var shrink := rng.randf_range(0.7, 0.82)
	var slope := rng.randf_range(0.78, 0.95)
	var skirt := rng.randf_range(0.3, 0.4)
	var y := MB.snap(_clear_height(base_r) + rng.randf_range(0.0, 0.3))  # 第一层下沿
	var tr := rng.randf_range(0.13, 0.17)
	mb.ngon_frustum("trunk", Vector3.ZERO, 0.0, 0.25, tr * 1.5, tr, 8, 0.0, false, false, true)  # 根部
	mb.ngon_frustum("trunk", Vector3.ZERO, 0.25, y + 1.2, tr, tr * 0.8, 8, 0.0, false, false, true)
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
		# 最下面一层底部收口，从下往上看不是一个平底大盘子
		mb.ngon_frustum("pine_skirt", Vector3.ZERO, y, y_hem, MB.snap(r), r_hem, 8, rot, false, i == 0)
		mb.ngon_frustum("pine", Vector3.ZERO, y_hem, MB.snap(y_hem + rise), r_hem, r_top, 8, rot, false)
		if last:
			var y_tip := MB.snap(y_hem + rise)
			mb.ngon_frustum("pine_skirt", Vector3.ZERO, y_tip - 0.15, y_tip + rng.randf_range(0.35, 0.6), 0.14, 0.0, 4, rot, false)
		y = y_hem + rise * 0.55
	return mb.commit()


## 阔叶树。style 为空时按种子选：oak / birch / poplar
static func build_broadleaf(seed_value: int, style := "") -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if style == "":
		style = BROADLEAF_STYLES[rng.randi_range(0, BROADLEAF_STYLES.size() - 1)]
	var mb := MB.new()
	match style:
		"birch":
			_birch(mb, rng)
		"poplar":
			# 竖长的卵形树冠：三四团由大到小往上叠，下面露出一截树干
			var r0 := rng.randf_range(0.8, 1.0)
			var trunk_h := _clear_height(r0) + rng.randf_range(0.1, 0.4)
			mb.ngon_frustum("trunk", Vector3.ZERO, 0.0, 0.25, 0.22, 0.15, 8, 0.0, false, false, true)
			mb.ngon_frustum("trunk", Vector3.ZERO, 0.25, trunk_h + 1.4, 0.15, 0.1, 8, 0.0, false, false, true)
			var cy := trunk_h + r0 * 0.68
			for i in rng.randi_range(3, 4):
				var r := r0 * (1.0 - i * 0.18)
				_blob(mb, Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1)), cy, r, r * 1.35, rng.randf() * PI)
				cy += r * 0.95
		_:
			_oak(mb, rng)
	return mb.commit()


## 橡树：主干在约 2/3 处分成 2~3 根斜向上的粗枝，每根枝头一团树冠，中间再盖一团主冠
static func _oak(mb: MB, rng: RandomNumberGenerator) -> void:
	var main_r := rng.randf_range(1.05, 1.35)
	var spread := main_r * rng.randf_range(0.55, 0.75)
	var trunk_h := _clear_height(spread + main_r * 0.6) * 0.9 + rng.randf_range(0.0, 0.3)
	var fork := trunk_h * rng.randf_range(0.7, 0.85)
	var tr := rng.randf_range(0.17, 0.22)
	mb.ngon_frustum("trunk", Vector3.ZERO, 0.0, 0.3, tr * 1.6, tr, 8, 0.0, false, false, true)
	mb.ngon_frustum("trunk", Vector3.ZERO, 0.3, fork + 0.2, tr, tr * 0.85, 8, 0.0, false, false, true)
	var top := Vector3(0, fork, 0)
	var n := rng.randi_range(2, 3)
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * i / n + rng.randf_range(-0.4, 0.4)
		var tip := Vector3(cos(a) * spread, trunk_h + main_r * rng.randf_range(0.35, 0.65), sin(a) * spread)
		_limb(mb, "trunk", top, tip, tr * 0.75, tr * 0.4, 6)
		var r := main_r * rng.randf_range(0.6, 0.78)
		_blob(mb, Vector3(tip.x, 0, tip.z), tip.y + r * 0.25, r, r * 1.25, rng.randf() * PI)
	_blob(mb, Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)),
		trunk_h + main_r * 1.0, main_r, main_r * rng.randf_range(1.0, 1.2), rng.randf() * PI)


## 白桦：微弯的白色主干（分三段收细，根部略粗）+ 3~4 根斜向上的枝；
## 树冠是一个椭圆形的叶团簇：8~11 个相互重叠的嫩绿叶团，从主干中部包到树梢，
## 下缘留出 2 米多的白色树干
static func _birch(mb: MB, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(4.6, 5.6)
	var bend := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
	var pts := [Vector3(0, 0.25, 0), Vector3(0, h * 0.42, 0) + bend * 0.3, Vector3(0, h * 0.72, 0) + bend * 0.7, Vector3(0, h, 0) + bend]
	var radii := [0.16, 0.13, 0.095, 0.05]
	mb.ngon_frustum("birch_bark", Vector3.ZERO, 0.0, 0.25, 0.23, 0.16, 8, 0.0, false, false, true)
	for i in 3:
		mb.tube("birch_bark", pts[i], pts[i + 1], radii[i], radii[i + 1], 8, 0.0, i == 2)
	# 枝
	var nb := rng.randi_range(3, 4)
	var a0 := rng.randf() * TAU
	var tips: Array[Vector3] = []
	for i in nb:
		var t := rng.randf_range(0.0, 1.0)
		var base: Vector3 = (pts[1] as Vector3).lerp(pts[2], t)
		var a := a0 + TAU * i / nb + rng.randf_range(-0.3, 0.3)
		var len := rng.randf_range(0.45, 0.7)
		var tip := base + Vector3(cos(a) * len, len * rng.randf_range(0.7, 1.0), sin(a) * len)
		mb.tube("birch_bark", base, tip, 0.06, 0.025, 6)
		tips.append(tip)
	# 树冠：椭球形分布的叶团，中心偏上
	var crown_c: Vector3 = (pts[2] as Vector3) + Vector3(0, 0.1, 0)
	var crown_rx := rng.randf_range(0.65, 0.85)
	var crown_ry := h * 0.3
	var blobs: Array[Vector3] = []
	for tip in tips:
		blobs.append(tip)
	blobs.append(pts[3] + Vector3(0, 0.1, 0))
	for i in rng.randi_range(6, 8):
		var a := rng.randf() * TAU
		var e := rng.randf_range(-0.55, 0.8)
		var rr := sqrt(maxf(1.0 - e * e, 0.05)) * crown_rx * rng.randf_range(0.5, 0.9)
		blobs.append(crown_c + Vector3(cos(a) * rr, e * crown_ry, sin(a) * rr))
	for c in blobs:
		var r := rng.randf_range(0.58, 0.78) * (1.0 - clampf((c.y - crown_c.y) / (crown_ry * 2.0), 0.0, 0.35))
		_blob(mb, Vector3(c.x, 0, c.z), c.y, r, r * 1.2, rng.randf() * PI, "leaf_birch", "leaf_birch_dark", 7)


## 两点之间的一根枝干（贴图沿圆周展开）
static func _limb(mb: MB, mat: String, a: Vector3, b: Vector3, r0: float, r1: float, sides := 6) -> void:
	mb.tube(mat, a, b, r0, r1, sides)


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
		light := "leaf", dark := "leaf_dark", sides := 8) -> void:
	var y0 := MB.snap(cy - h * 0.5)
	var y1 := MB.snap(cy - h * 0.12)
	var y2 := MB.snap(cy + h * 0.15)
	var y3 := MB.snap(cy + h * 0.5)
	mb.ngon_frustum(dark, c, y0, y1, MB.snap(r * 0.6), r, sides, rot, false, true)
	mb.ngon_frustum(dark, c, y1, y2, r, r, sides, rot, false)
	mb.ngon_frustum(light, c, y2, y3, r, MB.snap(r * 0.5), sides, rot, true)


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
