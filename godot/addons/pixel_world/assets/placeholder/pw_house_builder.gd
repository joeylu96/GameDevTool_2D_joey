@tool
extends RefCounted
## 占位房屋：木板墙 + 双坡屋顶（带厚度和白色封檐）+ 白色转角 + 窗/门 + 烟囱。
## 正门朝 +Z。Blender 资产到位前用它跑通全流程。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")

const WALLS := ["wall_red", "wall_red", "wall_ochre", "wall_teal", "wall_wood"]
const FLOOR_H := 2.8
const BASE_H := 0.35
const OVERHANG := 0.45
const ROOF_T := 0.18


## 随机参数（可复现）
static func random_params(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"width": MB.snap(rng.randf_range(6.0, 10.0)),
		"depth": MB.snap(rng.randf_range(5.0, 6.5)),
		"floors": 2 if rng.randf() < 0.35 else 1,
		"wall": WALLS[rng.randi_range(0, WALLS.size() - 1)],
		"roof": "roof_grey",
		"pitch": rng.randf_range(34.0, 42.0),
		"chimney": rng.randf() < 0.65,
		"chimney_x": rng.randf_range(-0.6, 0.6),
	}


## 占地（含屋檐）
static func footprint(p: Dictionary) -> Vector2:
	return Vector2(p.width + OVERHANG * 2.0, p.depth + OVERHANG * 2.0)


static func build(p: Dictionary) -> ArrayMesh:
	var mb := MB.new()
	var w: float = p.width
	var d: float = p.depth
	var floors: int = p.floors
	var wall: String = p.wall
	var hw := w * 0.5
	var hd := d * 0.5
	var h := BASE_H + FLOOR_H * floors
	var pitch := deg_to_rad(p.pitch)
	var ridge := h + hd * tan(pitch)

	# 地基 + 墙
	mb.box("stone", Vector3(-hw - 0.1, 0.0, -hd - 0.1), Vector3(hw + 0.1, BASE_H, hd + 0.1))
	mb.box(wall, Vector3(-hw, BASE_H, -hd), Vector3(hw, h, hd), false)
	# 山墙三角
	mb.face(wall, [Vector3(hw, h, -hd), Vector3(hw, h, hd), Vector3(hw, ridge, 0)], Vector3.RIGHT)
	mb.face(wall, [Vector3(-hw, h, hd), Vector3(-hw, h, -hd), Vector3(-hw, ridge, 0)], Vector3.LEFT)
	# 白色转角板
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * hw, 0, sz * hd)
			mb.box("trim", Vector3(c.x - 0.1, BASE_H, c.z - 0.1), Vector3(c.x + 0.1, h, c.z + 0.1), false)

	# 屋顶：两片有厚度的斜板
	var eave_y := h - OVERHANG * tan(pitch)
	var ze := hd + OVERHANG
	var xe := hw + OVERHANG
	var t := Vector3(0, ROOF_T, 0)
	for s in [-1.0, 1.0]:
		var tl := Vector3(-xe, ridge, 0)
		var tr := Vector3(xe, ridge, 0)
		var br := Vector3(xe, eave_y, s * ze)
		var bl := Vector3(-xe, eave_y, s * ze)
		mb.face(p.roof, [tl, tr, br, bl], Vector3(0, 1, s))
		mb.face("roof_under", [tl - t, tr - t, br - t, bl - t], Vector3(0, -1, -s))
		mb.face("trim", [bl, br, br - t, bl - t], Vector3(0, 0, s))
		for sx in [-1.0, 1.0]:
			var a := Vector3(sx * xe, ridge, 0)
			var b := Vector3(sx * xe, eave_y, s * ze)
			mb.face("trim", [a, b, b - t, a - t], Vector3(sx, 0, 0))

	# 窗户（前后墙）
	var n_win := maxi(1, int((w - 1.0) / 2.2))
	var spacing := w / n_win
	for f in floors:
		var y0 := BASE_H + f * FLOOR_H + 0.8
		for s in [-1.0, 1.0]:
			for i in n_win:
				var x := -hw + spacing * (i + 0.5)
				if f == 0 and s > 0 and absf(x) < 1.3:
					continue  # 给门让位
				var z: float = s * (hd + 0.02)
				mb.quad01("window",
					Vector3(x - s * 0.5, y0 + 1.25, z), Vector3(x + s * 0.5, y0 + 1.25, z),
					Vector3(x + s * 0.5, y0, z), Vector3(x - s * 0.5, y0, z), Vector3(0, 0, s))
	# 山墙小窗
	for sx in [-1.0, 1.0]:
		var xw: float = sx * (hw + 0.02)
		var yw := h + 0.15
		if ridge - h > 1.9:
			mb.quad01("window",
				Vector3(xw, yw + 1.25, sx * 0.5), Vector3(xw, yw + 1.25, -sx * 0.5),
				Vector3(xw, yw, -sx * 0.5), Vector3(xw, yw, sx * 0.5), Vector3(sx, 0, 0))
	# 门
	var zd := hd + 0.02
	mb.quad01("door", Vector3(-0.625, BASE_H + 2.0, zd), Vector3(0.625, BASE_H + 2.0, zd),
		Vector3(0.625, BASE_H, zd), Vector3(-0.625, BASE_H, zd), Vector3.BACK)
	mb.box("stone", Vector3(-0.9, 0.0, hd), Vector3(0.9, 0.2, hd + 0.6))  # 台阶

	# 烟囱（后坡）
	if p.get("chimney", false):
		var cx: float = p.get("chimney_x", 0.3) * hw
		var cz := -hd * 0.4
		mb.box("brick", Vector3(cx - 0.35, h, cz - 0.35), Vector3(cx + 0.35, ridge + 0.9, cz + 0.35))
		mb.box("stone", Vector3(cx - 0.42, ridge + 0.9, cz - 0.42), Vector3(cx + 0.42, ridge + 1.05, cz + 0.42))
	return mb.commit()
