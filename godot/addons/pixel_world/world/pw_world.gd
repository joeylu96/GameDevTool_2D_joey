@tool
class_name PWWorld
extends Node3D
## 场景生成器：按风格和种子生成场景，可在编辑器里生成并另存为 .tscn，也可在运行时生成。
##
## 风格（theme，见 PWStyles）：
##   town   — 海边小镇：BSP 道路网、朝路的房屋、路灯、篱笆、长椅、湖岸（灯塔 + 码头 + 土路）
##   forest — 森林：起伏林地、大湖和河、营地 / 木屋 / 废墟与林间小路
##   plains — 平原：开阔草原、花丛、大湖和河、树丛与灌木篱、农舍 / 风车
##   （雪原、海岛、沙漠、峡谷等在 PWStyles 里登记为「即将推出」）
## 所有物体经 PWPlacement 规则检查后才放置（见 pw_placement.gd），生成后再整体校验一次。
##
## 对外查询（角色、鱼群用）：ground_y(x, z)、water_depth(x, z)、can_stand(Vector2)、spawn_point

signal generated

const TownGen := preload("res://addons/pixel_world/world/pw_town_gen.gd")
const NatureGen := preload("res://addons/pixel_world/world/pw_nature_gen.gd")
const WATER_SHADER := preload("res://addons/pixel_world/shaders/water.gdshader")
## 水深贴图里 1.0 对应的深度（米）
const DEPTH_RANGE := 4.0

@export_enum("town", "forest", "plains", "snowfield", "island", "desert", "canyon") var theme := "town"
@export var seed_value := 7
## 场景边长（米）。设计规模：小镇约 64~80，野外约 128
@export_range(32, 192, 8) var size := 80
@export_range(0.0, 2.0, 0.05) var tree_density := 1.0
@export_range(0.0, 2.0, 0.05) var house_density := 1.0
@export_range(0.0, 2.0, 0.05) var bush_density := 1.0
@export_range(6.0, 20.0, 0.5) var lamp_spacing := 10.0
@export var with_lake := true
## 在编辑器里勾选即重新生成（按钮式属性）
@export var regenerate := false:
	set(v):
		if v and is_inside_tree():
			generate()
@export var generate_on_ready := true

## 生成结果
var placement: PWPlacement
var spawn_point := Vector3.ZERO
## NPC 的家：小镇是每栋房子门口，野外是营地 / 兴趣点旁。NPC 白天在附近闲逛、天黑回这里
var homes: Array[Vector3] = []
var fish: PWFishSchool
var water_y := -0.45
var violations := PackedStringArray()
## 每类物体的数量（生成后可查看）
var stats := {}

# 高度网格：(n+1)×(n+1) 个顶点，间距 cell，左下角 origin（世界 XZ）
var cell := 1.0
var grid_n := 0
var origin := Vector2.ZERO
var heights := PackedFloat32Array()
## true：地面高度取最近格（阶梯地形）；false：双线性插值（平地 + 缓坡湖岸）
var terraced := false
## 局部覆盖：[Rect2, y]（码头甲板等）
var overrides: Array = []
## 角色最多能涉多深的水
var wade_depth := 0.65
## 不可通行的网格顶点（悬崖边等），与 heights 同尺寸；空数组 = 没有
var walk_block := PackedByteArray()
## 水流方向（河道），与 heights 同尺寸；长度 = 流速 0..1。空数组 = 静水
var flow := PackedVector2Array()
var _content: Node3D


func _ready() -> void:
	if generate_on_ready and get_child_count() == 0:
		generate()


## 清空并重新生成
func generate() -> void:
	clear()
	homes.clear()
	var t0 := Time.get_ticks_msec()
	placement = PWPlacement.new()
	_content = Node3D.new()
	_content.name = "Generated"
	add_child(_content)
	if theme == "wild":
		theme = "forest"  # 旧名字兼容
	var style := PWStyles.get_style(theme)
	if not style.get("ready", false):
		push_warning("PWWorld: 风格 %s 还没有实现，改用小镇" % theme)
		style = PWStyles.get_style("town")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, theme, size])
	var batcher := PWBatcher.new()
	if style.generator == "nature":
		NatureGen.new(self, rng, batcher, style.params).run()
	else:
		TownGen.new(self, rng, batcher).run()
	batcher.flush(_content, theme.capitalize())
	_build_water()
	violations = placement.validate()
	if not violations.is_empty():
		push_warning("PWWorld: %d 处摆放违规，例如：%s" % [violations.size(), violations[0]])
		if OS.get_cmdline_user_args().has("--violations"):
			for v in violations:
				print("  VIOLATION ", v)
	print("PWWorld: %s seed=%d size=%d 生成完成，%d ms，%s，违规 %d，鱼群范围 %s" % [
		theme, seed_value, size, Time.get_ticks_msec() - t0, stats, violations.size(),
		fish.area if fish != null else "无"])
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		_set_owner_recursive(_content, get_tree().edited_scene_root)
	generated.emit()


func clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_content = null
	fish = null
	overrides.clear()
	walk_block = PackedByteArray()
	flow = PackedVector2Array()
	stats.clear()
	violations = PackedStringArray()


func content() -> Node3D:
	return _content


func _set_owner_recursive(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_set_owner_recursive(c, owner_node)
	n.owner = owner_node


# ---------------------------------------------------------------- 高度网格

func init_grid(half_size: float, margin: float, fill_y := 0.0) -> void:
	cell = 1.0
	origin = Vector2(-half_size - margin, -half_size - margin)
	grid_n = int(ceil((half_size + margin) * 2.0 / cell))
	heights = PackedFloat32Array()
	heights.resize((grid_n + 1) * (grid_n + 1))
	heights.fill(fill_y)


func set_h(i: int, j: int, y: float) -> void:
	heights[j * (grid_n + 1) + i] = y


func get_h(i: int, j: int) -> float:
	i = clampi(i, 0, grid_n)
	j = clampi(j, 0, grid_n)
	return heights[j * (grid_n + 1) + i]


## 顶点 (i, j) 的世界坐标 XZ
func vert_xz(i: int, j: int) -> Vector2:
	return origin + Vector2(i, j) * cell


func terrain_y(x: float, z: float) -> float:
	var g := (Vector2(x, z) - origin) / cell
	if terraced:
		return get_h(int(floor(g.x + 0.5)), int(floor(g.y + 0.5)))
	var i := int(floor(g.x))
	var j := int(floor(g.y))
	var fx := g.x - i
	var fz := g.y - j
	return lerpf(lerpf(get_h(i, j), get_h(i + 1, j), fx), lerpf(get_h(i, j + 1), get_h(i + 1, j + 1), fx), fz)


# ---------------------------------------------------------------- 查询

func ground_y(x: float, z: float) -> float:
	for o: Array in overrides:
		if (o[0] as Rect2).has_point(Vector2(x, z)):
			return o[1]
	return terrain_y(x, z)


func water_depth(x: float, z: float) -> float:
	for o: Array in overrides:
		if (o[0] as Rect2).has_point(Vector2(x, z)):
			return 0.0
	return maxf(water_y - terrain_y(x, z), 0.0)


func can_stand(p: Vector2) -> bool:
	var half := size * 0.5 - 0.5
	if absf(p.x) > half or absf(p.y) > half:
		return false
	if water_depth(p.x, p.y) > wade_depth:
		return false
	if not walk_block.is_empty():
		var g := (p - origin) / cell
		var i := clampi(int(floor(g.x + 0.5)), 0, grid_n)
		var j := clampi(int(floor(g.y + 0.5)), 0, grid_n)
		if walk_block[j * (grid_n + 1) + i] != 0:
			return false
	for r in placement.solid_rects:
		if r.has_point(p):
			return false
	for c in placement.solid_circles:
		if Vector2(c.x, c.y).distance_squared_to(p) < c.z * c.z:
			return false
	return true


# ---------------------------------------------------------------- 水面

## 水深贴图：每个网格顶点一个像素。R = 水深 / DEPTH_RANGE（陆地为 0）；G、B = 水流方向 × 流速（0.5 = 静水）。
## 水面 shader 用它算颜色、透明度、浪花、结冰，以及河面波光的流动
func make_depth_texture() -> ImageTexture:
	var img := Image.create(grid_n + 1, grid_n + 1, false, Image.FORMAT_RGBA8)
	var has_flow := flow.size() == heights.size()
	for j in grid_n + 1:
		for i in grid_n + 1:
			var d := clampf((water_y - get_h(i, j)) / DEPTH_RANGE, 0.0, 1.0)
			var f := flow[j * (grid_n + 1) + i] if has_flow else Vector2.ZERO
			img.set_pixel(i, j, Color(d, f.x * 0.5 + 0.5, f.y * 0.5 + 0.5, 1))
	return ImageTexture.create_from_image(img)


func _build_water() -> void:
	var has_water := false
	for h in heights:
		if h < water_y:
			has_water = true
			break
	if not has_water:
		return
	var span := grid_n * cell
	var plane := PlaneMesh.new()
	plane.size = Vector2(span, span)
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("depth_tex", make_depth_texture())
	m.set_shader_parameter("depth_rect", Vector4(origin.x, origin.y, span, span))
	m.set_shader_parameter("depth_range", DEPTH_RANGE)
	plane.material = m
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(origin.x + span * 0.5, water_y, origin.y + span * 0.5)
	_content.add_child(mi)


## 在一块水域里放一群鱼（area：活动范围；鱼会避开太浅的地方）
func add_fish(area: Rect2, count := 18) -> void:
	fish = PWFishSchool.new()
	fish.name = "Fish"
	fish.count = count
	fish.area = area
	fish.water_y = water_y
	fish.seed_value = seed_value
	fish.bed_height = terrain_y
	_content.add_child(fish)
