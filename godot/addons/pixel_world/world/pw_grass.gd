@tool
class_name PWGrass
extends RefCounted
## 草丛：模型与摆放规则。
##
## 模型（build_tuft）：一丛 6~12 片细长的草叶（双面三角形，根部深绿、尖端浅绿，带随机倾斜），
##   四种：grass（普通）、tall（高草）、dry（偏黄的干草）、flower（草里夹 2~4 朵小花）；
##   每种按种子生成多个变体，再加上每丛独立的朝向、大小和色调，所以没有两丛一样。
##
## 摆放规则（scatter）——后续所有场景风格都用这一套：
##   1. 候选点：0.8 米的抖动网格（均匀铺满，不会成排）
##   2. 硬性排除：水里和水边 0.25 米、沙滩、岩石、坡度 > 0.65、道路 / 土路 / 码头、房屋和门前通道、
##      篱笆、路灯 / 长椅 / 货物脚下、地标；树干周围 0.35 米（PWPlacement 的 GRASS 间距表）
##   3. 密度：由风格给的 density(p)（0~1，例如草原 1.0、林下 0.25、小镇草坪 0.5）
##      × 成团噪声（草一片片地长，中间露出地皮，不是均匀的地毯）
##   4. 种类：成团噪声高的地方多高草；靠近沙滩 / 岩石多干草；花按风格的 flowers 比例，并且成片出现
##   5. 上限：每种风格给一个预算（性能），超过就停
## 草不登记到 PWPlacement（之后不会再放别的东西），也不投影（太细，投影只会产生闪烁的噪点）。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")
const Mats := preload("res://addons/pixel_world/core/pw_materials.gd")
const Pal := preload("res://addons/pixel_world/core/pw_palette.gd")
const P := preload("res://addons/pixel_world/world/pw_placement.gd")

const KINDS := ["grass", "tall", "dry", "flower"]
const VARIANTS := 5
const SPACING := 0.8

static var _cache := {}


## 一丛草。kind：grass / tall / dry / flower
static func build_tuft(seed_value: int, kind := "grass") -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tall := kind == "tall"
	var dry := kind == "dry"
	var root := Pal.mix("grass_2", "grass_1", 0.3)
	var tips: Array[Color] = [Pal.mix("grass_0", "light_0", 0.2), Pal.c("grass_0"), Pal.mix("grass_0", "light_0", 0.4)]
	if dry:
		root = Pal.mix("grass_2", "dirt_1", 0.5)
		tips = [Pal.c("ochre_0"), Pal.mix("dirt_0", "grass_0", 0.4), Pal.c("dirt_0")]
	var n := rng.randi_range(10, 14) if tall else rng.randi_range(8, 12)
	for i in n:
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.16)
		var yaw := rng.randf() * TAU
		var h := rng.randf_range(0.45, 0.85) if tall else rng.randf_range(0.24, 0.5)
		var wdt := rng.randf_range(0.04, 0.065)
		var lean := rng.randf_range(0.08, 0.4)
		var side := Vector3(cos(yaw), 0, sin(yaw))
		var fwd := Vector3(-sin(yaw), 0, cos(yaw))
		var b0 := off - side * wdt
		var b1 := off + side * wdt
		var tip := off + fwd * (h * lean) + Vector3(0, h, 0)
		var n_dir := side.cross(tip - off).normalized()
		var tc: Color = tips[rng.randi_range(0, tips.size() - 1)]
		# 双面：正反两个三角形
		for face in [[b0, b1, tip, n_dir], [b1, b0, tip, -n_dir]]:
			for k in 3:
				var v: Vector3 = face[k]
				st.set_normal((face[3] as Vector3).lerp(Vector3.UP, 0.7).normalized())  # 法线偏上，草地整体受光更均匀
				st.set_color(tc if k == 2 else root)
				st.set_uv(Vector2(v.x, v.y))
				st.add_vertex(v)
	var mesh := st.commit()
	mesh.surface_set_material(0, Mats.get_mat("blade"))
	if kind == "flower":
		var mb := MB.new()
		var heads := ["red_0", "light_0", "frame_0", "cloth_yellow", "red_0"]
		var col: String = heads[rng.randi_range(0, heads.size() - 1)]
		for k in rng.randi_range(2, 4):
			var a := rng.randf() * TAU
			var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.03, 0.12)
			var hh := rng.randf_range(0.28, 0.42)
			mb.tube("flat_grass_2", p, p + Vector3(0, hh, 0), 0.008, 0.008, 3)
			mb.ngon_frustum("flat_" + col, p, hh - 0.02, hh + 0.025, 0.045, 0.03, 5, a, true, true)
			mb.ngon_frustum("flat_light_1", p, hh + 0.025, hh + 0.035, 0.015, 0.0, 4, a, false)
		mesh = _merge(mb.commit(), mesh)
	return mesh


static func _merge(a: ArrayMesh, b: ArrayMesh) -> ArrayMesh:
	for s in b.get_surface_count():
		a.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.surface_get_arrays(s))
		a.surface_set_material(a.get_surface_count() - 1, b.surface_get_material(s))
	return a


## 草丛变体：优先用 Blender 版（bl_grass_tuft 前 4 个是普通草、后 2 个是高草；bl_grass_dry；bl_grass_flower），
## 没有 Blender 资产时用代码版
static func variants(kind: String) -> Array[Mesh]:
	if not _cache.has(kind):
		var arr: Array[Mesh] = []
		var bl := PWAssetLibrary.blender_variants({"grass": "bl_grass_tuft", "tall": "bl_grass_tuft",
			"dry": "bl_grass_dry", "flower": "bl_grass_flower"}[kind])
		if kind == "grass":
			bl = bl.slice(0, 4)
		elif kind == "tall":
			bl = bl.slice(4)
		arr.append_array(bl)
		for i in VARIANTS if arr.is_empty() else 0:
			arr.append(build_tuft(7000 + KINDS.find(kind) * 100 + i, kind))
		_cache[kind] = arr
	return _cache[kind]


## 按规则撒草。
##   density(p: Vector2) -> float：风格给的基础密度 0..1（已排除的地方返回 0）
##   ground(p: Vector2) -> float：地面高度
##   dryness(p: Vector2) -> float：0..1，越大越多干草（沙滩 / 岩石附近）
## opts：budget（最多几丛）、flowers（花的比例 0..1）、half（场景半边长）
static func scatter(pl: PWPlacement, batch: PWBatcher, rng: RandomNumberGenerator, density: Callable,
		ground: Callable, dryness: Callable, opts: Dictionary) -> int:
	var half: float = opts.get("half", 40.0)
	var budget: int = opts.get("budget", 3000)
	var flowers: float = opts.get("flowers", 0.1)
	var clump := FastNoiseLite.new()
	clump.seed = rng.randi()
	clump.frequency = 0.09
	var bloom := FastNoiseLite.new()
	bloom.seed = rng.randi()
	bloom.frequency = 0.06
	var placed := 0
	var steps := int(half * 2.0 / SPACING)
	# 随机起点的行顺序，预算用完时不会只铺满地图的一半
	var order := range(steps)
	_shuffle(order, rng)
	for jj: int in order:
		for ii in steps:
			if placed >= budget:
				return placed
			var p := Vector2(-half + (ii + rng.randf()) * SPACING, -half + (jj + rng.randf()) * SPACING)
			var d: float = density.call(p)
			if d <= 0.0:
				continue
			var c := clump.get_noise_2d(p.x, p.y) * 0.5 + 0.5
			if rng.randf() > d * smoothstep(0.25, 0.65, c):
				continue
			if not pl.can_place(P.GRASS, p, 0.12):
				continue
			var kind := "grass"
			var dry: float = dryness.call(p)
			if rng.randf() < dry * 0.8:
				kind = "dry"
			elif rng.randf() < flowers * 2.0 * smoothstep(0.55, 0.8, bloom.get_noise_2d(p.x, p.y) * 0.5 + 0.5):
				kind = "flower"
			elif c > 0.7 and rng.randf() < 0.5:
				kind = "tall"
			var vs := variants(kind)
			var s := rng.randf_range(0.8, 1.3)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s)),
				Vector3(p.x, float(ground.call(p)) - 0.02, p.y))
			batch.add_plant(vs[rng.randi_range(0, vs.size() - 1)], xf, _tint(rng), false)
			placed += 1
	return placed


static func _tint(rng: RandomNumberGenerator) -> Color:
	var k := rng.randf_range(0.88, 1.08)
	return Color(k * rng.randf_range(0.95, 1.05), k, k * rng.randf_range(0.92, 1.03), 1.0)


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t
