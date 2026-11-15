@tool
class_name PWFishSchool
extends Node3D
## 一群在浅水区游动的小鱼（MultiMesh，一种颜色一个）。随机漫游；快出界或水太浅时掉头；
## threat（例如玩家）靠近时受惊加速游开。
##
## 由场景提供：bed_height(x, z) -> float 湖底高度（用来保证鱼在水里、离湖底有一点距离）。

const Props := preload("res://addons/pixel_world/assets/placeholder/pw_props_builder.gd")
const KINDS := ["fish_silver", "fish_orange"]

@export var count := 18
## 活动范围（世界 XZ）
@export var area := Rect2(-30, 23.6, 60, 3.0)
@export var water_y := -0.45
@export var min_depth := 0.35
@export var seed_value := 77

var bed_height: Callable
var threat: Node3D

var _fish: Array[Dictionary] = []
var _mms: Array[MultiMesh] = []
var _counts := [0, 0]


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		# 只在够深的水里出生（活动范围是个矩形，里面可能有陆地）；找不到就不放这条鱼
		var p := Vector3.ZERO
		var found := false
		for attempt in 200:
			p = Vector3(rng.randf_range(area.position.x, area.end.x), water_y - 0.3,
				rng.randf_range(area.position.y, area.end.y))
			if _depth(p) >= min_depth + 0.15:
				found = true
				break
		if not found:
			continue
		var kind := _fish.size() % 2  # 一半银色、一半橙色
		_fish.append({"kind": kind, "idx": _counts[kind], "pos": p, "home": p, "heading": rng.randf() * TAU,
			"turn": 0.0, "speed": 0.4, "base": rng.randf_range(0.3, 0.6), "phase": rng.randf() * TAU,
			"scale": rng.randf_range(1.2, 1.8), "dive": rng.randf_range(0.0, 0.2)})
		_counts[kind] += 1
	for k in KINDS.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# Blender 小鱼：变体 0 橙色、1 银色；没有 Blender 资产时用代码版
		var bl := PWAssetLibrary.blender_variants("bl_fish")
		mm.mesh = bl[1 - k] if bl.size() >= 2 else Props.build_fish(KINDS[k])
		mm.instance_count = _counts[k]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mms.append(mm)


func _depth(p: Vector3) -> float:
	if not bed_height.is_valid():
		return 1.0
	return water_y - float(bed_height.call(p.x, p.z))


## 鱼能不能待在这里：在活动范围内、水够深
func _swimmable(p: Vector3) -> bool:
	return area.has_point(Vector2(p.x, p.z)) and _depth(p) >= min_depth


func _process(delta: float) -> void:
	for f in _fish:
		var pos: Vector3 = f.pos
		var home: Vector3 = f.home
		if not _swimmable(pos):
			pos = home  # 兜底：万一出现在浅水 / 岸上，放回出生点
		var heading: float = f.heading
		f.turn = clampf(f.turn + randf_range(-1.0, 1.0) * delta * 3.0, -1.0, 1.0)
		var desired: float = heading + f.turn * delta
		var spd: float = f.base
		var to_home := Vector2(home.x - pos.x, home.z - pos.z)
		# 提前看前方：快到浅水就转向自己的出生点（出生点一定在深水里）
		var fwd := Vector3(sin(heading), 0, cos(heading))
		if not _swimmable(pos + fwd * 1.2):
			desired = lerp_angle(heading, atan2(to_home.x, to_home.y), minf(delta * 4.0, 1.0))
		elif to_home.length() > 9.0:
			desired = lerp_angle(desired, atan2(to_home.x, to_home.y), minf(delta * 0.6, 1.0))  # 别游得离家太远
		if threat != null:
			var away := Vector2(pos.x - threat.global_position.x, pos.z - threat.global_position.z)
			if away.length() < 2.4:
				var flee := atan2(away.x, away.y)
				# 逃跑方向也必须是水：不行就沿岸往家的方向逃
				if not _swimmable(pos + Vector3(sin(flee), 0, cos(flee)) * 1.2):
					flee = atan2(to_home.x, to_home.y)
				desired = lerp_angle(heading, flee, minf(delta * 6.0, 1.0))
				spd = 2.4
		f.speed = lerpf(f.speed, spd, minf(delta * 3.0, 1.0))
		var step := Vector3(sin(desired), 0, cos(desired)) * float(f.speed) * delta
		# 硬性约束：下一步水太浅就不走，原地掉头
		if _swimmable(pos + step):
			pos += step
		else:
			desired = atan2(to_home.x, to_home.y) + randf_range(-0.6, 0.6)
			f.speed = f.base * 0.5
		f.heading = desired
		var bed := water_y - _depth(pos)
		pos.y = clampf(water_y - 0.18 - float(f.dive), bed + 0.1, water_y - 0.1)
		f.pos = pos
		f.phase += delta * (5.0 + float(f.speed) * 8.0)
		var yaw: float = desired + sin(f.phase) * 0.18
		var s: float = f.scale
		_mms[f.kind].set_instance_transform(f.idx, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), pos))
