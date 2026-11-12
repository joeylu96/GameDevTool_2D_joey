@tool
extends RefCounted
## 程序化像素贴图。全部只用调色板颜色，按 16 texel/米 设计（32px 贴图 = 2 米一循环）。
## 用于占位资产；Blender 资产到位后可替换，但风格规则相同：
##   1. 大面积用「成片色块」（可平铺的值噪声），不用逐像素随机杂点——缩到屏幕像素后会显得脏。
##   2. 细节用成簇的小笔触（草丛、针叶、石子），每个笔触都有「亮面 + 下方阴影」。
##   3. 地面类贴图（顶面）生成后 flip_y：俯视镜头里贴图 +v 指向远处，翻转后「阴影在下」方向才正确。

const Pal := preload("res://addons/pixel_world/core/pw_palette.gd")

static var _cache := {}


static func get_tex(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var img: Image
	match key:
		"wall_red":
			img = planks(["red_0", "red_1", "red_2", "red_3"], 101)
		"wall_ochre":
			img = planks(["ochre_0", "ochre_1", "ochre_2", "ochre_3"], 102)
		"wall_teal":
			img = planks(["teal_0", "teal_1", "teal_2", "teal_3"], 103)
		"wall_wood":
			img = planks(["wood_0", "wood_1", "wood_2", "wood_3"], 104)
		"roof_grey":
			img = shingles(["stone_0", "roof_0", "roof_1", "roof_2"], 201)
		"roof_red":
			img = shingles(["red_0", "red_1", "red_2", "red_3"], 202)
		"trim":
			img = speckle(["frame_0", "frame_1"], 16, 301, 0.04, 0.0)
		"stone":
			img = bricks(["stone_0", "stone_1", "stone_2", "stone_3"], 401, 8)
		"brick":
			img = bricks(["red_1", "red_2", "red_2", "red_3"], 402, 6)
		"curb":
			img = bricks(["snow_3", "stone_0", "stone_0", "stone_2"], 403, 16)
		"pine":
			img = needles(["pine_1", "pine_0", "pine_2"], 501, false)
		"pine_skirt":
			img = needles(["pine_2", "pine_1", "pine_3"], 502, true)
		"leaf":
			img = leaves(["grass_1", "grass_0", "grass_2"], 503)
		"leaf_dark":
			img = leaves(["grass_2", "grass_1", "pine_1"], 504)
		"trunk":
			img = planks(["wood_1", "wood_2", "wood_2", "wood_3"], 505, 16, 3)
		"rock":
			img = blotches(["stone_1", "stone_0", "stone_2"], 32, 506)
		"metal":
			img = speckle(["stone_3", "stone_2", "ink"], 16, 601, 0.15, 0.1)
		"lamp_glass":
			img = speckle(["light_0", "light_1", "frame_0"], 16, 602, 0.2, 0.0)
		"grass":
			img = grass(701)
		"dirt":
			img = dirt(702)
		"earth":
			img = bricks(["dirt_1", "dirt_2", "stone_2", "dirt_2"], 703, 10)
		"cobble":
			img = cobbles(801)
		"window":
			img = window(false)
		"window_emit":
			img = window(true)
		"door":
			img = door()
		_:
			img = Image.create(1, 1, false, Image.FORMAT_RGBA8)
			img.fill(Color.MAGENTA)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## 环绕写像素（保证贴图无缝平铺）
static func _px(img: Image, x: int, y: int, col: Color) -> void:
	img.set_pixel(posmod(x, img.get_width()), posmod(y, img.get_height()), col)


## 可平铺的值噪声：周期 = size，cells = 每个周期的格子数。返回 size*size 个 0..1 的值。
static func tile_noise(size: int, cells: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(cells * cells)
	for i in g.size():
		g[i] = rng.randf()
	var out := PackedFloat32Array()
	out.resize(size * size)
	var cell := float(size) / cells
	for y in size:
		for x in size:
			var fx := x / cell
			var fy := y / cell
			var ix := int(fx)
			var iy := int(fy)
			var tx := fx - ix
			var ty := fy - iy
			tx = tx * tx * (3.0 - 2.0 * tx)
			ty = ty * ty * (3.0 - 2.0 * ty)
			var x0 := ix % cells
			var x1 := (ix + 1) % cells
			var y0 := iy % cells
			var y1 := (iy + 1) % cells
			var top := lerpf(g[y0 * cells + x0], g[y0 * cells + x1], tx)
			var bot := lerpf(g[y1 * cells + x0], g[y1 * cells + x1], tx)
			out[y * size + x] = lerpf(top, bot, ty)
	return out


## 两层叠加的值噪声，色块边缘更自然
static func fbm(size: int, cells: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var a := tile_noise(size, cells, rng)
	var b := tile_noise(size, cells * 2, rng)
	for i in a.size():
		a[i] = a[i] * 0.7 + b[i] * 0.3
	return a


## 竖向木板墙：cols = [亮, 主色, 缝, 最暗]。每块板左侧一列高光，偶有横向接缝和木纹。
static func planks(cols: Array, seed_value: int, size := 32, plank_w := 4) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var hi := Pal.c(cols[0])
	var seam_c := Pal.c(cols[2])
	for px in range(0, size, plank_w):
		var shade := Pal.c(cols[0] if rng.randf() < 0.25 else cols[1])
		var joint := rng.randi_range(0, size - 1)
		for x in range(px, min(px + plank_w, size)):
			for y in size:
				var col := shade
				if x == px:
					col = seam_c
				elif y == joint:
					col = seam_c
				elif x == px + 1:
					col = hi
				img.set_pixel(x, y, col)
		# 木纹：板中间 2~3 像素的竖向短线
		for i in 2:
			var gx := px + rng.randi_range(2, plank_w - 1)
			var gy := rng.randi_range(0, size - 1)
			for k in rng.randi_range(2, 3):
				_px(img, gx, gy + k, Pal.c(cols[3]) if k == 0 else seam_c)
	return img


## 瓦片屋顶（贴图 +v = 顺坡向下）：cols = [瓦唇高光, 主色A, 主色B, 缝/阴影]。
## 每排：顶部一行是上一排投下的阴影，底部一行是瓦唇高光。
static func shingles(cols: Array, seed_value: int, size := 32) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var row_h := 4
	var sw := 8
	for row in range(size / row_h):
		var offset := (row % 2) * (sw / 2) + rng.randi_range(0, 1)
		var shades := []
		for i in range(size / sw + 1):
			shades.append(Pal.c(cols[1] if rng.randf() < 0.35 else cols[2]))
		for y in range(row * row_h, row * row_h + row_h):
			var ly := y - row * row_h
			for x in size:
				var xi := x + offset
				var col: Color = shades[(xi / sw) % shades.size()]
				if ly == 0:
					col = Pal.c(cols[3])
				elif xi % sw == 0:
					col = Pal.c(cols[3])
				elif ly == row_h - 1 and col == Pal.c(cols[1]):
					col = Pal.c(cols[0])  # 只有较亮的瓦片带高光瓦唇，避免整排横线像砖墙
				img.set_pixel(x, y, col)
	return img


## 砖/石块：cols = [亮, 次亮, 暗, 灰缝]。每块顶行比本色亮一级。
static func bricks(cols: Array, seed_value: int, brick_w := 8, size := 32) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var row_h := 4
	for row in range(size / row_h):
		var offset := (row % 2) * (brick_w / 2)
		var shades: Array[int] = []
		for i in range(size / brick_w + 1):
			shades.append(rng.randi_range(0, 2))
		for y in range(row * row_h, row * row_h + row_h):
			var ly := y - row * row_h
			for x in size:
				var xi := x + offset
				var si: int = shades[(xi / brick_w) % shades.size()]
				var col := Pal.c(cols[si])
				if ly == 0 or xi % brick_w == 0:
					col = Pal.c(cols[3])
				elif ly == 1:
					col = Pal.c(cols[maxi(si - 1, 0)])
				img.set_pixel(x, y, col)
	return img


## 底色 + 随机杂点：cols = [底, 点1, 点2]（只用于小物件：金属、灯罩、封檐板）
static func speckle(cols: Array, size: int, seed_value: int, p1: float, p2: float) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var r := rng.randf()
			var col := Pal.c(cols[0])
			if r < p1:
				col = Pal.c(cols[1])
			elif r < p1 + p2:
				col = Pal.c(cols[2])
			img.set_pixel(x, y, col)
	return img


## 三色成片斑块：cols = [底, 亮斑, 暗斑]（石头等）
static func blotches(cols: Array, size: int, seed_value: int) -> Image:
	var rng := _rng(seed_value)
	var n := fbm(size, 4, rng)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := n[y * size + x]
			var col := Pal.c(cols[0])
			if v > 0.6:
				col = Pal.c(cols[1])
			elif v < 0.34:
				col = Pal.c(cols[2])
			img.set_pixel(x, y, col)
	return img


## 草地 96px（6 米一循环）：成片的明暗色块 + 小草丛 + 零星小花。
static func grass(seed_value: int, size := 96) -> Image:
	var rng := _rng(seed_value)
	var n := fbm(size, 6, rng)
	# 明度阶梯：暗 → 亮。色块用中间三级，草丛用相邻一级做高光/阴影
	var ramp := [Pal.c("pine_1"), Pal.c("grass_2"), Pal.c("grass_1"), Pal.c("grass_0"), Pal.c("grass_0")]
	var level := PackedInt32Array()
	level.resize(size * size)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := n[y * size + x]
			var l := 3 if v > 0.6 else (1 if v < 0.3 else 2)
			level[y * size + x] = l
			img.set_pixel(x, y, ramp[l])
	# 草丛：「亮 · 亮」上排 + 中间一点阴影
	for i in size * size / 26:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		var l := level[y * size + x]
		if l < 3:
			_px(img, x, y, ramp[l + 1])
			_px(img, x + 1, y - 1, ramp[l + 1])
		_px(img, x, y + 1, ramp[l - 1])
		_px(img, x + 1, y, ramp[l - 1])
	# 小花：白 / 淡黄 / 红，下方一点阴影
	var flowers := [Pal.c("frame_0"), Pal.c("light_0"), Pal.c("red_0"), Pal.c("frame_0")]
	for i in size * size / 640:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		_px(img, x, y, flowers[rng.randi_range(0, flowers.size() - 1)])
		_px(img, x, y + 1, ramp[1])
	img.flip_y()
	return img


## 土路 64px：成片的深浅土色 + 带阴影的小石子。
static func dirt(seed_value: int, size := 64) -> Image:
	var rng := _rng(seed_value)
	var n := fbm(size, 8, rng)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := n[y * size + x]
			var col := Pal.c("dirt_1")
			if v > 0.66:
				col = Pal.c("dirt_0")
			elif v < 0.3:
				col = Pal.c("dirt_2")
			img.set_pixel(x, y, col)
	for i in size * size / 110:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		var big := rng.randf() < 0.4
		_px(img, x, y, Pal.c("stone_0"))
		if big:
			_px(img, x + 1, y, Pal.c("stone_1"))
		_px(img, x, y + 1, Pal.c("dirt_2"))
		if big:
			_px(img, x + 1, y + 1, Pal.c("dirt_2"))
	img.flip_y()
	return img


## 石板路 48px（3 米一循环）：成排的圆角石块（5 像素高），顶行高光、底行阴影，
## 少量偏蓝的石头增加变化。不用暖色石块——在灰色路面上会变成扎眼的橙点。
static func cobbles(seed_value: int, size := 48) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Pal.c("stone_2"))  # 石缝
	# 每种石头 = [高光, 本色, 阴影]
	var tones := [
		[Pal.c("snow_3"), Pal.c("stone_0"), Pal.c("stone_1")],
		[Pal.c("stone_0"), Pal.c("stone_1"), Pal.c("stone_1")],
		[Pal.c("stone_0"), Pal.c("roof_0"), Pal.c("roof_1")],
	]
	var row_h := 6
	for row in range(size / row_h):
		var x := rng.randi_range(0, 9)
		var remaining := size
		while remaining > 0:
			var w := rng.randi_range(6, 10)
			if remaining - w < 6:
				w = remaining
			remaining -= w
			var r := rng.randf()
			var t: Array = tones[0 if r < 0.5 else (1 if r < 0.88 else 2)]
			for ly in row_h - 1:
				for lx in w - 1:
					var corner := (lx == 0 or lx == w - 2) and (ly == 0 or ly == row_h - 2)
					if corner:
						continue
					var col: Color = t[1]
					if ly == 0 and lx > 0 and lx < w - 3:
						col = t[0]
					elif ly == row_h - 2:
						col = t[2]
					_px(img, x + lx, row * row_h + ly, col)
			x += w
	img.flip_y()
	return img


## 针叶：cols = [底, 亮, 暗]。droop=false：顶盖上的「^」形针叶簇；droop=true：裙边上下垂的针叶。
static func needles(cols: Array, seed_value: int, droop: bool, size := 32) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Pal.c(cols[0]))
	var hi := Pal.c(cols[1])
	var sh := Pal.c(cols[2])
	for gy in range(0, size, 4):
		for gx in range(0, size, 5):
			var x := gx + (gy / 4 % 2) * 2 + rng.randi_range(-1, 1)
			var y := gy + rng.randi_range(0, 1)
			if droop:
				_px(img, x, y, hi)
				_px(img, x, y + 1, hi)
				_px(img, x + 1, y + 2, sh)
				_px(img, x, y + 2, sh)
			else:
				_px(img, x, y, hi)
				_px(img, x - 1, y + 1, hi)
				_px(img, x + 1, y + 1, hi)
				_px(img, x, y + 2, sh)
	return img


## 阔叶：cols = [底, 亮, 暗]。成片暗部 + 一簇簇亮叶，每簇下方一点阴影。
static func leaves(cols: Array, seed_value: int, size := 32) -> Image:
	var rng := _rng(seed_value)
	var n := tile_noise(size, 4, rng)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var base := Pal.c(cols[0])
	var hi := Pal.c(cols[1])
	var sh := Pal.c(cols[2])
	for y in size:
		for x in size:
			img.set_pixel(x, y, sh if n[y * size + x] < 0.32 else base)
	for i in size * size / 18:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		_px(img, x, y, hi)
		_px(img, x + 1, y, hi)
		_px(img, x, y - 1, hi)
		_px(img, x, y + 1, sh)
		_px(img, x + 1, y + 1, sh)
	return img


## 窗户 16x20：白框十字窗格 + 深色玻璃。emit=true 时输出发光遮罩（玻璃=白）。
static func window(emit: bool) -> Image:
	var w := 16
	var h := 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var frame := x < 2 or x >= w - 2 or y < 2 or y >= h - 2 or x == 7 or x == 8 or y == 9 or y == 10
			var col: Color
			if emit:
				col = Color.BLACK if frame else Color.WHITE
			elif frame:
				col = Pal.c("frame_0") if y < h - 2 else Pal.c("frame_1")
			else:
				# 左上角一道斜高光
				var hl := (x + y) % 9 == 0 and x < 7 and y < 9
				col = Pal.c("window_1") if hl else Pal.c("window_0")
			img.set_pixel(x, y, col)
	return img


## 门 20x32：白框 + 竖木板 + 门把手
static func door() -> Image:
	var w := 20
	var h := 32
	var rng := _rng(901)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var shades := []
	for i in 6:
		shades.append(Pal.c(["wood_1", "wood_2"][rng.randi_range(0, 1)]))
	for y in h:
		for x in w:
			var col: Color
			if x < 2 or x >= w - 2 or y < 2:
				col = Pal.c("frame_0")
			elif (x - 2) % 4 == 0:
				col = Pal.c("wood_3")
			else:
				col = shades[(x - 2) / 4]
			if x == 14 and y == 17:
				col = Pal.c("light_1")
			img.set_pixel(x, y, col)
	return img
