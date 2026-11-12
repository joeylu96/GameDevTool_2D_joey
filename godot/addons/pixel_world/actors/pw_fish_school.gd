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
		var kind := i % 2  # 一半银色、一半橙色
		var p := Vector3(rng.randf_range(area.position.x, area.end.x), water_y - 0.3,
			rng.randf_range(area.position.y, area.end.y))
		_fish.append({"kind": kind, "idx": _counts[kind], "pos": p, "heading": rng.randf() * TAU,
			"turn": 0.0, "speed": 0.4, "base": rng.randf_range(0.3, 0.6), "phase": rng.randf() * TAU,
			"scale": rng.randf_range(1.2, 1.8), "dive": rng.randf_range(0.0, 0.2)})
		_counts[kind] += 1
	for k in KINDS.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Props.build_fish(KINDS[k])
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


func _process(delta: float) -> void:
	var center := area.get_center()
	for f in _fish:
		var pos: Vector3 = f.pos
		var heading: float = f.heading
		f.turn = clampf(f.turn + randf_range(-1.0, 1.0) * delta * 3.0, -1.0, 1.0)
		var desired: float = heading + f.turn * delta
		var spd: float = f.base
		var fwd := Vector3(sin(heading), 0, cos(heading))
		var ahead := pos + fwd * 0.9
		if not area.has_point(Vector2(ahead.x, ahead.z)) or _depth(ahead) < min_depth:
			var to_c := Vector2(center.x - pos.x, center.y - pos.z)
			desired = lerp_angle(heading, atan2(to_c.x, to_c.y), delta * 3.0)
		if threat != null:
			var away := Vector2(pos.x - threat.global_position.x, pos.z - threat.global_position.z)
			if away.length() < 2.4:
				desired = lerp_angle(heading, atan2(away.x, away.y), delta * 6.0)
				spd = 2.4
		f.heading = desired
		f.speed = lerpf(f.speed, spd, delta * 3.0)
		pos += Vector3(sin(desired), 0, cos(desired)) * float(f.speed) * delta
		var bed := water_y - _depth(pos)
		pos.y = clampf(water_y - 0.18 - float(f.dive), bed + 0.1, water_y - 0.1)
		f.pos = pos
		f.phase += delta * (5.0 + float(f.speed) * 8.0)
		var yaw: float = desired + sin(f.phase) * 0.18
		var s: float = f.scale
		_mms[f.kind].set_instance_transform(f.idx, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), pos))
