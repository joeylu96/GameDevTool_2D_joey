@tool
class_name PWHub
extends Control
## Pixel World 主界面：进入工具后先看到这里，而不是直接进场景。
##   资源库      —— 浏览所有资源（按分类），3D 预览，「换一批」看同一资源的不同变体
##   场景生成器  —— 选择风格（小镇 / 森林 / 平原 / 即将推出……）和参数，预览，然后进入场景
##   特效库      —— 天气、积水与涟漪、积雪、路灯光斑、水面、后期，在演示小场景里实时查看
##   天气光照    —— 昼夜关键帧、时间、阴影，在演示小场景里实时查看
##   关于        —— 操作说明与文档位置
## 运行时由 Demo 使用（enter_scene 信号进入场景）；在编辑器里作为主屏幕「Pixel World」使用
## （editor_mode = true，生成器的按钮改为「生成到当前场景」，发出 generate_in_editor 信号）。

signal enter_scene(config: Dictionary)
signal generate_in_editor(config: Dictionary)

const T := preload("res://addons/pixel_world/ui/pw_ui_theme.gd")

var editor_mode := false
var _pages := {}
var _nav := {}
var _current := ""
var _diorama: PWPreview
var _diorama_world: PWWorld
var _content_host: Control

# 资源库
var _cat_list: ItemList
var _item_list: ItemList
var _asset_preview: PWPreview
var _asset_title: Label
var _asset_desc: Label
var _asset_vary: Label
var _asset_items: Array[Dictionary] = []
var _asset_item: Dictionary = {}
var _asset_batch := 0

# 场景生成器
var _style_id := "town"
var _style_cards := {}
var _seed: SpinBox
var _size: SpinBox
var _trees: HSlider
var _houses: HSlider
var _bushes: HSlider
var _lake: CheckBox
var _gen_preview: PWPreview
var _gen_status: Label
var _style_desc: Label

# 特效 / 天气光照
var _fx_info: Label
var _fx_host: Control
var _light_host: Control
var _hour: HSlider
var _clock: Label
var _auto_time: CheckBox


func _ready() -> void:
	theme = T.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = T.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	row.add_child(_build_nav())
	var host := MarginContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		host.add_theme_constant_override("margin_" + side, 18)
	row.add_child(host)
	_content_host = host
	_pages["assets"] = _build_assets_page()
	_pages["generator"] = _build_generator_page()
	_pages["effects"] = _build_effects_page()
	_pages["lighting"] = _build_lighting_page()
	_pages["about"] = _build_about_page()
	for k: String in _pages:
		host.add_child(_pages[k])
	show_page("generator")
	# 一进来就有一个默认预览，而不是一块空草地；换风格时也自动刷新预览
	if not Engine.is_editor_hint() or editor_mode:
		_preview_world.call_deferred()


# ---------------------------------------------------------------- 左侧导航

func _build_nav() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 210
	panel.add_theme_stylebox_override("panel", T.box(Color(0.05, 0.06, 0.09, 1.0), 0, 16))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(T.label("Pixel World", 24, T.ACCENT))
	v.add_child(T.label("像素世界工具箱", 14, T.TEXT_DIM))
	var sp := Control.new()
	sp.custom_minimum_size.y = 18
	v.add_child(sp)
	for spec in [["generator", "场景生成器"], ["assets", "资源库"], ["effects", "特效库"], ["lighting", "天气光照"], ["about", "关于"]]:
		var b := Button.new()
		b.text = "  " + spec[1]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 40
		b.add_theme_font_size_override("font_size", 16)
		var id: String = spec[0]
		b.pressed.connect(func(): show_page(id))
		v.add_child(b)
		_nav[id] = b
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	v.add_child(T.label("Godot 4.7 · Blender 5.2", 12, T.TEXT_DIM))
	return panel


func show_page(id: String) -> void:
	_current = id
	for k: String in _pages:
		(_pages[k] as Control).visible = k == id
		(_nav[k] as Button).set_pressed_no_signal(k == id)
	match id:
		"assets":
			if _asset_item.is_empty():
				_select_category(0)
		"effects":
			_attach_diorama(_fx_host)
			_apply_fx()
		"lighting":
			_attach_diorama(_light_host)
			if _fx_actor != null:
				_fx_actor.visible = false
			_diorama.reset_view()


func _page(title: String, subtitle: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(T.label(title, 26))
	v.add_child(T.label(subtitle, 14, T.TEXT_DIM))
	return v


# ---------------------------------------------------------------- 资源库

func _build_assets_page() -> Control:
	var page := _page("资源库", "工具链里所有能放进场景的资源。同一种资源每次放进场景都会有变化——点「换一批」看看。")
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	_cat_list = ItemList.new()
	_cat_list.custom_minimum_size.x = 150
	for c: Dictionary in PWAssetLibrary.CATEGORIES:
		_cat_list.add_item("%s（%d）" % [c.name, PWAssetLibrary.in_category(c.id).size()])
	_cat_list.item_selected.connect(_select_category)
	row.add_child(_cat_list)
	_item_list = ItemList.new()
	_item_list.custom_minimum_size.x = 180
	_item_list.item_selected.connect(func(i): _select_item(_asset_items[i]))
	row.add_child(_item_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	_asset_preview = PWPreview.new()
	right.add_child(_asset_preview)
	var info := PanelContainer.new()
	right.add_child(info)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 6)
	info.add_child(iv)
	var head := HBoxContainer.new()
	iv.add_child(head)
	_asset_title = T.label("", 20, T.ACCENT)
	_asset_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_asset_title)
	head.add_child(T.button("换一批", func():
		_asset_batch += 1
		_show_asset()))
	_asset_desc = T.label("", 14)
	_asset_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(_asset_desc)
	_asset_vary = T.label("", 13, T.TEXT_DIM)
	_asset_vary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(_asset_vary)
	return page


func _select_category(i: int) -> void:
	_cat_list.select(i)
	var cat: Dictionary = PWAssetLibrary.CATEGORIES[i]
	_asset_items = PWAssetLibrary.in_category(cat.id)
	_item_list.clear()
	for it in _asset_items:
		_item_list.add_item(it.name)
	if _asset_items.is_empty():
		_asset_item = {}
		_asset_title.text = cat.name
		_asset_desc.text = "这个分类还没有资源。" + ("运行 tools/blender_build_assets.py 生成 Blender 资产后会出现在这里。" if cat.id == "blender" else "")
		_asset_vary.text = ""
		_asset_preview.set_content(null, 3.0)
		return
	_item_list.select(0)
	_select_item(_asset_items[0])


func _select_item(it: Dictionary) -> void:
	_asset_item = it
	_asset_batch = 0
	_show_asset()


## 展示数量按资源本身决定（PWAssetLibrary 的 show）：
##   [最少, 最多] —— 场景里成片出现的（树、草、石头……）：每次随机一个数量，自然散开，每个都不一样
##   "styles:N"   —— 有固定款式的（路灯、篱笆、长椅）：每种款式一个，排成一排
##   1            —— 独一个的（角色、房屋、地标）：只放一个，「换一批」换一个变体
func _show_asset() -> void:
	var it := _asset_item
	if it.is_empty():
		return
	_asset_title.text = it.name
	_asset_desc.text = it.desc
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([it.id, _asset_batch])
	var holder := Node3D.new()
	var sz: float = it.get("size", 2.0)
	var show: Variant = it.get("show", 1)
	var count := 1
	var mode := "single"
	if show is Array:
		mode = "random"
		count = rng.randi_range(show[0], show[1])
	elif show is String and (show as String).begins_with("styles:"):
		mode = "styles"
		count = int((show as String).trim_prefix("styles:"))
	var mode_text := {"single": "单个展示（换一批 = 换一个变体）", "random": "随机 %d 个（场景里会成片出现，每个都不一样）" % count,
		"styles": "全部 %d 种款式" % count}
	_asset_vary.text = "变化：%s\n展示：%s" % [it.vary, mode_text[mode]]
	var placed: Array[Vector2] = []
	var radius := sz * (0.6 + sqrt(float(count)) * 0.75)
	for k in count:
		var variant := k if mode == "styles" else _asset_batch * 16 + k
		var node := PWAssetLibrary.instantiate(it, variant, rng)
		if mode == "styles":
			node.position = Vector3((k - (count - 1) * 0.5) * sz * 1.3, 0, 0)
		elif mode == "random":
			# 泊松式随机散布：彼此保持一点距离
			var p := Vector2.ZERO
			for attempt in 30:
				p = Vector2(rng.randf_range(-radius, radius), rng.randf_range(-radius, radius))
				var ok := true
				for q in placed:
					if q.distance_to(p) < sz * 0.8:
						ok = false
				if ok:
					break
			placed.append(p)
			node.position = Vector3(p.x, 0, p.y)
		holder.add_child(node)
	var frame := sz * 0.8
	if mode == "styles":
		frame = sz * (0.5 + count * 0.55)
	elif mode == "random":
		frame = radius * 1.1
	_asset_preview.set_content(holder, frame)


# ---------------------------------------------------------------- 场景生成器

func _build_generator_page() -> Control:
	var page := _page("场景生成器", "选一种风格，设好参数，先预览，满意了再进入场景。同一个种子总是生成同一个场景。")
	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 10)
	cards.add_theme_constant_override("v_separation", 10)
	page.add_child(cards)
	for st: Dictionary in PWStyles.STYLES:
		cards.add_child(_style_card(st))
	_style_desc = T.label("", 14, T.TEXT_DIM)
	_style_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_style_desc)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	page.add_child(row)
	# 参数
	var params := PanelContainer.new()
	params.custom_minimum_size.x = 300
	row.add_child(params)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	params.add_child(pv)
	pv.add_child(T.label("参数", 18, T.ACCENT))
	var seed_row := HBoxContainer.new()
	_seed = _spin(0, 999999, 1, 7)
	seed_row.add_child(_labeled("种子", _seed))
	seed_row.add_child(T.button("随机", func(): _seed.value = randi() % 100000))
	pv.add_child(seed_row)
	_size = _spin(32, 192, 8, 80)
	pv.add_child(_labeled("尺寸（米）", _size))
	_trees = _slider(1.0)
	pv.add_child(_labeled("树木密度", _trees))
	_houses = _slider(1.0)
	pv.add_child(_labeled("房屋密度", _houses))
	_bushes = _slider(1.0)
	pv.add_child(_labeled("灌木密度", _bushes))
	_lake = CheckBox.new()
	_lake.text = "生成湖（和河）"
	_lake.button_pressed = true
	_lake.focus_mode = Control.FOCUS_NONE
	pv.add_child(_lake)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(fill)
	_gen_status = T.label("", 13, T.TEXT_DIM)
	_gen_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(_gen_status)
	pv.add_child(T.button("预览", _preview_world))
	pv.add_child(T.button("生成到当前场景" if editor_mode else "进入场景", _enter, true))
	# 预览
	_gen_preview = PWPreview.new()
	_gen_preview.pitch = 48.0
	row.add_child(_gen_preview)
	_select_style("town")
	return page


func _style_card(st: Dictionary) -> Control:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 74)
	b.disabled = not st.ready
	b.text = "%s\n%s" % [st.name, st.en if st.ready else "即将推出"]
	b.add_theme_font_size_override("font_size", 16)
	var sb := T.box(T.PANEL_HI, 8, 10)
	sb.border_width_left = 6
	sb.border_color = st.color
	b.add_theme_stylebox_override("normal", sb)
	var hv := sb.duplicate()
	hv.bg_color = T.PANEL_HI.lightened(0.1)
	b.add_theme_stylebox_override("hover", hv)
	var pr := sb.duplicate()
	pr.bg_color = (st.color as Color).darkened(0.45)
	pr.set_border_width_all(2)
	pr.border_width_left = 6
	b.add_theme_stylebox_override("pressed", pr)
	var ds := sb.duplicate()
	ds.bg_color = T.PANEL.darkened(0.2)
	b.add_theme_stylebox_override("disabled", ds)
	b.tooltip_text = st.desc
	var id: String = st.id
	b.pressed.connect(func():
		_select_style(id)
		_preview_world())
	_style_cards[id] = b
	return b


func _select_style(id: String) -> void:
	_style_id = id
	var st := PWStyles.get_style(id)
	for k: String in _style_cards:
		(_style_cards[k] as Button).set_pressed_no_signal(k == id)
	_style_desc.text = "%s：%s" % [st.name, st.desc]
	_size.value = st.get("size", 80)
	_houses.editable = st.get("generator", "") == "town"


func config() -> Dictionary:
	return {"theme": _style_id, "seed": int(_seed.value), "size": int(_size.value),
		"tree_density": _trees.value, "house_density": _houses.value, "bush_density": _bushes.value,
		"with_lake": _lake.button_pressed}


static func apply_config(w: PWWorld, c: Dictionary) -> void:
	w.theme = c.get("theme", "town")
	w.seed_value = c.get("seed", 7)
	w.size = c.get("size", 80)
	w.tree_density = c.get("tree_density", 1.0)
	w.house_density = c.get("house_density", 1.0)
	w.bush_density = c.get("bush_density", 1.0)
	w.with_lake = c.get("with_lake", true)


func _preview_world() -> void:
	_gen_status.text = "生成中……"
	await get_tree().process_frame
	await get_tree().process_frame
	var w := PWWorld.new()
	w.generate_on_ready = false
	apply_config(w, config())
	_gen_preview.set_content(w, w.size * 0.42, false)
	w.generate()
	_gen_status.text = "%s #%d：%s" % [PWStyles.get_style(w.theme).name, w.seed_value, _stats_text(w.stats)]


static func _stats_text(s: Dictionary) -> String:
	var names := {"house": "房屋", "lamp": "路灯", "tree": "树", "bush": "灌木", "rock": "石头", "grass": "草丛", "landmark": "地点", "lakes": "湖"}
	var parts := PackedStringArray()
	for k: String in names:
		if s.has(k):
			parts.append("%s %s" % [names[k], s[k]])
	if s.get("river", false):
		parts.append("有河")
	return "，".join(parts)


func _enter() -> void:
	if editor_mode:
		generate_in_editor.emit(config())
	else:
		enter_scene.emit(config())


# ---------------------------------------------------------------- 特效库 / 天气光照（共用一个演示小场景）

## 特效分类：天气（天气系统）、环境（时间 / 水面）、动作（PWVFX：攻击、受击、法术、增益、移动）
const FX_CATEGORIES := ["天气", "环境", "动作"]
const EFFECTS := [
	{"cat": "天气", "name": "晴天", "weather": "clear", "hour": 11.0, "info": "直射阳光、清晰的阴影（太阳方向每游戏分钟更新一次，阴影稳定不闪）。积雪、积水立刻清除。"},
	{"cat": "天气", "name": "多云", "weather": "cloudy", "hour": 11.0, "info": "直射光减弱，阴影变淡，画面整体发灰。"},
	{"cat": "天气", "name": "雨：积水与涟漪", "weather": "rain", "hour": 14.0, "info": "地面变暗变亮滑，平地上长出反射天空的水洼，雨滴打出一圈圈涟漪；水面也有雨点。"},
	{"cat": "天气", "name": "雷暴：闪电", "weather": "storm", "hour": 17.0, "info": "大雨 + 强风，随机间隔的闪电让画面瞬间变亮。"},
	{"cat": "天气", "name": "雪：积雪", "weather": "snow", "hour": 12.0, "info": "朝上的面一簇簇积起雪，积满后成块；路面斑驳；湖面从浅处开始结冰。"},
	{"cat": "天气", "name": "暴风雪", "weather": "blizzard", "hour": 12.0, "info": "密集的雪和大风，雾更浓。"},
	{"cat": "天气", "name": "雾", "weather": "fog", "hour": 8.0, "info": "距离雾 + 去饱和，远处逐渐看不清。"},
	{"cat": "环境", "name": "白天", "weather": "clear", "hour": 11.0, "info": "正午的光照，作为对比基准。"},
	{"cat": "环境", "name": "黄昏", "weather": "clear", "hour": 18.0, "info": "低角度的暖色阳光，长长的影子，天空泛橙。"},
	{"cat": "环境", "name": "夜晚：灯光", "weather": "clear", "hour": 21.0, "info": "窗户随机亮灯，路灯灯头发光，地面有平滑渐变的光斑。"},
	{"cat": "环境", "name": "雨夜", "weather": "rain", "hour": 21.0, "info": "夜晚的灯光映在湿漉漉的地面和水洼上。"},
	{"cat": "环境", "name": "水面", "weather": "clear", "hour": 15.0, "info": "浅滩透明能看到沙底和鱼，越深越蓝；岸边浪花、波光短线；河水的波光顺着流向移动。"},
]

var _fx_cat := "天气"
var _fx_list: ItemList
var _fx_items: Array[Dictionary] = []
var _fx_cat_btns := {}
var _fx_actor: Node3D
var _fx_loop: CheckBox
var _fx_play: Button
var _fx_current: Dictionary = {}
var _fx_timer := 0.0


func _build_effects_page() -> Control:
	var page := _page("特效库", "工具链内置的效果，分为天气、环境和动作三类。点条目在右边的演示小场景里实时查看。")
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	var tabs := HBoxContainer.new()
	left.add_child(tabs)
	for c: String in FX_CATEGORIES:
		var b := T.button(c, func(): _select_fx_category(c))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_fx_cat_btns[c] = b
	_fx_list = ItemList.new()
	_fx_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fx_list.item_selected.connect(func(i): _select_fx(_fx_items[i]))
	left.add_child(_fx_list)
	var prow := HBoxContainer.new()
	left.add_child(prow)
	_fx_play = T.button("播放", func(): _play_fx(), true)
	prow.add_child(_fx_play)
	_fx_loop = CheckBox.new()
	_fx_loop.text = "循环播放"
	_fx_loop.button_pressed = true
	_fx_loop.focus_mode = Control.FOCUS_NONE
	prow.add_child(_fx_loop)
	_fx_info = T.label("", 14)
	_fx_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fx_info.custom_minimum_size.y = 90
	left.add_child(_fx_info)
	_fx_host = VBoxContainer.new()
	_fx_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_fx_host)
	_select_fx_category("天气")
	return page


func _select_fx_category(cat: String) -> void:
	_fx_cat = cat
	for k: String in _fx_cat_btns:
		(_fx_cat_btns[k] as Button).set_pressed_no_signal(k == cat)
	_fx_items.clear()
	_fx_list.clear()
	if cat == "动作":
		for e: Dictionary in PWVFX.CATALOG:
			_fx_items.append({"cat": "动作", "vfx": e.id, "name": e.name, "group": e.cat, "info": e.desc})
			_fx_list.add_item("%s · %s" % [e.cat, e.name])
	else:
		for e: Dictionary in EFFECTS:
			if e.cat == cat:
				_fx_items.append(e)
				_fx_list.add_item(e.name)
	var is_action := cat == "动作"
	_fx_play.visible = is_action
	_fx_loop.visible = is_action
	if not _fx_items.is_empty():
		_fx_list.select(0)
		_select_fx(_fx_items[0])


func _select_fx(e: Dictionary) -> void:
	_fx_current = e
	_fx_info.text = e.info
	if _current == "effects":
		_apply_fx()


## 在演示小场景里应用当前选中的特效（只在特效页可见时调用，避免主界面一启动就生成演示场景）
func _apply_fx() -> void:
	var e := _fx_current
	if e.is_empty():
		return
	_ensure_diorama()
	if e.has("vfx"):
		# 动作特效：晴天白天，场景中间站一个角色，镜头拉近
		_diorama.weather.set_weather("clear", 0.0, true)
		_diorama.tod.hour = 11.0
		_ensure_fx_actor()
		_diorama.distance = 9.0
		_diorama.pitch = 24.0
		_diorama.pivot.position = _fx_actor.position + Vector3(0, 0.9, 0)
		_diorama._update_camera()
		_play_fx()
	else:
		if _fx_actor != null:
			_fx_actor.visible = false
		_diorama.tod.hour = e.hour
		_diorama.weather.set_weather(e.weather, 0.0, true)
		_diorama.reset_view()


func _ensure_fx_actor() -> void:
	if _fx_actor == null:
		var c := PWCharacter.new()
		c.name = "FxActor"
		c.sprite_id = "swordsman"  # 有像素精灵就用精灵角色（没有时自动退回低模）
		var p := _diorama_world.spawn_point
		c.position = p
		_diorama.root.add_child(c)
		_fx_actor = c
	_fx_actor.visible = true


func _play_fx() -> void:
	if not _fx_current.has("vfx") or _fx_actor == null:
		return
	# 特效朝向镜头的右手边，弧线和飞行轨迹从侧面看最清楚
	var y := deg_to_rad(_diorama.yaw)
	var right := Vector3(cos(y), 0, -sin(y))
	var pos := _fx_actor.position
	var id: String = _fx_current.vfx
	if id in ["slash", "slash_x", "fireball", "dust"]:
		_fx_actor.rotation.y = atan2(right.x, right.z)
	if id == "hit":
		pos += right * 1.2
	PWVFX.spawn(id, _diorama.root, pos, right)
	_fx_timer = 0.0


func _build_lighting_page() -> Control:
	var page := _page("天气光照", "昼夜按关键帧插值（太阳色 / 强度、环境光、天空）。拖动时间看一天里的光线变化。")
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	_clock = T.label("时间 11:00", 20, T.ACCENT)
	left.add_child(_clock)
	_hour = _slider(11.0, 0.0, 24.0, 0.05)
	_hour.value_changed.connect(func(v):
		_ensure_diorama()
		_diorama.tod.hour = v)
	left.add_child(_hour)
	_auto_time = CheckBox.new()
	_auto_time.text = "时间自动流逝"
	_auto_time.focus_mode = Control.FOCUS_NONE
	_auto_time.toggled.connect(func(on):
		_ensure_diorama()
		_diorama.tod.running = on
		_diorama.tod.day_length_seconds = 60.0)
	left.add_child(_auto_time)
	left.add_child(T.label("天气", 16, T.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	left.add_child(grid)
	for spec in [["clear", "晴"], ["cloudy", "多云"], ["rain", "雨"], ["storm", "雷暴"], ["snow", "雪"], ["fog", "雾"]]:
		var wid: String = spec[0]
		grid.add_child(T.button(spec[1], func():
			_ensure_diorama()
			_diorama.weather.set_weather(wid, 1.5, true)))
	left.add_child(T.label("昼夜关键帧", 16, T.ACCENT))
	for key: Array in PWTimeOfDay.KEYS:
		if key[0] >= 24.0:
			continue
		var kr := HBoxContainer.new()
		kr.add_child(T.label("%05.2f" % key[0], 13, T.TEXT_DIM))
		for c in [key[1], key[3], key[5]]:
			var sw := ColorRect.new()
			sw.color = c
			sw.custom_minimum_size = Vector2(36, 16)
			kr.add_child(sw)
		kr.add_child(T.label("太阳 %.2f  环境 %.2f" % [key[2], key[4]], 13, T.TEXT_DIM))
		left.add_child(kr)
	left.add_child(T.label("色块：太阳色 / 环境光色 / 天空色", 12, T.TEXT_DIM))
	_light_host = VBoxContainer.new()
	_light_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_light_host)
	return page


func _ensure_diorama() -> void:
	if _diorama != null:
		return
	_diorama = PWPreview.new(true)
	_diorama.pitch = 38.0
	_diorama_world = PWWorld.new()
	_diorama_world.generate_on_ready = false
	_diorama_world.theme = "town"
	_diorama_world.size = 48
	_diorama_world.seed_value = 3
	_diorama.set_content(_diorama_world, 17.0)
	_diorama_world.generate()


func _attach_diorama(host: Control) -> void:
	_ensure_diorama()
	if _diorama.get_parent() != host:
		if _diorama.get_parent() != null:
			_diorama.get_parent().remove_child(_diorama)
		host.add_child(_diorama)


func _process(delta: float) -> void:
	if _current == "effects" and _fx_current.has("vfx") and _fx_loop != null and _fx_loop.button_pressed:
		_fx_timer += delta
		if _fx_timer > 2.2:
			_play_fx()
	if _diorama != null and _diorama.tod != null and _clock != null and _current == "lighting":
		_clock.text = "时间 " + _diorama.tod.get_clock_text()
		if _auto_time.button_pressed:
			_hour.set_value_no_signal(_diorama.tod.hour)


# ---------------------------------------------------------------- 关于

func _build_about_page() -> Control:
	var page := _page("关于", "")
	var txt := T.label("", 15)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.text = """进入场景后的操作
  WASD / 方向键：走动（镜头跟随）    Q / E：旋转镜头    滚轮：缩放
  左上角面板：换天气、调时间、切换显示效果、回到主界面

当前进度
  P0 风格规范、统一材质     P1 天气与昼夜     P2 场景生成（小镇 / 森林 / 平原）
  P3 Blender 资产生成（进行中）     P4 NPC     P5 打磨

文档
  docs/DESIGN.md        方案设计与进度
  docs/VISUAL_SPEC.md   画面参数、阴影规则、摆放规则、草的规则
  README.md             环境要求与使用方法

工具版本：Godot 4.7.2 · Blender 5.2 LTS（Windows / macOS 统一）"""
	page.add_child(txt)
	return page


# ---------------------------------------------------------------- 小工具

func _labeled(text: String, c: Control) -> Control:
	var h := HBoxContainer.new()
	var l := T.label(text, 14)
	l.custom_minimum_size.x = 86
	h.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(c)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h


func _spin(lo: float, hi: float, step: float, v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	return s


func _slider(v: float, lo := 0.0, hi := 2.0, step := 0.05) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size.x = 120
	return s
