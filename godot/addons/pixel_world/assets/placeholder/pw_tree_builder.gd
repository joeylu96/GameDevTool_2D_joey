@tool
extends RefCounted
## 占位松树：方形棱台层层叠起（体素感），坡面能接住积雪。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")


static func build_pine(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mb := MB.new()
	var tiers := rng.randi_range(3, 4)
	var total_h := rng.randf_range(3.4, 4.8)
	var base_r := rng.randf_range(1.1, 1.45)
	mb.box("trunk", Vector3(-0.19, 0, -0.19), Vector3(0.19, 0.9, 0.19), false)
	var y := 0.6
	var tier_h := total_h / tiers * 1.2
	# 每层 = 陡峭裙边（不积雪，露出深绿）+ 平缓顶盖（积雪），形成一圈圈雪檐
	for i in tiers:
		var r := MB.snap(base_r * (1.0 - float(i) / tiers * 0.62))
		var last := i == tiers - 1
		var y_mid := MB.snap(y + tier_h * 0.42)
		var r_mid := MB.snap(r * 0.8)
		mb.frustum("pine", Vector3.ZERO, MB.snap(y), y_mid, r, r_mid)
		mb.frustum("pine", Vector3.ZERO, y_mid, MB.snap(y + tier_h * (1.0 if last else 0.8)), r_mid, 0.0 if last else MB.snap(r * 0.2), false)
		y += tier_h * 0.6
	return mb.commit()


## 路灯：灯杆 + 玻璃灯箱（夜间发光）+ 小顶
static func build_lamp() -> ArrayMesh:
	var mb := MB.new()
	mb.box("metal", Vector3(-0.15, 0, -0.15), Vector3(0.15, 0.3, 0.15))
	mb.box("metal", Vector3(-0.06, 0.3, -0.06), Vector3(0.06, 2.5, 0.06), false)
	mb.box("metal", Vector3(-0.19, 2.5, -0.19), Vector3(0.19, 2.56, 0.19))
	mb.box("bulb", Vector3(-0.15, 2.56, -0.15), Vector3(0.15, 2.9, 0.15), false)
	mb.frustum("metal", Vector3.ZERO, 2.9, 3.08, 0.24, 0.0)
	return mb.commit()
