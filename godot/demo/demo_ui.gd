extends CanvasLayer
## 场景内的控制面板（中文，思源黑体裁剪版见 tools/subset_font.py）。
## 左上角一个可折叠的面板：场景 / 天气 / 时间 / 显示，底部是操作提示；右上角是场景信息。

const T := preload("res://addons/pixel_world/ui/pw_ui_theme.gd")

var main: Node
var _body: Control
var _toggle: Button
var _clock: Label
var _hour_slider: HSlider
var _auto: CheckBox
var _status: Label
var _scene_title: Label
var _weather_btns := {}
var _syncing := false


func setup(m: Node) -> void:
	main = m


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.theme = T.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.position = Vector2(14, 14)
	panel.custom_minimum_size.x = 320
	root.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	# 标题栏：场景名 + 折叠
	var head := HBoxContainer.new()
	outer.add_child(head)
	_scene_title = T.label("", 17, T.ACCENT)
	_scene_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_scene_title)
	_toggle = T.button("收起", func():
		_body.visible = not _body.visible
		_toggle.text = "收起" if _body.visible else "展开")
	head.add_child(_toggle)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	outer.add_child(body)
	_body = body

	# 场景
	var scene_row := HBoxContainer.new()
	body.add_child(scene_row)
	scene_row.add_child(T.button("主界面", func(): main.back_to_hub()))
	scene_row.add_child(T.button("换一个", func(): main.regenerate("", randi() % 100000)))
	for th in PWStyles.ready_ids():
		var id := th
		scene_row.add_child(T.button(PWStyles.get_style(th).name.substr(0, 2), func(): main.regenerate(id)))

	# 天气
	body.add_child(_section("天气"))
	var grid := GridContainer.new()
	grid.columns = 4
	body.add_child(grid)
	for spec in [["clear", "晴"], ["cloudy", "多云"], ["rain", "雨"], ["storm", "雷暴"],
			["snow", "雪"], ["blizzard", "暴风雪"], ["fog", "雾"]]:
		var wid: String = spec[0]
		var b := T.button(spec[1], func(): main.weather.set_weather(wid))
		b.toggle_mode = true
		b.custom_minimum_size.x = 70
		grid.add_child(b)
		_weather_btns[wid] = b
	grid.add_child(T.button("闪电", func(): main.weather.strike_lightning()))

	# 时间
	body.add_child(_section("时间"))
	_clock = T.label("", 15)
	body.add_child(_clock)
	_hour_slider = HSlider.new()
	_hour_slider.min_value = 0
	_hour_slider.max_value = 24
	_hour_slider.step = 0.05
	_hour_slider.focus_mode = Control.FOCUS_NONE
	_hour_slider.value_changed.connect(func(v):
		if not _syncing:
			main.tod.hour = v)
	body.add_child(_hour_slider)
	var trow := HBoxContainer.new()
	body.add_child(trow)
	_auto = _check("自动流逝", true, func(on): main.tod.running = on)
	trow.add_child(_auto)
	var speed := OptionButton.new()
	speed.focus_mode = Control.FOCUS_NONE
	for s in [["一天 1 分钟", 60], ["一天 5 分钟", 300], ["一天 20 分钟", 1200]]:
		speed.add_item(s[0])
	speed.select(1)
	speed.item_selected.connect(func(i): main.tod.day_length_seconds = [60, 300, 1200][i])
	trow.add_child(speed)

	# 显示
	body.add_child(_section("显示"))
	var drow := HBoxContainer.new()
	body.add_child(drow)
	drow.add_child(_check("走路", true, func(on): main.walk_mode = on))
	drow.add_child(_check("像素风", main.display.pixel_mode, func(on): main.display.pixel_mode = on))
	drow.add_child(_check("移轴", false, func(on): main.post.tilt_shift = on))

	_status = T.label("", 12, T.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)

	# 底部操作提示
	var hint := PanelContainer.new()
	hint.add_theme_stylebox_override("panel", T.box(Color(0, 0, 0, 0.45), 6, 8))
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -50
	hint.offset_bottom = -14
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(hint)
	hint.add_child(T.label("WASD 走动    Q / E 旋转镜头    滚轮缩放", 14, T.TEXT_DIM))


func _section(text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_child(T.label(text, 14, T.ACCENT))
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.08)
	line.custom_minimum_size.y = 1
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(line)
	return h


func _process(_delta: float) -> void:
	if main == null or main.tod == null or main.world == null:
		return
	_syncing = true
	_hour_slider.value = main.tod.hour
	_syncing = false
	_auto.set_pressed_no_signal(main.tod.running)
	_clock.text = main.tod.get_clock_text()
	var st := PWStyles.get_style(main.world.theme)
	_scene_title.text = "%s  #%d" % [st.name, main.world.seed_value]
	for k: String in _weather_btns:
		(_weather_btns[k] as Button).set_pressed_no_signal(k == main.weather.weather)
	_status.text = "积雪 %.0f%%   潮湿 %.0f%%   渲染 %d×%d" % [
		main.weather.snow_amount * 100.0, main.weather.wetness * 100.0,
		main.display.viewport.size.x, main.display.viewport.size.y]


func _check(t: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = t
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	return c
