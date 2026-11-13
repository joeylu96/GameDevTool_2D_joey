@tool
extends RefCounted
## 程序化贴图，32 texel/米（64px 贴图 = 2 米一循环）。只用调色板颜色及其之间的混合色。
## 规则：
##   1. 大面积用成片色块（可平铺值噪声）和多级明暗过渡，不用逐像素随机杂点；
##   2. 细节用成簇的小笔触（草叶、针叶、石子、木纹），每个笔触有亮面和阴影；
##   3. 结构线（木板缝、瓦缝、石缝）1 像素宽，旁边 1 像素高光，体积感更细腻；
##   4. 地面类贴图（顶面）生成后 flip_y：俯视镜头里贴图 +v 指向远处，翻转后「阴影在下」才正确；
##   5. 生成 mipmap：远处平滑不闪烁，近处最近邻保持清晰。
## 键名 "flat_<调色板色名>" 返回纯色贴图（人物五官等小部件用）。

const Pal := preload("res://addons/pixel_world/core/pw_palette.gd")

static var _cache := {}


static func get_tex(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var img := _make(key)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _make(key: String) -> Image:
	if key.begins_with("flat_"):
		var flat := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		flat.fill(Pal.c(key.substr(5)))
		return flat
	match key:
		# 墙面 / 木作
		"wall_red":
			return planks(["red_0", "red_1", "red_2", "red_3"], 101)
		"wall_ochre":
			return planks(["ochre_0", "ochre_1", "ochre_2", "ochre_3"], 102)
		"wall_teal":
			return planks(["teal_0", "teal_1", "teal_2", "teal_3"], 103)
		"wall_wood":
			return planks(["wood_0", "wood_1", "wood_2", "wood_3"], 104)
		"door_wood":
			return planks(["wood_0", "wood_1", "wood_2", "wood_3"], 111, 64, 6)
		"door_red":
			return planks(["red_0", "red_1", "red_2", "red_3"], 112, 64, 6)
		"door_teal":
			return planks(["teal_0", "teal_1", "teal_2", "teal_3"], 113, 64, 6)
		"door_green":
			return planks_c([Pal.mix("cloth_green", "grass_0", 0.35), Pal.c("cloth_green"),
				Pal.mix("cloth_green", "pine_2", 0.5), Pal.c("pine_3")], 114, 64, 6)
		"trim":
			return mottle(["frame_0", "frame_1"], 32, 301, 0.6)
		"trunk":
			return bark(505)
		"deck":
			return grain(["wood_0", "wood_1", "wood_2"], 1004)
		"birch_bark":
			return birch(509)
		"crate":
			return _rot(planks(["ochre_1", "ochre_2", "ochre_3", "wood_3"], 1001, 32, 8))
		"boards":
			return _rot(planks(["wood_0", "wood_1", "wood_2", "wood_3"], 1002, 32, 6))
		"barrel":
			return planks(["wood_0", "wood_1", "wood_2", "wood_3"], 1003, 32, 6)
		# 屋顶
		"roof_grey":
			return shingles(["stone_0", "roof_0", "roof_1", "roof_2"], 201)
		"roof_red":
			return shingles(["red_0", "red_1", "red_2", "red_3"], 202)
		"roof_cap":
			return mottle(["roof_2", "roof_1"], 32, 203, 0.55)
		# 石作
		"stone":
			return bricks(["stone_0", "stone_1", "stone_2", "stone_3"], 401, 16)
		"brick":
			return bricks(["red_1", "red_2", "red_2", "red_3"], 402, 12)
		"curb":
			return bricks(["snow_3", "stone_0", "stone_0", "stone_2"], 403, 32)
		"earth":
			return bricks(["dirt_1", "dirt_2", "stone_2", "dirt_2"], 703, 20)
		"rock":
			return blotches(["stone_1", "stone_0", "stone_2"], 64, 506)
		"rock_red":  # 峡谷 / 沙漠的红岩
			return blotches(["ochre_1", "red_1", "ochre_2"], 64, 509)
		"plaster_white":
			return mottle(["frame_0", "frame_1"], 32, 1101, 0.62)
		"plaster_red":
			return mottle(["red_0", "red_1"], 32, 1102, 0.6)
		# 金属 / 玻璃
		"metal":
			return mottle(["stone_3", "ink"], 32, 601, 0.6)
		"metal_green":
			return mottle([Pal.mix("pine_3", "teal_3", 0.5), Pal.c("pine_3")], 32, 605, 0.6)
		"metal_red":
			return mottle([Pal.c("red_3"), Pal.mix("red_3", "ink", 0.5)], 32, 606, 0.6)
		"brass":
			return mottle(["light_1", "light_2"], 16, 602, 0.6)
		"lamp_glass":
			return mottle(["light_0", "light_1"], 16, 603, 0.55)
		"glass":
			return glass(604)
		# 植物
		"pine":
			return needles(["pine_1", "pine_0", "pine_2"], 501, false)
		"pine_skirt":
			return needles(["pine_2", "pine_1", "pine_3"], 502, true)
		"leaf":
			return leaves(["grass_1", "grass_0", "grass_2"], 503)
		"leaf_dark":
			return leaves(["grass_2", "grass_1", "pine_1"], 504)
		"leaf_birch":
			return leaves([Pal.mix("grass_0", "cloth_yellow", 0.15), Pal.mix("grass_0", "light_0", 0.35), Pal.c("grass_1")], 510)
		"leaf_birch_dark":
			return leaves([Pal.c("grass_1"), Pal.c("grass_0"), Pal.c("grass_2")], 511)
		"flowers":
			return flowers(507)
		"weed":
			return weed(508)
		# 地面
		"grass":
			return grass(701)
		"dirt":
			return dirt(702)
		"shore":
			return dirt(704, 96, 30)
		"cobble":
			return cobbles(801)
		"sand":
			return sand(705)
		"lakebed":
			return lakebed(706)
		# 生物 / 人物
		"fish_orange":
			return fish(["light_2", "ochre_0", "red_1"], 901)
		"fish_silver":
			return fish(["stone_2", "snow_3", "stone_3"], 902)
		"cloth_red":
			return knit(["red_0", "red_1"], 1201, false)
		"cloth_blue":
			return knit([Pal.c("cloth_blue"), Pal.mix("cloth_blue", "window_0", 0.4)], 1202, false)
		"cloth_dark":
			return knit(["stone_2", "stone_3"], 1203, false)
		"knit":
			return knit(["cloth_yellow", "ochre_1"], 1204, true)
		"skin":
			return mottle(["skin_0", "skin_1"], 16, 1205, 0.7)
		"hair":
			return _rot(planks(["wood_0", "wood_1", "wood_2", "wood_3"], 1206, 16, 2))
		"boots":
			return mottle(["wood_3", "ink"], 16, 1207, 0.6)
		"hay":
			return _rot(bark_cols([Pal.mix("ochre_0", "light_0", 0.3), Pal.c("ochre_0"), Pal.c("ochre_1")], 1301))
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	return img


# ---------------------------------------------------------------- 工具

static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


static func _cols(names: Array) -> Array[Color]:
	var out: Array[Color] = []
	for n in names:
		out.append(n if n is Color else Pal.c(n))
	return out


static func _rot(img: Image) -> Image:
	img.rotate_90(CLOCKWISE)
	return img


## 环绕写像素（保证贴图无缝平铺）
static func _px(img: Image, x: int, y: int, col: Color) -> void:
	img.set_pixel(posmod(x, img.get_width()), posmod(y, img.get_height()), col)


## 环绕读像素
static func _pix(img: Image, x: int, y: int) -> Color:
	return img.get_pixel(posmod(x, img.get_width()), posmod(y, img.get_height()))


## 1D 平滑值噪声（木纹等）
static func _n1(x: float, s: float) -> float:
	var i := floorf(x)
	var f := x - i
	f = f * f * (3.0 - 2.0 * f)
	var a := fposmod(sin(i * 12.9898 + s * 78.233) * 43758.5453, 1.0)
	var b := fposmod(sin((i + 1.0) * 12.9898 + s * 78.233) * 43758.5453, 1.0)
	return lerpf(a, b, f)


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


# ---------------------------------------------------------------- 木作

static func planks(names: Array, seed_value: int, size := 64, plank_w := 8) -> Image:
	return planks_c(_cols(names), seed_value, size, plank_w)


## 竖向木板：cols = [亮, 主色, 暗, 缝]。每块板色调略有不同；左侧 1 像素高光、右侧 1 像素暗边；
## 沿板长方向的细木纹、偶尔的横向接缝（带两颗钉子）和木节。
static func planks_c(cols: Array, seed_value: int, size := 64, plank_w := 8) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mot := tile_noise(size, 4, rng)
	for px in range(0, size, plank_w):
		var shade: Color = (cols[0] as Color).lerp(cols[1], rng.randf_range(0.35, 1.0))
		var joint := rng.randi_range(0, size - 1) if rng.randf() < 0.65 else -100
		for x in range(px, mini(px + plank_w, size)):
			var lx := x - px
			var gs := rng.randf() * 100.0
			for y in size:
				var col := shade.lerp(cols[2], (mot[y * size + x] - 0.5) * 0.35)
				var g := _n1(y * 0.11, gs)
				if g > 0.74:
					col = col.lerp(cols[2], 0.4)
				elif g < 0.1:
					col = col.lerp(cols[0], 0.3)
				if lx == 0:
					col = cols[3]
				elif lx == 1:
					col = col.lerp(cols[0], 0.5)
				elif lx == plank_w - 1:
					col = col.lerp(cols[2], 0.4)
				var dy := posmod(y - joint, size)
				if dy == 0 and lx > 0:
					col = cols[3]
				elif dy == 1 and lx > 0:
					col = col.lerp(cols[0], 0.4)
				elif (dy == 3 or dy == size - 2) and (lx == 2 or lx == plank_w - 2) and joint >= 0:
					col = cols[3].lerp(cols[2], 0.3)  # 钉子
				img.set_pixel(x, y, col)
		# 木节
		if rng.randf() < 0.3 and plank_w >= 6:
			var kx := px + rng.randi_range(2, plank_w - 3)
			var ky := rng.randi_range(0, size - 1)
			for oy in range(-2, 3):
				for ox in range(-1, 2):
					var ring := absi(oy) == 2 or absi(ox) == 1
					var cur := _pix(img, kx + ox, ky + oy)
					_px(img, kx + ox, ky + oy, cur.lerp(cols[2], 0.45) if ring else (cols[3] as Color).lerp(cols[2], 0.5))
	return img


## 顺纹木（甲板）：只有沿 x 方向的低对比木纹，没有板缝——板缝由几何缝隙表现，
## 避免长条甲板上密集的高对比条纹（看着眼花、产生摩尔纹）。
static func grain(names: Array, seed_value: int, size := 64) -> Image:
	var cols := _cols(names)
	var rng := _rng(seed_value)
	var mot := tile_noise(size, 4, rng)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var s := rng.randf() * 100.0
		for x in size:
			var col := cols[1].lerp(cols[0], mot[y * size + x] * 0.45)
			var g := _n1(x * 0.08, s)
			if g > 0.78:
				col = col.lerp(cols[2], 0.28)
			elif g < 0.1:
				col = col.lerp(cols[0], 0.2)
			img.set_pixel(x, y, col)
	return img


## 白桦树皮 64px（2 米一循环）：象牙白底 + 淡灰的竖向明暗 + 长短不一的横向皮孔（中间黑、两端灰、
## 上方一道浅高光）+ 少量大块深色疤痕（枝条脱落处）。皮孔是成簇的，不是满屏均匀的小短线。
static func birch(seed_value: int, size := 64) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n := fbm(size, 4, rng)
	var white := Pal.c("frame_0")
	var shade := Pal.mix("frame_1", "snow_3", 0.5)
	for y in size:
		for x in size:
			var v := n[y * size + x]
			var col := white
			if v < 0.38:
				col = white.lerp(shade, 0.6)
			elif v < 0.5:
				col = white.lerp(shade, 0.25)
			img.set_pixel(x, y, col)
	var ink := Pal.c("ink")
	var grey := Pal.c("stone_2")
	var hi := Pal.c("snow_0")
	# 皮孔：成簇出现，每簇 2~4 条，上下相隔 2~4 像素
	for c in 9:
		var cx := rng.randi_range(0, size - 1)
		var cy := rng.randi_range(0, size - 1)
		for k in rng.randi_range(2, 4):
			var w := rng.randi_range(4, 13)
			var x0 := cx + rng.randi_range(-4, 4)
			var y0 := cy + k * rng.randi_range(2, 4)
			for dx in w:
				var edge := dx < 1 or dx >= w - 1
				_px(img, x0 + dx, y0, grey if edge else ink)
				_px(img, x0 + dx, y0 - 1, hi)
				if not edge and w > 8 and dx > 2 and dx < w - 3:
					_px(img, x0 + dx, y0 + 1, grey)
	# 疤痕：深色三角 / 菱形块
	for i in 3:
		var sx := rng.randi_range(0, size - 1)
		var sy := rng.randi_range(0, size - 1)
		for dy in 5:
			var half := 3 - absi(dy - 2)
			for dx in range(-half, half + 1):
				_px(img, sx + dx, sy + dy, ink if absi(dx) < half else grey)
	return img


## 树皮：竖向深沟 + 亮脊
static func bark(seed_value: int, size := 32) -> Image:
	return bark_cols(_cols(["wood_1", "wood_2", "wood_3"]), seed_value, size)


## 竖向纤维纹理：cols = [亮, 主, 暗]（树皮、干草）
static func bark_cols(cols: Array, seed_value: int, size := 32) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for x in size:
		var s := rng.randf() * 50.0
		for y in size:
			var v := _n1(y * 0.18, s) * 0.6 + _n1(x * 0.7, 3.0) * 0.4
			var col: Color = cols[1]
			if v > 0.62:
				col = cols[0]
			elif v < 0.32:
				col = cols[2]
			img.set_pixel(x, y, col)
	return img


# ---------------------------------------------------------------- 屋顶 / 石作

## 瓦片屋顶（贴图 +v = 顺坡向下）：cols = [瓦唇高光, 主色A(亮), 主色B(暗), 缝]。
## 每排 8 像素：顶部是上一排投下的阴影，往下渐亮，底边一道瓦唇高光，下沿两角圆润。
static func shingles(names: Array, seed_value: int, size := 64) -> Image:
	var cols := _cols(names)
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mot := tile_noise(size, 4, rng)
	var row_h := 8
	var sw := 16
	for row in range(size / row_h):
		var offset := (row % 2) * (sw / 2) + rng.randi_range(-2, 2)
		var tiles: Array[Color] = []
		for i in range(size / sw + 1):
			var t := rng.randf() * 0.45 if rng.randf() < 0.88 else rng.randf_range(0.75, 1.0)
			tiles.append(cols[1].lerp(cols[2], t))
		for ly in row_h:
			var y := row * row_h + ly
			for x in size:
				var xi := posmod(x + offset, size)
				var lx := xi % sw
				var base: Color = tiles[(xi / sw) % tiles.size()]
				base = base.lerp(cols[3], (mot[y * size + x] - 0.5) * 0.25)
				var col := base
				if ly == 0:
					col = cols[3]
				elif ly == 1:
					col = base.lerp(cols[3], 0.4)
				elif ly == row_h - 1:
					col = base.lerp(cols[0], 0.45)
				else:
					col = base.lerp(cols[0], float(ly - 2) / row_h * 0.25)
				if lx == 0 and ly < row_h - 1:
					col = cols[3]
				elif lx == 1 and ly > 0 and ly < row_h - 1:
					col = col.lerp(cols[0], 0.2)
				if ly == row_h - 1 and (lx == 0 or lx == sw - 1):
					col = cols[3]
				img.set_pixel(x, y, col)
	return img


## 砖 / 石块：cols = [亮, 主色, 暗, 灰缝]。每块色调连续变化；顶行和左列高光、底行和右列暗边；少量缺口。
static func bricks(names: Array, seed_value: int, brick_w := 16, size := 64, row_h := 8) -> Image:
	var cols := _cols(names)
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mot := tile_noise(size, 8, rng)
	for row in range(size / row_h):
		var offset := (row % 2) * (brick_w / 2)
		var shades: Array[Color] = []
		for i in range(size / brick_w + 1):
			shades.append(cols[0].lerp(cols[2], rng.randf_range(0.2, 0.9)))
		for ly in row_h:
			var y := row * row_h + ly
			for x in size:
				var xi := x + offset
				var lx := xi % brick_w
				var base: Color = shades[(xi / brick_w) % shades.size()]
				base = base.lerp(cols[2], (mot[y * size + x] - 0.5) * 0.3)
				var col := base
				if ly == 0 or lx == 0:
					col = cols[3]
				elif ly == 1:
					col = base.lerp(cols[0], 0.45)
				elif lx == 1:
					col = base.lerp(cols[0], 0.25)
				elif ly == row_h - 1:
					col = base.lerp(cols[3], 0.35)
				elif lx == brick_w - 1:
					col = base.lerp(cols[3], 0.25)
				img.set_pixel(x, y, col)
	for i in size * size / 90:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		_px(img, x, y, _pix(img, x, y).lerp(cols[3], 0.45))
	return img


## 低频斑驳：cols = [底色, 斑色]，amount 控制斑块多少（阈值）。用于封檐板、灰泥、金属、皮肤等。
static func mottle(names: Array, size: int, seed_value: int, threshold := 0.6) -> Image:
	var cols := _cols(names)
	var rng := _rng(seed_value)
	var n := fbm(size, maxi(2, size / 8), rng)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := n[y * size + x]
			var col := cols[0]
			if v > threshold + 0.06:
				col = cols[1]
			elif v > threshold:
				col = cols[0].lerp(cols[1], 0.5)
			img.set_pixel(x, y, col)
	return img


## 石头：三色成片斑块 + 中间过渡色
static func blotches(names: Array, size: int, seed_value: int) -> Image:
	var cols := _cols(names)
	var rng := _rng(seed_value)
	var n := fbm(size, 6, rng)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := n[y * size + x]
			var col := cols[0]
			if v > 0.64:
				col = cols[1]
			elif v > 0.58:
				col = cols[0].lerp(cols[1], 0.5)
			elif v < 0.32:
				col = cols[2]
			elif v < 0.38:
				col = cols[0].lerp(cols[2], 0.5)
			img.set_pixel(x, y, col)
	return img


## 窗玻璃：上亮下暗的渐变 + 两道斜向反光
static func glass(seed_value: int, size := 32) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c0 := Pal.c("window_0")
	var c1 := Pal.c("window_1")
	var hl := Pal.mix("window_1", "snow_2", 0.45)
	for y in size:
		for x in size:
			var col := c1.lerp(c0, clampf(float(y) / size * 1.4, 0.0, 1.0))
			var d := posmod(x + y, size)
			if d >= 6 and d < 9:
				col = hl
			elif d == 11:
				col = col.lerp(hl, 0.6)
			img.set_pixel(x, y, col)
	return img


# ---------------------------------------------------------------- 地面

## 草地 128px（4 米一循环）：五级明暗的成片色块 + 大量细草叶（尖端亮、根部暗）+ 零星小花。
static func grass(seed_value: int, size := 128) -> Image:
	var rng := _rng(seed_value)
	var n := fbm(size, 8, rng)
	var ramp: Array[Color] = [Pal.c("pine_1"), Pal.mix("pine_1", "grass_2", 0.5), Pal.c("grass_2"),
		Pal.mix("grass_2", "grass_1", 0.5), Pal.c("grass_1"), Pal.mix("grass_1", "grass_0", 0.5), Pal.c("grass_0")]
	var level := PackedInt32Array()
	level.resize(size * size)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var l := clampi(int((n[y * size + x] - 0.22) / 0.56 * 4.0) + 1, 1, 5)
			level[y * size + x] = l
			img.set_pixel(x, y, ramp[l])
	# 草叶：2~3 像素高的竖线，尖端亮一级、根部暗一级，偶尔向一侧倾斜
	for i in size * size / 7:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		var l := level[y * size + x]
		var lean := rng.randi_range(-1, 1) if rng.randf() < 0.3 else 0
		_px(img, x, y, ramp[l - 1])
		_px(img, x, y - 1, ramp[mini(l + 1, 6)])
		if rng.randf() < 0.5:
			_px(img, x + lean, y - 2, ramp[mini(l + 1, 6)])
	# 小花：十字形花瓣 + 花心，下方一点阴影
	var petals := [Pal.c("frame_0"), Pal.c("light_0"), Pal.c("red_0"), Pal.c("cloth_yellow"), Pal.c("snow_1")]
	for i in size * size / 520:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		var pc: Color = petals[rng.randi_range(0, petals.size() - 1)]
		_px(img, x, y, Pal.c("light_1"))
		_px(img, x - 1, y, pc)
		_px(img, x + 1, y, pc)
		_px(img, x, y - 1, pc)
		_px(img, x, y + 1, pc.lerp(ramp[1], 0.5))
		_px(img, x, y + 2, ramp[1])
	img.flip_y()
	return img


## 土路：成片的五级土色 + 带高光和阴影的小石子 + 零星草芽。pebble_div 越小石子越多。
static func dirt(seed_value: int, size := 128, pebble_div := 140) -> Image:
	var rng := _rng(seed_value)
	var n := fbm(size, 8, rng)
	var ramp: Array[Color] = [Pal.c("dirt_2"), Pal.mix("dirt_2", "dirt_1", 0.5), Pal.c("dirt_1"),
		Pal.mix("dirt_1", "dirt_0", 0.5), Pal.c("dirt_0")]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, ramp[clampi(int((n[y * size + x] - 0.2) / 0.6 * 5.0), 0, 4)])
	for i in size * size / pebble_div:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		var w := rng.randi_range(2, 3)
		var hl := Pal.mix("stone_0", "frame_1", rng.randf() * 0.5)
		for dx in w:
			_px(img, x + dx, y, hl if dx == 0 else Pal.c("stone_0"))
			_px(img, x + dx, y + 1, Pal.c("stone_1"))
			_px(img, x + dx, y + 2, ramp[0])
	for i in size * size / 900:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		_px(img, x, y, Pal.c("grass_1"))
		_px(img, x + 1, y - 1, Pal.c("grass_0"))
		_px(img, x, y + 1, Pal.c("grass_2"))
	img.flip_y()
	return img


## 石板路 96px（3 米一循环）：成排的圆角石块（9 像素高），从上到下由亮到暗，左亮右暗，
## 每块色调和斑驳都不同；少量偏蓝 / 偏暖的石头增加变化。
static func cobbles(seed_value: int, size := 96) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mortar := Pal.mix("stone_2", "stone_3", 0.5)
	img.fill(mortar)
	var mot := tile_noise(size, 12, rng)
	var tones := [
		[Pal.c("snow_3"), Pal.c("stone_0"), Pal.c("stone_1")],
		[Pal.c("stone_0"), Pal.c("stone_1"), Pal.c("stone_2")],
		[Pal.c("stone_0"), Pal.c("roof_0"), Pal.c("roof_1")],
		[Pal.c("frame_1"), Pal.mix("stone_0", "dirt_0", 0.45), Pal.c("stone_1")],
	]
	var row_h := 10
	for row in range(size / row_h + 1):
		if row * row_h >= size:
			break
		var x := rng.randi_range(0, 15)
		var remaining := size
		while remaining > 0:
			var w := rng.randi_range(12, 18)
			if remaining - w < 12:
				w = remaining
			remaining -= w
			var r := rng.randf()
			var t: Array = tones[0 if r < 0.45 else (1 if r < 0.86 else (2 if r < 0.95 else 3))]
			var sh := rng.randf_range(-0.15, 0.15)
			var ih := row_h - 1
			for ly in ih:
				for lx in w - 1:
					var cx := mini(lx, w - 2 - lx)
					var cy := mini(ly, ih - 1 - ly)
					if cx + cy < 2:
						continue  # 圆角
					var v := float(ly) / (ih - 1) + sh
					var col: Color
					if v < 0.25:
						col = (t[0] as Color).lerp(t[1], v / 0.25)
					else:
						col = (t[1] as Color).lerp(t[2], clampf((v - 0.25) / 0.75, 0.0, 1.0) * 0.85)
					if lx == 0 or (lx == 1 and cy < 2):
						col = col.lerp(t[0], 0.4)
					elif lx == w - 2:
						col = col.lerp(t[2], 0.5)
					var yy := row * row_h + ly
					col = col.lerp(t[2], (mot[posmod(yy, size) * size + posmod(x + lx, size)] - 0.5) * 0.35)
					_px(img, x + lx, yy, col)
			x += w
	img.flip_y()
	return img


## 湖边浅滩的沙：浅暖色 + 平行的沙纹 + 小石子和贝壳
static func sand(seed_value: int, size := 96) -> Image:
	var rng := _rng(seed_value)
	var n := fbm(size, 6, rng)
	var c0 := Pal.mix("dirt_0", "frame_1", 0.5)
	var c1 := Pal.c("dirt_0")
	var c2 := Pal.mix("dirt_0", "dirt_1", 0.6)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := n[y * size + x]
			var col := c1
			if v > 0.6:
				col = c0
			# 沙纹：被噪声扭曲的弯曲条纹，低对比
			var ripple := sin((y * 0.9 + x * 0.3 + v * 22.0) * TAU / 10.0)
			if ripple > 0.9:
				col = col.lerp(c2, 0.35)
			elif ripple < -0.94:
				col = col.lerp(c0, 0.25)
			img.set_pixel(x, y, col)
	for i in size * size / 160:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		var pc := Pal.c("stone_0") if rng.randf() < 0.75 else Pal.c("snow_1")
		_px(img, x, y, pc)
		_px(img, x + 1, y, pc.lerp(Pal.c("stone_1"), 0.5))
		_px(img, x, y + 1, c2)
	img.flip_y()
	return img


## 深一些的湖底：泥色 + 卵石 + 深色水草斑块
static func lakebed(seed_value: int, size := 96) -> Image:
	var rng := _rng(seed_value)
	var n := fbm(size, 6, rng)
	var c0 := Pal.mix("dirt_1", "teal_2", 0.35)
	var c1 := Pal.mix("dirt_2", "teal_3", 0.4)
	var c2 := Pal.mix("pine_2", "teal_3", 0.5)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := n[y * size + x]
			var col := c1
			if v > 0.6:
				col = c0
			elif v < 0.3:
				col = c2
			img.set_pixel(x, y, col)
	for i in size * size / 120:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		_px(img, x, y, Pal.c("stone_1"))
		_px(img, x + 1, y, Pal.c("stone_2"))
		_px(img, x, y + 1, Pal.c("stone_3"))
	img.flip_y()
	return img


# ---------------------------------------------------------------- 植物

## 针叶：cols = [底, 亮, 暗]。droop=false：顶盖上的「^」形针叶簇；droop=true：裙边上下垂的针叶。
static func needles(names: Array, seed_value: int, droop: bool, size := 64) -> Image:
	var cols := _cols(names)
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n := tile_noise(size, 6, rng)
	for y in size:
		for x in size:
			img.set_pixel(x, y, cols[2].lerp(cols[0], 0.5) if n[y * size + x] < 0.3 else cols[0])
	var hi := cols[1]
	var mid := cols[0].lerp(cols[1], 0.5)
	var sh := cols[2]
	for gy in range(0, size, 5):
		for gx in range(0, size, 6):
			var x := gx + (gy / 5 % 2) * 3 + rng.randi_range(-1, 1)
			var y := gy + rng.randi_range(0, 1)
			if droop:
				_px(img, x, y, hi)
				_px(img, x, y + 1, hi)
				_px(img, x, y + 2, mid)
				_px(img, x, y + 3, sh)
				_px(img, x + 1, y + 1, mid)
				_px(img, x + 1, y + 3, sh)
			else:
				_px(img, x, y, hi)
				_px(img, x - 1, y + 1, hi)
				_px(img, x + 1, y + 1, hi)
				_px(img, x - 2, y + 2, mid)
				_px(img, x + 2, y + 2, mid)
				_px(img, x, y + 2, sh)
				_px(img, x, y + 3, sh)
	return img


## 阔叶：cols = [底, 亮, 暗]。成片暗部 + 一簇簇圆形叶团（左上亮、右下暗，顶端一点反光）。
static func leaves(names: Array, seed_value: int, size := 64) -> Image:
	var cols := _cols(names)
	var rng := _rng(seed_value)
	var n := tile_noise(size, 6, rng)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, cols[2] if n[y * size + x] < 0.32 else cols[0])
	var shine := cols[1].lerp(Pal.c("light_0"), 0.25)
	for i in size * size / 22:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		_px(img, x, y - 1, cols[1])
		_px(img, x + 1, y - 1, cols[1])
		_px(img, x - 1, y, cols[1])
		_px(img, x, y, shine if rng.randf() < 0.3 else cols[1])
		_px(img, x + 1, y, cols[0].lerp(cols[1], 0.5))
		_px(img, x + 2, y, cols[0])
		_px(img, x - 1, y + 1, cols[0])
		_px(img, x, y + 1, cols[0].lerp(cols[2], 0.5))
		_px(img, x + 1, y + 1, cols[2])
	return img


## 花箱里的花：深绿叶底 + 密集的小花（花瓣 + 花心）
static func flowers(seed_value: int, size := 32) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Pal.c("pine_1"))
	for i in size * size / 8:
		_px(img, rng.randi_range(0, size - 1), rng.randi_range(0, size - 1), Pal.c("grass_1"))
	var cols := [Pal.c("red_0"), Pal.c("light_0"), Pal.c("frame_0"), Pal.c("red_0"), Pal.c("cloth_yellow")]
	for i in size * size / 14:
		var x := rng.randi_range(0, size - 1)
		var y := rng.randi_range(0, size - 1)
		var pc: Color = cols[rng.randi_range(0, cols.size() - 1)]
		_px(img, x, y, pc)
		_px(img, x + 1, y, pc)
		_px(img, x, y + 1, pc.lerp(Pal.c("pine_2"), 0.4))
		_px(img, x + 1, y + 1, Pal.c("light_1"))
		_px(img, x, y + 2, Pal.c("pine_2"))
	return img


## 水草：竖向的深浅绿色叶片
static func weed(seed_value: int, size := 16) -> Image:
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for x in size:
		var col := Pal.mix("grass_2", "teal_1", rng.randf())
		for y in size:
			img.set_pixel(x, y, col.lerp(Pal.c("teal_3"), float(y) / size * 0.6))
	return img


# ---------------------------------------------------------------- 生物 / 人物

## 鱼：cols = [背, 腹, 斑]。鱼鳞小弧纹
static func fish(names: Array, seed_value: int, size := 16) -> Image:
	var cols := _cols(names)
	var rng := _rng(seed_value)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var col := cols[0].lerp(cols[1], float(y) / size)
			if (x + (y / 2) % 2 * 2) % 4 == 0 and y % 2 == 0:
				col = col.lerp(cols[2], 0.35)
			img.set_pixel(x, y, col)
	for i in 4:
		_px(img, rng.randi_range(0, size - 1), rng.randi_range(0, size / 2), cols[2])
	return img


## 针织 / 布料：cols = [主色, 暗色]。ribbed=true 时是竖向罗纹（毛线帽），否则是细密的斜纹
static func knit(names: Array, seed_value: int, ribbed: bool, size := 16) -> Image:
	var cols := _cols(names)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var col := cols[0]
			if ribbed:
				if x % 3 == 0:
					col = cols[1]
			elif (x + y) % 4 == 0:
				col = cols[0].lerp(cols[1], 0.5)
			img.set_pixel(x, y, col)
	return img
