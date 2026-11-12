extends Control
## Demo 入口：渲染容器 + 小镇 + 昼夜 + 天气 + 相机 + 后期 + 角色 + 控制面板。
## 默认「走路模式」：WASD / 方向键控制角色，镜头跟随；关闭后 WASD 平移镜头。
##
## 命令行截图（用于自动验证）：
##   godot --path godot -- --weather=snow --hour=20 --screenshot=/tmp/a.png
## 其它参数：--snap（积雪/潮湿立刻到位） --frames=N（截图前等待帧数） --pixel（像素模式）
##           --distance=米 --yaw=度 --focus=x,z（镜头对准的地面位置，并关闭走路模式）
##           --player=x,z（角色位置） --walk=x,z（截图前让角色朝这个方向走）

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
var town: DemoTown
var player: PWCharacter
## 走路模式：WASD 控制角色、镜头跟随
var walk_mode := true:
	set(v):
		walk_mode = v
		if rig != null:
			rig.keyboard_pan = not v
var _dragging := false
var _auto_walk := Vector3.ZERO


func _ready() -> void:
	Globals.ensure_runtime()
	display = PixelDisplay.new()
	add_child(display)
	var vp := display.viewport

	town = DemoTown.new()
	town.name = "Town"
	vp.add_child(town)
	town.build()

	player = PWCharacter.new()
	player.name = "Player"
	player.position = Vector3(5.0, 0.0, 9.0)  # 码头土路上
	player.ground_height = town.ground_y
	player.can_stand = town.can_stand
	player.water_depth = town.water_depth
	vp.add_child(player)
	town.fish.threat = player

	tod = TimeOfDay.new()
	tod.name = "TimeOfDay"
	vp.add_child(tod)
	weather = Weather.new()
	weather.name = "WeatherSystem"
	weather.time_of_day = tod
	vp.add_child(weather)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	rig.position = player.position
	rig.min_distance = 6.0
	rig.distance = 22.0
	rig.keyboard_pan = not walk_mode
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
	if args.has("snow"):  # --snow=0..1：直接设定积雪量（看积雪过程）
		weather.snow_amount = float(args["snow"])
	if args.has("wet"):
		weather.wetness = float(args["wet"])
	if args.has("pixel"):
		display.pixel_mode = true
	if args.has("tilt"):
		post.tilt_shift = true
	if args.has("yaw"):
		rig.yaw_deg = float(args["yaw"])
	if args.has("distance"):
		rig.distance = float(args["distance"])
	if args.has("player"):
		var pz: PackedStringArray = args["player"].split(",")
		player.position = Vector3(float(pz[0]), town.ground_y(float(pz[0]), float(pz[1])), float(pz[1]))
		rig.position = player.position
	if args.has("walk"):
		var wz: PackedStringArray = args["walk"].split(",")
		_auto_walk = Vector3(float(wz[0]), 0.0, float(wz[1]))
	if args.has("focus"):  # --focus=x,z：镜头对准的地面位置（关闭走路模式）
		var xz: PackedStringArray = args["focus"].split(",")
		walk_mode = false
		rig.position = Vector3(float(xz[0]), 0.0, float(xz[1]))
	if args.has("run"):  # 指定 --hour 时默认停住时间；加 --run 让时间继续走
		tod.running = true
	if args.has("diffshot"):
		await _diff_shot(args["diffshot"], int(args.get("frames", "90")), int(args.get("gap", "20")))
		get_tree().quit()
		return
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


## 画面稳定性检查：隔 gap 帧截两张图（隐藏 UI），把变化的像素标成洋红色保存，并打印变化比例。
## 静止镜头下变化越少越好（雨雪粒子、水面波光属于正常变化）。
func _diff_shot(path: String, frames: int, gap: int) -> void:
	for c in get_children():
		if c is CanvasLayer or (c is Control and c != display):
			c.visible = false
	for i in frames:
		await get_tree().process_frame
	var a := get_viewport().get_texture().get_image()
	for i in gap:
		await get_tree().process_frame
	var b := get_viewport().get_texture().get_image()
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var da := a.get_data()
	var db := b.get_data()
	var changed := 0
	for i in range(0, da.size(), 3):
		if absi(da[i] - db[i]) + absi(da[i + 1] - db[i + 1]) + absi(da[i + 2] - db[i + 2]) > 24:
			changed += 1
			db[i] = 255
			db[i + 1] = 0
			db[i + 2] = 255
	var out := Image.create_from_data(b.get_width(), b.get_height(), false, Image.FORMAT_RGB8, db)
	out.save_png(path)
	print("diff saved: %s  changed=%d (%.2f%%)" % [path, changed, 100.0 * changed / (da.size() / 3)])


## 走路模式：WASD / 方向键按镜头方向移动角色，镜头平滑跟随
func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if walk_mode:
		var mv := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			mv.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			mv.x += 1
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			mv.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			mv.y += 1
		var y := deg_to_rad(rig.yaw_deg)
		var right := Vector3(cos(y), 0, -sin(y))
		var down := Vector3(sin(y), 0, cos(y))
		dir = (right * mv.x + down * mv.y).normalized()
	if _auto_walk != Vector3.ZERO:
		dir = _auto_walk.normalized()
	player.walk(dir, delta)
	if walk_mode:
		rig.position = rig.position.lerp(Vector3(player.position.x, 0.0, player.position.z), 1.0 - exp(-delta * 4.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			rig.zoom(0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			rig.zoom(1.1)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging and not walk_mode:
		rig.pan_pixels((event as InputEventMouseMotion).relative, size.y)
