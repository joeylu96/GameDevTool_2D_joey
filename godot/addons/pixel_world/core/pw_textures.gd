@tool
extends RefCounted
## 程序化像素贴图。全部只用调色板颜色，按 16 texel/米 设计（32px 贴图 = 2 米一循环）。
## 用于占位资产；Blender 资产到位后可替换，但风格规则相同。

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
			img = shingles(["roof_0", "roof_1", "roof_2"], 201)
		"roof_red":
			img = shingles(["red_1", "red_2", "red_3"], 202)
		"trim":
			img = speckle(["frame_0", "frame_1"], 16, 301, 0.08, 0.0)
		"stone":
			img = bricks(["stone_0", "stone_1", "stone_2", "stone_3"], 401, 8)
		"brick":
			img = bricks(["red_1", "red_2", "red_2", "red_3"], 402, 6)
		"pine":
			img = speckle(["pine_1", "pine_0", "pine_2"], 32, 501, 0.08, 0.1)
		"trunk":
			img = planks(["wood_1", "wood_2", "wood_2", "wood_3"], 502, 16, 3)
		"metal":
			img = speckle(["stone_3", "stone_2", "ink"], 16, 601, 0.15, 0.1)
		"lamp_glass":
			img = speckle(["light_0", "light_1", "frame_0"], 16, 602, 0.2, 0.0)
		"grass":
			img = speckle(["grass_1", "grass_0", "grass_2"], 32, 701, 0.12, 0.16)
		"dirt":
			img = speckle(["dirt_1", "dirt_0", "dirt_2"], 32, 702, 0.15, 0.15)
		"earth":
			img = bricks(["dirt_1", "dirt_2", "stone_2", "dirt_2"], 703, 10)
		"cobble":
			img = cobbles(["stone_0", "stone_1", "dirt_1", "stone_2"], 801)
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


## 竖向木板墙：cols = [亮, 次亮, 缝, 最暗]
static func planks(cols: Array, seed_value: int, size := 32, plank_w := 4) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for px in range(0, size, plank_w):
		var shade := Pal.c(cols[rng.randi_range(0, 1)])
		var seam := rng.randi_range(0, size - 1)
		for x in range(px, min(px + plank_w, size)):
			for y in size:
				var col := shade
				if x == px:
					col = Pal.c(cols[2])
				elif y == seam:
					col = Pal.c(cols[2])
				elif rng.randf() < 0.03:
					col = Pal.c(cols[3])
				img.set_pixel(x, y, col)
	return img


## 瓦片屋顶：横排交错，cols = [亮, 次亮, 暗缝]
static func shingles(cols: Array, seed_value: int, size := 32) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var row_h := 4
	var sw := 8
	for row in range(size / row_h):
		var offset := (row % 2) * (sw / 2)
		var shades := []
		for i in range(size / sw + 1):
			shades.append(Pal.c(cols[rng.randi_range(0, 1)]))
		for y in range(row * row_h, row * row_h + row_h):
			for x in size:
				var xi := x + offset
				var col: Color = shades[(xi / sw) % shades.size()]
				if y == row * row_h + row_h - 1 or xi % sw == 0:
					col = Pal.c(cols[2])
				img.set_pixel(x, y, col)
	return img


## 砖/石块：cols = [亮, 次亮, 暗, 灰缝]
static func bricks(cols: Array, seed_value: int, brick_w := 8, size := 32) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var row_h := 4
	for row in range(size / row_h):
		var offset := (row % 2) * (brick_w / 2)
		var shades := []
		for i in range(size / brick_w + 1):
			shades.append(Pal.c(cols[rng.randi_range(0, 2)]))
		for y in range(row * row_h, row * row_h + row_h):
			for x in size:
				var xi := x + offset
				var col: Color = shades[(xi / brick_w) % shades.size()]
				if y == row * row_h or xi % brick_w == 0:
					col = Pal.c(cols[3])
				img.set_pixel(x, y, col)
	return img


## 底色 + 随机杂点：cols = [底, 点1, 点2]
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


## 石板路：可平铺的 Voronoi 石块，cols = [石1, 石2, 石3, 缝]
static func cobbles(cols: Array, seed_value: int, size := 32) -> Image:
	var rng := _rng(seed_value)
	var pts: Array[Vector2] = []
	var shades: Array[Color] = []
	for i in 14:
		pts.append(Vector2(rng.randf() * size, rng.randf() * size))
		shades.append(Pal.c(cols[rng.randi_range(0, 2)]))
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var d1 := INF
			var d2 := INF
			var idx := 0
			for i in pts.size():
				var dv := (p - pts[i]).abs()
				dv.x = min(dv.x, size - dv.x)  # 环绕距离，保证无缝平铺
				dv.y = min(dv.y, size - dv.y)
				var d := dv.length()
				if d < d1:
					d2 = d1
					d1 = d
					idx = i
				elif d < d2:
					d2 = d
			img.set_pixel(x, y, Pal.c(cols[3]) if d2 - d1 < 1.1 else shades[idx])
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
