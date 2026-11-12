extends CanvasLayer
## Demo 控制面板（英文标签：Web 端默认字体不含中文字形）。

var main: Node
var _clock: Label
var _hour_slider: HSlider
var _auto: CheckBox
var _info: Label
var _syncing := false


func setup(m: Node) -> void:
	main = m


func _ready() -> void:
	layer = 10
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.14, 0.78)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	box.add_child(_label("Weather"))
	var grid := GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	for id in ["clear", "cloudy", "rain", "storm", "snow", "blizzard", "fog"]:
		var b := Button.new()
		b.text = id.capitalize()
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): main.weather.set_weather(id))
		grid.add_child(b)
	var bolt := Button.new()
	bolt.text = "Bolt!"
	bolt.focus_mode = Control.FOCUS_NONE
	bolt.pressed.connect(func(): main.weather.strike_lightning())
	grid.add_child(bolt)

	_clock = _label("Time")
	box.add_child(_clock)
	_hour_slider = HSlider.new()
	_hour_slider.min_value = 0
	_hour_slider.max_value = 24
	_hour_slider.step = 0.05
	_hour_slider.custom_minimum_size.x = 280
	_hour_slider.focus_mode = Control.FOCUS_NONE
	_hour_slider.value_changed.connect(func(v):
		if not _syncing:
			main.tod.hour = v)
	box.add_child(_hour_slider)

	var row := HBoxContainer.new()
	box.add_child(row)
	_auto = _check("Auto time", true, func(on): main.tod.running = on)
	row.add_child(_auto)
	row.add_child(_check("Walk", true, func(on): main.walk_mode = on))
	row.add_child(_check("Pixel", false, func(on): main.display.pixel_mode = on))
	row.add_child(_check("Tilt-shift", false, func(on): main.post.tilt_shift = on))

	var speed_row := HBoxContainer.new()
	box.add_child(speed_row)
	speed_row.add_child(_label("Day length"))
	var speed := OptionButton.new()
	speed.focus_mode = Control.FOCUS_NONE
	for s in [60, 300, 1200]:
		speed.add_item("%d s" % s)
	speed.select(1)
	speed.item_selected.connect(func(i): main.tod.day_length_seconds = [60, 300, 1200][i])
	speed_row.add_child(speed)

	_info = _label("")
	_info.add_theme_font_size_override("font_size", 12)
	_info.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_info)


func _process(_delta: float) -> void:
	if main == null or main.tod == null:
		return
	_syncing = true
	_hour_slider.value = main.tod.hour
	_syncing = false
	_auto.set_pressed_no_signal(main.tod.running)
	_clock.text = "Time  %s   (%s)" % [main.tod.get_clock_text(), main.weather.weather.capitalize()]
	var keys := "WASD walk  Q/E rotate  wheel zoom" if main.walk_mode else "WASD pan  Q/E rotate  wheel zoom  drag pan"
	_info.text = "snow %.2f  wet %.2f  night %.2f  render %dx%d\n%s" % [
		main.weather.snow_amount, main.weather.wetness, main.tod.night_factor,
		main.display.viewport.size.x, main.display.viewport.size.y, keys]


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _check(t: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = t
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	return c
