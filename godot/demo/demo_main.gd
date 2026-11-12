extends Control
## Demo 入口：像素渲染容器 + 小镇 + 昼夜 + 天气 + 相机 + 后期 + 控制面板。
##
## 命令行截图（用于自动验证）：
##   godot --path godot -- --weather=snow --hour=20 --screenshot=/tmp/a.png
## 其它参数：--snap（积雪/潮湿立刻到位） --frames=N（截图前等待帧数） --no-pixel

const Globals := preload("res://addons/pixel_world/core/pw_globals.gd")
const PixelDisplay := preload("res://addons/pixel_world/render/pw_pixel_display.gd")
const TimeOfDay := preload("res://addons/pixel_world/weather/pw_time_of_day.gd")
const Weather := preload("res://addons/pixel_world/weather/pw_weather_system.gd")
const CameraRig := preload("res://addons/pixel_world/render/pw_camera_rig.gd")
const PostFX := preload("res://addons/pixel_world/render/pw_post_fx.gd")
const DemoTown := preload("res://demo/demo_town.gd")
const DemoUI := preload("res://demo/demo_ui.gd")

var display: PWPixelDisplay
var tod: PWTimeOfDay
var weather: PWWeatherSystem
var rig: PWCameraRig
var post: PWPostFX
var _dragging := false


func _ready() -> void:
	Globals.ensure_runtime()
	display = PixelDisplay.new()
	add_child(display)
	var vp := display.viewport

	var town := DemoTown.new()
	town.name = "Town"
	vp.add_child(town)
	town.build()

	tod = TimeOfDay.new()
	tod.name = "TimeOfDay"
	vp.add_child(tod)
	weather = Weather.new()
	weather.name = "WeatherSystem"
	weather.time_of_day = tod
	vp.add_child(weather)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	vp.add_child(rig)
	post = PostFX.new()
	vp.add_child(post)

	var ui := DemoUI.new()
	ui.setup(self)
	add_child(ui)

	_apply_cmdline()


func _apply_cmdline() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("hour"):
		tod.hour = float(args["hour"])
		tod.running = false
	if args.has("weather"):
		weather.set_weather(args["weather"], 0.0, args.has("snap"))
	if args.has("no-pixel"):
		display.pixel_mode = false
	if args.has("yaw"):
		rig.yaw_deg = float(args["yaw"])
	if args.has("distance"):
		rig.distance = float(args["distance"])
	if args.has("screenshot"):
		var frames := int(args.get("frames", "90"))
		for i in frames:
			await get_tree().process_frame
		if args.has("flash"):
			weather.flash = 1.0
			await get_tree().process_frame
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(args["screenshot"])
		print("screenshot saved: ", args["screenshot"])
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			rig.zoom(0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			rig.zoom(1.1)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		rig.pan_pixels((event as InputEventMouseMotion).relative, size.y)
