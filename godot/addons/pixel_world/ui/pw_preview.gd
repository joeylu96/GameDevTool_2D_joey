@tool
class_name PWPreview
extends SubViewportContainer
## 3D 预览窗：独立的小世界（自己的光照、地面）。视角固定不自动旋转，用按键 / 底部按钮控制：
##   ← →（或 A D 以外的左右方向键）旋转     ↑ ↓ 俯仰     + / -（或滚轮）缩放
##   W A S D 平移     R 重置视角     鼠标左键拖动旋转、右键 / 中键拖动平移
## 鼠标在预览窗上（或点过它）时按键才生效，避免和输入框冲突。
## set_content(node, radius, stage)：放入要看的东西；stage = false 时不显示圆形草地展台（预览整个场景时用，
## 展台比水面高，会挡住湖面）。with_weather = true 时内置昼夜和天气（特效库、天气光照用）。

const T := preload("res://addons/pixel_world/ui/pw_ui_theme.gd")

var viewport: SubViewport
var root: Node3D
var pivot: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var env: WorldEnvironment
var tod: PWTimeOfDay
var weather: PWWeatherSystem
var stage: MeshInstance3D
var yaw := 35.0
var pitch := 32.0
var distance := 10.0
var auto_rotate := false
var _content: Node3D
var _drag := 0  # 0 无，1 旋转，2 平移
var _hover := false
var _home := {}


func _init(with_weather := false) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.handle_input_locally = false
	add_child(viewport)
	root = Node3D.new()
	viewport.add_child(root)
	pivot = Node3D.new()
	root.add_child(pivot)
	camera = Camera3D.new()
	camera.fov = 30.0
	camera.far = 600.0
	pivot.add_child(camera)
	if with_weather:
		tod = PWTimeOfDay.new()
		tod.running = false
		tod.hour = 11.0
		root.add_child(tod)
		weather = PWWeatherSystem.new()
		weather.time_of_day = tod
		weather.area_half_size = 14.0
		weather.snow_particles = 1500
		weather.rain_particles = 1200
		root.add_child(weather)
	else:
		sun = DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -35, 0)
		sun.light_energy = 0.9
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 60.0
		root.add_child(sun)
		env = WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.16, 0.18, 0.25)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.66, 0.72, 0.85)
		e.ambient_light_energy = 0.6
		e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.environment = e
		root.add_child(env)
		# 圆形草地展台（看单个资源时用）
		stage = MeshInstance3D.new()
		var mb := preload("res://addons/pixel_world/core/pw_mesh_builder.gd").new()
		mb.ngon_frustum("grass", Vector3.ZERO, -0.3, 0.0, 30.0, 30.0, 24, 0.0, true)
		stage.mesh = mb.commit()
		stage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(stage)
	mouse_entered.connect(func(): _hover = true)
	mouse_exited.connect(func(): _hover = false)


func _ready() -> void:
	_build_controls()
	_update_camera()


## 底部的视角按钮条
func _build_controls() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", T.box(Color(0, 0, 0, 0.5), 6, 6))
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -48
	bar.offset_bottom = -8
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	bar.add_child(h)
	for spec in [["左转", func(): _orbit(-15, 0)], ["右转", func(): _orbit(15, 0)], ["抬高", func(): _orbit(0, 6)],
			["压低", func(): _orbit(0, -6)], ["放大", func(): _zoom(0.85)], ["缩小", func(): _zoom(1.18)], ["重置", reset_view]]:
		var b := T.button(spec[0], spec[1])
		b.add_theme_font_size_override("font_size", 13)
		h.add_child(b)
	var hint := T.label("  ←→ 旋转  ↑↓ 俯仰  +- 缩放  WASD 平移  R 重置", 12, T.TEXT_DIM)
	h.add_child(hint)


func set_content(node: Node3D, radius: float, show_stage := true) -> void:
	if _content != null:
		_content.queue_free()
	_content = node
	if node != null:
		root.add_child(node)
	if stage != null:
		stage.visible = show_stage
	distance = clampf(radius * 3.2, 3.0, 260.0)
	pivot.position = Vector3(0, radius * 0.35, 0)
	_home = {"yaw": yaw, "pitch": pitch, "distance": distance, "pivot": pivot.position}
	_update_camera()


func reset_view() -> void:
	if _home.is_empty():
		return
	yaw = _home.yaw
	pitch = _home.pitch
	distance = _home.distance
	pivot.position = _home.pivot
	_update_camera()


func _orbit(dyaw: float, dpitch: float) -> void:
	yaw += dyaw
	pitch = clampf(pitch + dpitch, 8.0, 85.0)
	_update_camera()


func _zoom(k: float) -> void:
	distance = clampf(distance * k, 1.5, 300.0)
	_update_camera()


## 按屏幕方向平移（x 右，y 下 = 朝镜头），单位米
func _pan(v: Vector2) -> void:
	var y := deg_to_rad(yaw)
	var right := Vector3(cos(y), 0, -sin(y))
	var toward := Vector3(sin(y), 0, cos(y))
	pivot.position += right * v.x + toward * v.y
	_update_camera()


func _process(delta: float) -> void:
	if auto_rotate and _drag == 0 and is_visible_in_tree():
		yaw += delta * 8.0
		_update_camera()
	if sun != null:
		sun.directional_shadow_max_distance = distance * 2.5
	if not is_visible_in_tree() or not (_hover or has_focus()):
		return
	var rot := 0.0
	var tilt := 0.0
	var mv := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT):
		rot -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT):
		rot += 1
	if Input.is_physical_key_pressed(KEY_UP):
		tilt += 1
	if Input.is_physical_key_pressed(KEY_DOWN):
		tilt -= 1
	if Input.is_physical_key_pressed(KEY_A):
		mv.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		mv.x += 1
	if Input.is_physical_key_pressed(KEY_W):
		mv.y -= 1
	if Input.is_physical_key_pressed(KEY_S):
		mv.y += 1
	if rot != 0.0 or tilt != 0.0:
		_orbit(rot * 70.0 * delta, tilt * 40.0 * delta)
	if mv != Vector2.ZERO:
		_pan(mv.normalized() * distance * 0.6 * delta)
	if Input.is_physical_key_pressed(KEY_EQUAL) or Input.is_physical_key_pressed(KEY_KP_ADD):
		_zoom(1.0 - delta * 1.2)
	if Input.is_physical_key_pressed(KEY_MINUS) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT):
		_zoom(1.0 + delta * 1.2)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R \
			and is_visible_in_tree() and (_hover or has_focus()):
		reset_view()


func _update_camera() -> void:
	if camera == null:
		return
	var p := deg_to_rad(pitch)
	var y := deg_to_rad(yaw)
	var off := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * distance
	camera.transform = Transform3D(Basis.looking_at(-off, Vector3.UP), off)
	if tod != null:
		tod.fit_shadows(distance)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = 1 if mb.pressed else 0
			if mb.pressed:
				grab_focus()
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_drag = 2 if mb.pressed else 0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.1)
		accept_event()
	elif event is InputEventMouseMotion and _drag != 0:
		var mm := event as InputEventMouseMotion
		if _drag == 1:
			_orbit(-mm.relative.x * 0.4, mm.relative.y * 0.3)
		else:
			var mpp := 2.0 * distance * tan(deg_to_rad(camera.fov) * 0.5) / maxf(size.y, 1.0)
			_pan(-mm.relative * mpp)
		accept_event()
