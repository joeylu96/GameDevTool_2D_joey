@tool
class_name PWPreview
extends SubViewportContainer
## 3D 预览窗：独立的小世界（自己的光照、地面），鼠标左键拖动旋转、滚轮缩放。
## 用法：set_content(node, radius) 放入要看的东西；with_weather = true 时内置昼夜和天气（特效库、天气光照用）。

var viewport: SubViewport
var root: Node3D
var pivot: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var env: WorldEnvironment
var tod: PWTimeOfDay
var weather: PWWeatherSystem
var yaw := 35.0
var pitch := 32.0
var distance := 10.0
var auto_rotate := true
var _content: Node3D
var _drag := false


func _init(with_weather := false) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	camera.far = 500.0
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
		# 圆形草地展台
		var ground := MeshInstance3D.new()
		var mb := preload("res://addons/pixel_world/core/pw_mesh_builder.gd").new()
		mb.ngon_frustum("grass", Vector3.ZERO, -0.3, 0.0, 30.0, 30.0, 24, 0.0, true)
		ground.mesh = mb.commit()
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ground)


func _ready() -> void:
	_update_camera()


func set_content(node: Node3D, radius: float) -> void:
	if _content != null:
		_content.queue_free()
	_content = node
	if node != null:
		root.add_child(node)
	distance = clampf(radius * 3.2, 3.0, 220.0)
	pivot.position = Vector3(0, radius * 0.35, 0)
	_update_camera()


func _process(delta: float) -> void:
	if auto_rotate and not _drag and is_visible_in_tree():
		yaw += delta * 8.0
		_update_camera()
	if sun != null:
		sun.directional_shadow_max_distance = distance * 2.5


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
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = maxf(distance * 0.9, 1.5)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = minf(distance * 1.1, 300.0)
			_update_camera()
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.4
		pitch = clampf(pitch + mm.relative.y * 0.3, 8.0, 85.0)
		_update_camera()
		accept_event()
