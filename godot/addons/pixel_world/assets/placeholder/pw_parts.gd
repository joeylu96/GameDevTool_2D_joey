@tool
extends RefCounted
## 建筑部件：窗户、门。都是独立的 3D 部件（有厚度的框、窗棂、玻璃、窗台、百叶窗、门板、门把手），
## 房屋、灯塔等共用。墙体是实心盒子，所以部件全部贴在墙面外侧，靠一层层外凸做出凹凸感。
##
## 坐标约定：c = 部件底边中点（在墙面上），n = 墙面外法线（±X 或 ±Z）。
## 部件局部坐标 (lx, ly, ld)：lx 沿「从墙外看的左方向」，ly 向上，ld 沿外法线（离墙距离）。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")


## 窗户。hw = 半宽，h = 高。opts：
##   panes_x / panes_y（窗格数，默认 2×2）、shutters（百叶窗材质键，"" = 无）、
##   flowers（窗下花箱）、rnd（0..1，夜里是否亮灯的随机数，见 glass 材质的 emission_random_off）
static func window(mb: MB, c: Vector3, n: Vector3, hw: float, h: float, opts := {}) -> void:
	var left := n.cross(Vector3.UP)
	var ft := 0.07
	var px: int = opts.get("panes_x", 2)
	var py: int = opts.get("panes_y", 2)
	# 玻璃
	mb.color = Color(1, 1, 1, opts.get("rnd", 0.5))
	var g := c + n * 0.012
	mb.face("glass", [g + left * hw + Vector3(0, h, 0), g - left * hw + Vector3(0, h, 0), g - left * hw, g + left * hw], n)
	mb.color = Color.WHITE
	# 窗框
	_lbox(mb, "trim", c, left, n, -hw - ft * 0.5, hw + ft * 0.5, h - ft * 0.5, h + ft * 0.5, 0.0, 0.06)
	_lbox(mb, "trim", c, left, n, -hw - ft * 0.5, hw + ft * 0.5, -ft * 0.5, ft * 0.5, 0.0, 0.06)
	_lbox(mb, "trim", c, left, n, hw - ft * 0.5, hw + ft * 0.5, ft * 0.5, h - ft * 0.5, 0.0, 0.06)
	_lbox(mb, "trim", c, left, n, -hw - ft * 0.5, -hw + ft * 0.5, ft * 0.5, h - ft * 0.5, 0.0, 0.06)
	# 窗棂
	for i in range(1, px):
		var x := -hw + 2.0 * hw * i / px
		_lbox(mb, "trim", c, left, n, x - 0.022, x + 0.022, ft * 0.5, h - ft * 0.5, 0.0, 0.035)
	for j in range(1, py):
		var y := h * j / py
		_lbox(mb, "trim", c, left, n, -hw + ft * 0.5, hw - ft * 0.5, y - 0.022, y + 0.022, 0.0, 0.035)
	# 窗台 + 窗楣（带一道小檐口）
	_lbox(mb, "trim", c, left, n, -hw - 0.11, hw + 0.11, -0.13, -ft * 0.5, 0.0, 0.16)
	_lbox(mb, "trim", c, left, n, -hw - 0.1, hw + 0.1, h + ft * 0.5, h + ft * 0.5 + 0.1, 0.0, 0.07)
	_lbox(mb, "trim", c, left, n, -hw - 0.14, hw + 0.14, h + ft * 0.5 + 0.1, h + ft * 0.5 + 0.14, 0.0, 0.12)
	# 百叶窗：窗户两侧各一扇，带两道横档
	var sh: String = opts.get("shutters", "")
	if sh != "":
		var sw := hw * 0.9
		for side in [-1.0, 1.0]:
			var a := hw + ft * 0.5 + 0.03
			var x0: float = side * a
			var x1: float = side * (a + sw)
			_lbox(mb, sh, c, left, n, minf(x0, x1), maxf(x0, x1), 0.0, h, 0.0, 0.04)
			for yy in [h * 0.22, h * 0.78]:
				_lbox(mb, sh, c, left, n, minf(x0, x1) + 0.03, maxf(x0, x1) - 0.03, yy - 0.03, yy + 0.03, 0.04, 0.06)
	# 花箱
	if opts.get("flowers", false):
		_lbox(mb, "wall_wood", c, left, n, -hw - 0.05, hw + 0.05, -0.46, -0.13, 0.16, 0.42)
		_lbox(mb, "flowers", c, left, n, -hw, hw, -0.13, 0.04, 0.18, 0.4)


## 门。opts：w（宽，默认 1.05）、h（高，默认 2.05）、mat（门板材质，默认 door_wood）、
## glass_top（上半部是否带玻璃，默认 true）、rnd（门上玻璃夜里亮灯的随机数）
static func door(mb: MB, c: Vector3, n: Vector3, opts := {}) -> void:
	var left := n.cross(Vector3.UP)
	var w: float = opts.get("w", 1.05)
	var h: float = opts.get("h", 2.05)
	var mat: String = opts.get("mat", "door_wood")
	var hw := w * 0.5
	var ft := 0.1
	# 门框 + 门楣檐口
	_lbox(mb, "trim", c, left, n, hw, hw + ft, 0.0, h + ft, 0.0, 0.09)
	_lbox(mb, "trim", c, left, n, -hw - ft, -hw, 0.0, h + ft, 0.0, 0.09)
	_lbox(mb, "trim", c, left, n, -hw, hw, h, h + ft, 0.0, 0.09)
	_lbox(mb, "trim", c, left, n, -hw - ft - 0.07, hw + ft + 0.07, h + ft, h + ft + 0.07, 0.0, 0.15)
	# 门板
	_lbox(mb, mat, c, left, n, -hw, hw, 0.0, h, 0.0, 0.035)
	# 下半部两块凸起的嵌板
	for side in [-1.0, 1.0]:
		var x0: float = side * 0.05
		var x1: float = side * (hw - 0.1)
		_lbox(mb, mat, c, left, n, minf(x0, x1), maxf(x0, x1), 0.14, h * 0.44, 0.035, 0.055)
	# 上半部：玻璃 + 十字窗棂，或两块嵌板
	var y0 := h * 0.54
	var y1 := h - 0.12
	if opts.get("glass_top", true):
		mb.color = Color(1, 1, 1, opts.get("rnd", 0.9))
		var g := c + n * 0.04
		var gx := hw - 0.13
		mb.face("glass", [g + left * gx + Vector3(0, y1, 0), g - left * gx + Vector3(0, y1, 0),
			g - left * gx + Vector3(0, y0, 0), g + left * gx + Vector3(0, y0, 0)], n)
		mb.color = Color.WHITE
		_lbox(mb, mat, c, left, n, -gx - 0.04, gx + 0.04, y1, y1 + 0.04, 0.035, 0.065)
		_lbox(mb, mat, c, left, n, -gx - 0.04, gx + 0.04, y0 - 0.04, y0, 0.035, 0.065)
		_lbox(mb, mat, c, left, n, gx, gx + 0.04, y0, y1, 0.035, 0.065)
		_lbox(mb, mat, c, left, n, -gx - 0.04, -gx, y0, y1, 0.035, 0.065)
		_lbox(mb, mat, c, left, n, -0.018, 0.018, y0, y1, 0.035, 0.055)
	else:
		for side in [-1.0, 1.0]:
			var x0: float = side * 0.05
			var x1: float = side * (hw - 0.1)
			_lbox(mb, mat, c, left, n, minf(x0, x1), maxf(x0, x1), y0, y1, 0.035, 0.055)
	# 门把手（从外面看在右侧）+ 底板
	var hx := -(hw - 0.14)
	_lbox(mb, "brass", c, left, n, hx - 0.03, hx + 0.03, h * 0.46, h * 0.54, 0.035, 0.05)
	_lbox(mb, "brass", c, left, n, hx - 0.07, hx + 0.02, h * 0.49, h * 0.51, 0.05, 0.11)


## 部件局部坐标下的方盒（墙面坐标轴对齐时，世界包围盒就是两个角点的最小 / 最大值）
static func _lbox(mb: MB, mat: String, c: Vector3, left: Vector3, n: Vector3,
		x0: float, x1: float, y0: float, y1: float, d0: float, d1: float) -> void:
	var a := c + left * x0 + n * d0 + Vector3(0, y0, 0)
	var b := c + left * x1 + n * d1 + Vector3(0, y1, 0)
	mb.box(mat, Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)),
		Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)))
