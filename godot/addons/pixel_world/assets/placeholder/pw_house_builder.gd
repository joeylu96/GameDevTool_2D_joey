@tool
extends RefCounted
## 占位房屋：木板墙 + 双坡屋顶（带厚度、白色封檐、屋脊盖板）+ 白色转角 + 窗/门 + 烟囱。
## 细节：窗台和窗楣、一楼花箱、两层楼的腰线、门廊雨棚、老虎窗。
## 正门朝 +Z。Blender 资产到位前用它跑通全流程。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")

const WALLS := ["wall_red", "wall_red", "wall_ochre", "wall_teal", "wall_wood"]
const FLOOR_H := 2.8
const BASE_H := 0.35
const OVERHANG := 0.45
const ROOF_T := 0.18
const WIN_HW := 0.5   # 窗户半宽
const WIN_H := 1.25


## 随机参数（可复现）。只决定大的形体；细节由 _details() 从这些参数派生，
## 不额外消耗调用方的随机数，因此增删细节不会打乱整个小镇的布局。
static func random_params(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"width": MB.snap(rng.randf_range(6.0, 10.0)),
		"depth": MB.snap(rng.randf_range(5.0, 6.5)),
		"floors": 2 if rng.randf() < 0.35 else 1,
		"wall": WALLS[rng.randi_range(0, WALLS.size() - 1)],
		"pitch": rng.randf_range(34.0, 42.0),
		"chimney": rng.randf() < 0.65,
		"chimney_x": rng.randf_range(-0.6, 0.6),
	}


## 占地（含屋檐）
static func footprint(p: Dictionary) -> Vector2:
	return Vector2(p.width + OVERHANG * 2.0, p.depth + OVERHANG * 2.0)


## 细节参数：老虎窗数量、花箱、雨棚、屋顶颜色。已显式给出的键不会被覆盖。
static func _details(p: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([p.width, p.depth, p.pitch, p.wall])
	var d := {
		"dormers": (rng.randi_range(1, 2) if p.width >= 7.5 else 1) if rng.randf() < 0.55 else 0,
		"flowers": rng.randf() < 0.55,
		"canopy": rng.randf() < 0.6,
		"roof": "roof_red" if p.wall != "wall_red" and rng.randf() < 0.3 else "roof_grey",
	}
	d.merge(p, true)
	return d


static func build(params: Dictionary) -> ArrayMesh:
	var p := _details(params)
	var mb := MB.new()
	var w: float = p.width
	var d: float = p.depth
	var floors: int = p.floors
	var wall: String = p.wall
	var roof: String = p.roof
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
	# 两层楼：楼层之间一圈白色腰线
	if floors > 1:
		var yb := BASE_H + FLOOR_H - 0.06
		mb.box("trim", Vector3(-hw - 0.05, yb, -hd - 0.05), Vector3(hw + 0.05, yb + 0.14, hd + 0.05))

	# 屋顶：两片有厚度的斜板 + 屋脊盖板
	var eave_y := h - OVERHANG * tan(pitch)
	var ze := hd + OVERHANG
	var xe := hw + OVERHANG
	var t := Vector3(0, ROOF_T, 0)
	for s in [-1.0, 1.0]:
		var tl := Vector3(-xe, ridge, 0)
		var tr := Vector3(xe, ridge, 0)
		var br := Vector3(xe, eave_y, s * ze)
		var bl := Vector3(-xe, eave_y, s * ze)
		mb.face(roof, [tl, tr, br, bl], Vector3(0, 1, s))
		mb.face("roof_under", [tl - t, tr - t, br - t, bl - t], Vector3(0, -1, -s))
		mb.face("trim", [bl, br, br - t, bl - t], Vector3(0, 0, s))
		for sx in [-1.0, 1.0]:
			var a := Vector3(sx * xe, ridge, 0)
			var b := Vector3(sx * xe, eave_y, s * ze)
			mb.face("trim", [a, b, b - t, a - t], Vector3(sx, 0, 0))
	mb.box("roof_cap", Vector3(-xe - 0.03, ridge - 0.06, -0.14), Vector3(xe + 0.03, ridge + 0.1, 0.14))

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
				_window(mb, Vector3(x, y0, s * hd), Vector3(0, 0, s), f == 0 and s > 0 and p.flowers)
	# 山墙小窗
	for sx in [-1.0, 1.0]:
		if ridge - h > 1.9:
			_window(mb, Vector3(sx * hw, h + 0.15, 0), Vector3(sx, 0, 0), false)
	# 门 + 台阶 + 雨棚
	var zd := hd + 0.02
	mb.quad01("door", Vector3(-0.625, BASE_H + 2.0, zd), Vector3(0.625, BASE_H + 2.0, zd),
		Vector3(0.625, BASE_H, zd), Vector3(-0.625, BASE_H, zd), Vector3.BACK)
	mb.box("stone", Vector3(-0.9, 0.0, hd), Vector3(0.9, 0.2, hd + 0.6))
	if p.canopy:
		_canopy(mb, hd, BASE_H + 2.3, roof)

	# 烟囱（后坡）
	var cx: float = p.get("chimney_x", 0.3) * hw
	var cz := -hd * 0.4
	if p.get("chimney", false):
		mb.box("brick", Vector3(cx - 0.35, h, cz - 0.35), Vector3(cx + 0.35, ridge + 0.9, cz + 0.35))
		mb.box("stone", Vector3(cx - 0.42, ridge + 0.9, cz - 0.42), Vector3(cx + 0.42, ridge + 1.05, cz + 0.42))

	# 老虎窗：前后坡各一排，后坡避开烟囱
	var nd: int = p.dormers
	for i in nd:
		var xd := -hw + w * (i + 1) / (nd + 1)
		for s in [-1.0, 1.0]:
			if s < 0 and p.get("chimney", false) and absf(xd - cx) < 1.4:
				continue
			_dormer(mb, xd, s, hd, ridge, pitch, wall, roof)
	return mb.commit()


## 窗户 + 窗台 + 窗楣，可选花箱。c = 窗户底边中点（在墙面上），n = 墙面外法线（±X 或 ±Z）
static func _window(mb: MB, c: Vector3, n: Vector3, flowers: bool, hw := WIN_HW, wh := WIN_H) -> void:
	var left := n.cross(Vector3.UP)  # 从墙外看过去的左方向
	var top := Vector3(0, wh, 0)
	var o := c + n * 0.02
	mb.quad01("window", o + left * hw + top, o - left * hw + top, o - left * hw, o + left * hw, n)
	_obox(mb, "trim", c, left, n, hw + 0.12, c.y - 0.1, c.y, 0.0, 0.14)            # 窗台
	_obox(mb, "trim", c, left, n, hw + 0.1, c.y + wh, c.y + wh + 0.1, 0.0, 0.06)   # 窗楣
	if flowers:
		_obox(mb, "wall_wood", c, left, n, hw + 0.05, c.y - 0.42, c.y - 0.06, 0.14, 0.42)
		_obox(mb, "flowers", c, left, n, hw, c.y - 0.06, c.y + 0.1, 0.16, 0.4)


## 贴墙的小方块：沿墙宽 ±hw，高 y0..y1，离墙 d0..d1（沿法线方向）
static func _obox(mb: MB, mat: String, c: Vector3, left: Vector3, n: Vector3,
		hw: float, y0: float, y1: float, d0: float, d1: float) -> void:
	var a := c + left * hw + n * d0
	var b := c - left * hw + n * d1
	mb.box(mat, Vector3(minf(a.x, b.x), y0, minf(a.z, b.z)), Vector3(maxf(a.x, b.x), y1, maxf(a.z, b.z)))


## 门廊雨棚：单坡小屋顶 + 白色封边 + 两个托架
static func _canopy(mb: MB, hd: float, cy: float, roof: String) -> void:
	var ze := hd + 0.85
	var hw := 1.0
	var a := Vector3(-hw, cy + 0.35, hd)
	var b := Vector3(hw, cy + 0.35, hd)
	var c := Vector3(hw, cy, ze)
	var d := Vector3(-hw, cy, ze)
	var t := Vector3(0, 0.1, 0)
	mb.face(roof, [a, b, c, d], Vector3(0, 1, 1))
	mb.face("roof_under", [a - t, b - t, c - t, d - t], Vector3(0, -1, 0))
	mb.face("trim", [d, c, c - t, d - t], Vector3.BACK)
	for sx in [-1.0, 1.0]:
		var p0 := Vector3(sx * hw, cy + 0.35, hd)
		var p1 := Vector3(sx * hw, cy, ze)
		mb.face("trim", [p0, p1, p1 - t, p0 - t], Vector3(sx, 0, 0))
		mb.box("trim", Vector3(sx * 0.85 - 0.05, cy - 0.45, hd), Vector3(sx * 0.85 + 0.05, cy + 0.25, hd + 0.12))


## 老虎窗：一个嵌进屋面的小盒子 + 自己的双坡小屋顶 + 正面小窗。s = 1 前坡，-1 后坡
static func _dormer(mb: MB, xd: float, s: float, hd: float, ridge: float, pitch: float,
		wall: String, roof: String) -> void:
	var zf := hd * 0.62                  # 正面到屋脊的水平距离
	var yr := ridge - zf * tan(pitch)    # 正面底边处的屋面高度
	var dh := minf(1.05, zf * tan(pitch) - 0.3)
	if dh < 0.7:
		return  # 屋顶太平，放不下
	var dw := 0.75
	var zb := maxf(zf - 1.6, 0.05)
	var ye := yr + dh
	var yt := ye + dw * 0.95
	# 墙体：下半截埋进屋面，从上方看不到
	mb.box(wall, Vector3(xd - dw, yr - 0.6, minf(s * zb, s * zf)), Vector3(xd + dw, ye, maxf(s * zb, s * zf)), false)
	mb.face(wall, [Vector3(xd - dw, ye, s * zf), Vector3(xd + dw, ye, s * zf), Vector3(xd, yt - 0.02, s * zf)], Vector3(0, 0, s))
	# 小屋顶：屋脊沿 Z，向前出挑
	var zo := s * (zf + 0.2)
	var zbk := s * zb
	var dwr := dw + 0.14
	var t := Vector3(0, 0.1, 0)
	for side in [-1.0, 1.0]:
		var a := Vector3(xd, yt, zbk)
		var b := Vector3(xd, yt, zo)
		var c := Vector3(xd + side * dwr, ye - 0.08, zo)
		var d := Vector3(xd + side * dwr, ye - 0.08, zbk)
		mb.face(roof, [a, b, c, d], Vector3(side, 1, 0))
		mb.face("trim", [b, c, c - t, b - t], Vector3(0, 0, s))
	# 正面小窗
	_window(mb, Vector3(xd, yr + 0.12, s * zf), Vector3(0, 0, s), false, 0.32, 0.7)
