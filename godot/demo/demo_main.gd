extends Control
## Demo 入口：先显示主界面（PWHub），进入场景后是渲染容器 + 生成的场景（PWWorld）+ 昼夜 + 天气 + 相机 + 后期 + 角色 + 控制面板。
## 默认「走路模式」：WASD / 方向键控制角色，镜头跟随；关闭后 WASD 平移镜头。
## 像素精灵角色的动作：Shift 跑步，J 攻击（带斩击特效），K 施法（带魔法阵），H 受击。NPC 走近会挥手打招呼。
##
## 命令行截图（用于自动验证）：
##   godot --path godot -- --weather=snow --hour=20 --screenshot=/tmp/a.png
## 其它参数：--theme=town|forest|plains --seed=N --size=米（场景生成）
##           --snap（积雪/潮湿立刻到位） --frames=N（截图前等待帧数） --pixel（像素模式）
##           --distance=米 --yaw=度 --focus=x,z（镜头对准的地面位置，并关闭走路模式）
##           --player=x,z（角色位置） --walk=x,z（截图前让角色朝这个方向走）
##           --model3d（玩家用低模身体而不是像素精灵） --npcs=N（NPC 数量，默认 8，0 = 不要）

const Globals := preload("res://addons/pixel_world/core/pw_globals.gd")
const Mats := preload("res://addons/pixel_world/core/pw_materials.gd")
const PixelDisplay := preload("res://addons/pixel_world/render/pw_pixel_display.gd")
const TimeOfDay := preload("res://addons/pixel_world/weather/pw_time_of_day.gd")
const Weather := preload("res://addons/pixel_world/weather/pw_weather_system.gd")
const CameraRig := preload("res://addons/pixel_world/render/pw_camera_rig.gd")
const PostFX := preload("res://addons/pixel_world/render/pw_post_fx.gd")
const DemoUI := preload("res://demo/demo_ui.gd")

var display: PWPixelDisplay
var tod: PWTimeOfDay
var weather: PWWeatherSystem
var rig: PWCameraRig
var post: PWPostFX
var world: PWWorld
var player: PWCharacter
var npcs: Array[PWNPC] = []
var nav: PWNavGrid
## 玩家用的像素精灵角色（没生成精灵表时自动退回低模身体）
var player_sprite := "mercenary"  # 玩家：佣兵队长（参考 res/ex.png 的大致特征做的原创角色）
## 走路模式：WASD 控制角色、镜头跟随
var walk_mode := true:
	set(v):
		walk_mode = v
		if rig != null:
			rig.keyboard_pan = not v
var _dragging := false
var _auto_walk := Vector3.ZERO


var hub: PWHub
var ui: Node


## 启动：默认先显示主界面（PWHub）；命令行带了场景参数（自动化截图 / 跑分）时直接进场景。
## --hub 强制显示主界面，--hubpage=generator|assets|effects|lighting|about 选页（截图用）。
func _ready() -> void:
	Globals.ensure_runtime()
	var args := _args()
	var direct := false
	for k in ["theme", "seed", "weather", "hour", "player", "focus", "bench", "seq", "diffshot", "walk"]:
		if args.has(k):
			direct = true
	if args.has("hub"):
		direct = false
	if direct:
		_start_scene({"theme": args.get("theme", "town"), "seed": int(args.get("seed", "7")),
			"size": int(args.get("size", str(PWStyles.get_style(args.get("theme", "town")).size)))})
		_apply_cmdline()
	else:
		_show_hub(args.get("hubpage", "generator"))
		if args.has("screenshot"):
			_hub_screenshot(args)


func _show_hub(page := "generator") -> void:
	hub = PWHub.new()
	hub.name = "Hub"
	add_child(hub)
	hub.enter_scene.connect(func(cfg: Dictionary):
		hub.queue_free()
		hub = null
		_start_scene(cfg))
	hub.show_page(page)


func _hub_screenshot(args: Dictionary) -> void:
	if args.has("hubstyle"):  # --hubstyle=forest：场景生成器选中某个风格
		hub._select_style(args["hubstyle"])
	if args.get("hubpage", "") == "generator" and args.has("hubpreview"):
		await hub._preview_world()
	if args.has("hubcat"):  # --hubcat=N：资源库选第 N 个分类（9 = Blender 资产）
		hub._select_category(int(args["hubcat"]))
	if args.has("hubitem"):  # --hubitem=N：资源库选当前分类的第 N 个资源
		hub._item_list.select(int(args["hubitem"]))
		hub._select_item(hub._asset_items[int(args["hubitem"])])
	if args.has("hubfx"):  # --hubfx=分类:序号,分类:序号…：特效库依次切换（每次间隔 40 帧），检查切换是否正常
		for step: String in (args["hubfx"] as String).split(","):
			var kv := step.split(":")
			hub._select_fx_category(kv[0])
			hub._fx_list.select(int(kv[1]))
			hub._select_fx(hub._fx_items[int(kv[1])])
			for i in 40:
				await get_tree().process_frame
	for i in int(args.get("frames", "90")):
		await get_tree().process_frame
	if args.has("fxt"):  # --fxt=秒：重新播放当前动作特效，过这么多秒后截图（看特效某一时刻）
		hub._play_fx()
		await get_tree().create_timer(float(args["fxt"])).timeout
	get_viewport().get_texture().get_image().save_png(args["screenshot"])
	print("screenshot saved: ", args["screenshot"])
	get_tree().quit()


## 回到主界面：拆掉整个场景
func back_to_hub() -> void:
	if display != null:
		display.queue_free()
	if ui != null:
		ui.queue_free()
	display = null
	ui = null
	world = null
	player = null
	npcs.clear()
	tod = null
	weather = null
	rig = null
	post = null
	_show_hub()


func _start_scene(cfg: Dictionary) -> void:
	display = PixelDisplay.new()
	add_child(display)
	var vp := display.viewport

	world = PWWorld.new()
	world.name = "World"
	world.generate_on_ready = false
	PWHub.apply_config(world, cfg)
	vp.add_child(world)
	world.generate()

	player = PWCharacter.new()
	player.name = "Player"
	if not _args().has("model3d"):
		player.sprite_id = player_sprite
	player.ground_height = world.ground_y
	player.can_stand = world.can_stand
	player.water_depth = world.water_depth
	vp.add_child(player)

	tod = TimeOfDay.new()
	tod.name = "TimeOfDay"
	vp.add_child(tod)
	weather = Weather.new()
	weather.name = "WeatherSystem"
	weather.time_of_day = tod
	vp.add_child(weather)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	rig.min_distance = 6.0
	rig.distance = 22.0
	rig.keyboard_pan = not walk_mode
	vp.add_child(rig)
	post = PostFX.new()
	vp.add_child(post)
	_after_generate()

	ui = DemoUI.new()
	ui.setup(self)
	add_child(ui)


func _args() -> Dictionary:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	return args


## 换主题 / 换种子重新生成（控制面板调用）
func regenerate(theme := "", new_seed := -1) -> void:
	if theme != "":
		world.theme = theme
		world.size = PWStyles.get_style(theme).size
	if new_seed >= 0:
		world.seed_value = new_seed
	world.generate()
	_after_generate()


## 角色放到出生点，镜头对过去；鱼群认识玩家；风格自带天气（雪原 = 下雪、积雪）
func _after_generate() -> void:
	var st := PWStyles.get_style(world.theme)
	if st.has("weather") and weather != null:
		weather.set_weather(st.weather, 0.0, true)
	player.position = world.spawn_point
	player.velocity = Vector3.ZERO
	rig.position = player.position  # 注视点跟人物同高（峡谷台地、山坡上镜头不会钻进地里）
	rig.bounds = Rect2(-world.size * 0.5, -world.size * 0.5, world.size, world.size)
	if world.fish != null:
		world.fish.threat = player
	_spawn_npcs(int(_args().get("npcs", "8")))


## NPC：每个家（房门口 / 营地）最多住一个，角色轮流用精灵表里除玩家以外的那些
func _spawn_npcs(count: int) -> void:
	for n in npcs:
		if is_instance_valid(n):
			n.queue_free()
	npcs.clear()
	var ids: Array[String] = []
	for c: Dictionary in PWSpriteVisual.characters():
		if c.id != player_sprite:
			ids.append(c.id)
	if ids.is_empty() or world.homes.is_empty() or count <= 0:
		return
	# 寻路网格：整个场景 1 米一格，所有 NPC 共用
	nav = PWNavGrid.new()
	nav.build(Rect2(-world.size * 0.5, -world.size * 0.5, world.size, world.size), world.can_stand)
	var rng := RandomNumberGenerator.new()
	rng.seed = world.seed_value
	var homes := world.homes.duplicate()
	for i in homes.size():  # 洗牌，挑前 count 个
		var j := rng.randi_range(i, homes.size() - 1)
		var t: Vector3 = homes[i]
		homes[i] = homes[j]
		homes[j] = t
	for i in mini(count, homes.size()):
		var npc := PWNPC.new()
		npc.name = "NPC_%d" % i
		npc.sprite_id = ids[i % ids.size()]
		npc.home = homes[i]
		npc.wake_hour = rng.randf_range(6.0, 8.5)
		npc.sleep_hour = rng.randf_range(18.5, 21.0)
		npc.ground_height = world.ground_y
		npc.can_stand = world.can_stand
		npc.water_depth = world.water_depth
		npc.hour = func() -> float: return tod.hour if tod != null else 12.0
		npc.nav = nav
		npc.player = player
		display.viewport.add_child(npc)
		npcs.append(npc)


func _apply_cmdline() -> void:
	var args := _args()
	if args.has("hour"):
		tod.hour = float(args["hour"])
		tod.running = false
	if args.has("weather"):
		weather.set_weather(args["weather"], 0.0, args.has("snap"))
	if args.has("snow"):  # --snow=0..1：直接设定积雪量（看积雪过程）
		weather.snow_amount = float(args["snow"])
	if args.has("wet"):
		weather.wetness = float(args["wet"])
	if args.has("noaa"):  # 调试：贴图改回最近邻采样（对比移动时的闪烁）
		for m: ShaderMaterial in Mats._cache.values():
			m.set_shader_parameter("pixel_aa", false)
	if args.has("nopost"):  # 调试：关闭全屏后期
		post.visible = false
	if args.has("noglow"):
		tod.auto_glow = false
		tod.environment.glow_enabled = false
	if args.has("nomsaa"):
		display.viewport.msaa_3d = Viewport.MSAA_DISABLED
	if args.has("shadowstep"):  # 调试：太阳方向更新间隔（游戏分钟），0 = 每帧连续转动
		tod.shadow_step_minutes = float(args["shadowstep"])
	if args.has("shadownear"):  # 调试：第一级阴影覆盖到镜头距离的多少倍
		tod.shadow_near_factor = float(args["shadownear"])
	if args.has("noshadow"):  # 调试：关闭太阳阴影
		tod.sun.shadow_enabled = false
	if args.has("shadowmode"):  # 调试：ortho / 2 / 4
		var m: String = args["shadowmode"]
		tod.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if m == "ortho" \
			else (DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if m == "4" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	if args.has("shadowblur"):
		tod.sun.shadow_blur = float(args["shadowblur"])
	if args.has("shadowsoft"):  # 调试：软阴影质量 0..5
		RenderingServer.directional_soft_shadow_filter_set_quality(int(args["shadowsoft"]))
	if args.has("pixel"):
		display.pixel_mode = true
	if args.has("nopixel"):  # 关闭全像素风（原生分辨率 + MSAA）
		display.pixel_mode = false
	if args.has("tilt"):
		post.tilt_shift = true
	if args.has("yaw"):
		rig.yaw_deg = float(args["yaw"])
	if args.has("distance"):
		rig.distance = float(args["distance"])
	if args.has("pitch"):  # --pitch=度：镜头俯角（看地形起伏用低一点的角度）
		rig.pitch_deg = float(args["pitch"])
	if args.has("noui"):  # --noui：隐藏界面（截图看画面用）
		for c in get_children():
			if c is CanvasLayer or (c is Control and c != display):
				c.visible = false
	if args.has("player"):
		var pz: PackedStringArray = args["player"].split(",")
		player.position = Vector3(float(pz[0]), world.ground_y(float(pz[0]), float(pz[1])), float(pz[1]))
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
		var pan := Vector3.ZERO
		if args.has("pan"):  # --pan=dx,dz：两次截图之间把镜头平移这么多（检查移动时的闪烁）
			var pp: PackedStringArray = args["pan"].split(",")
			pan = Vector3(float(pp[0]), 0.0, float(pp[1]))
		await _diff_shot(args["diffshot"], int(args.get("frames", "90")), int(args.get("gap", "20")), pan)
		get_tree().quit()
		return
	if args.has("seq"):  # --seq=前缀 --seqn=N：连续截 N 帧（隐藏 UI），逐帧检查闪烁
		for c in get_children():
			if c is CanvasLayer or (c is Control and c != display):
				c.visible = false
		for i in int(args.get("frames", "90")):
			await get_tree().process_frame
		var t0 := tod.hour
		var fixed := args.has("seqfixed")  # 按真实 60 FPS 的时间步长推进游戏时间（不受存图快慢影响）
		if fixed:
			tod.running = false
		for i in int(args.get("seqn", "6")):
			for g in int(args.get("seqgap", "1")):  # --seqgap=N：每隔 N 帧截一张
				if fixed:
					tod.hour += (1.0 / 60.0) * 24.0 / tod.day_length_seconds
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [args["seq"], i])
		print("seq game-minutes elapsed: %.2f" % ((tod.hour - t0) * 60.0))
		print("seq saved: ", args["seq"])
		get_tree().quit()
		return
	if args.has("bench"):
		await _bench(int(args["bench"]))
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


## 性能跑分：关闭垂直同步，角色沿路走动（镜头跟随），测平均帧时间 / 帧率和渲染统计。
## 用法：godot --path godot -- --bench=600 [--weather=rain --snap]
func _bench(frames: int) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if _auto_walk == Vector3.ZERO:
		_auto_walk = Vector3(0.15, 0.0, 1.0)  # 沿土路往湖边走
	var vp_rid := display.viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	for i in 60:
		await get_tree().process_frame
	var times := PackedFloat32Array()
	var cpu_ms := 0.0
	var gpu_ms := 0.0
	var proc_ms := 0.0
	var last := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu()
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		proc_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	print("BENCH render_cpu=%.2fms render_gpu=%.2fms script_process=%.2fms" % [cpu_ms / frames, gpu_ms / frames, proc_ms / frames])
	var sorted := times.duplicate()
	sorted.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= times.size()
	var p95: float = sorted[int(sorted.size() * 0.95)]
	print("BENCH frames=%d avg=%.2fms fps=%.1f p95=%.2fms draw_calls=%d objects=%d primitives=%d vram=%.0fMB" % [
		frames, avg, 1000.0 / avg, p95,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])


## 画面稳定性检查：隔 gap 帧截两张图（隐藏 UI），把变化的像素标成洋红色保存，并打印变化比例。
## 静止镜头下变化越少越好（雨雪粒子、水面波光属于正常变化）。
## pan 非零时，两次截图之间把镜头平移 pan：平移不到 1 个屏幕像素时，变化越少说明移动时越不闪。
func _diff_shot(path: String, frames: int, gap: int, pan := Vector3.ZERO) -> void:
	for c in get_children():
		if c is CanvasLayer or (c is Control and c != display):
			c.visible = false
	for i in frames:
		await get_tree().process_frame
	var a := get_viewport().get_texture().get_image()
	rig.position += pan
	for i in gap:
		await get_tree().process_frame
	var b := get_viewport().get_texture().get_image()
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var da := a.get_data()
	var db := b.get_data()
	var changed := 0
	var popped := 0  # 大幅突变（像素整格翻转）的数量：闪烁的主要来源
	var total := 0
	for i in range(0, da.size(), 3):
		var d := absi(da[i] - db[i]) + absi(da[i + 1] - db[i + 1]) + absi(da[i + 2] - db[i + 2])
		total += d
		if d > 150:
			popped += 1
		if d > 24:
			changed += 1
			db[i] = 255
			db[i + 1] = 0
			db[i + 2] = 255
	var n := da.size() / 3
	var out := Image.create_from_data(b.get_width(), b.get_height(), false, Image.FORMAT_RGB8, db)
	out.save_png(path)
	print("diff saved: %s  changed=%d (%.2f%%)  popped=%.2f%%  mean=%.2f" % [
		path, changed, 100.0 * changed / n, 100.0 * popped / n, float(total) / n])


## 走路模式：WASD / 方向键按镜头方向移动角色，镜头平滑跟随
func _process(delta: float) -> void:
	if player == null or rig == null:
		return  # 在主界面
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
	var running := walk_mode and Input.is_physical_key_pressed(KEY_SHIFT)
	player.walk(dir, delta, running)
	if walk_mode:
		rig.position = rig.position.lerp(player.position, 1.0 - exp(-delta * 4.0))
	# 阴影范围和级联跟着镜头距离走：画面主体落在高精度的第一级（性能 + 画质 + 细阴影稳定）
	tod.fit_shadows(rig.distance)


func _unhandled_input(event: InputEvent) -> void:
	if rig == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and player != null and walk_mode:
		match (event as InputEventKey).physical_keycode:
			KEY_J:
				player_action("attack")
			KEY_K:
				player_action("cast")
			KEY_H:
				player_action("hit")
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


## 玩家动作 + 配套特效：攻击在出刀那一刻放斩击，施法放魔法阵，受击闪白 + 火花
func player_action(a: String) -> void:
	if player.is_busy():
		return
	var fwd := player.global_transform.basis.z
	var root := display.viewport
	match a:
		"attack":
			if player.attack() > 0.0:
				get_tree().create_timer(0.12).timeout.connect(func():
					if is_instance_valid(player):
						PWVFX.spawn("slash", root, player.global_position, player.global_transform.basis.z))
		"cast":
			if player.cast() > 0.0:
				PWVFX.spawn("magic_circle", root, player.global_position, fwd)
		"hit":
			if player.hurt() > 0.0:
				PWVFX.spawn("hit", root, player.global_position + fwd * 0.3, fwd)
