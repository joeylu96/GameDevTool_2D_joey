@tool
class_name PWCameraRig
extends Node3D
## 高俯视透视相机（参考图风格）。节点位置 = 注视点。
## 运行时：WASD/方向键平移，Q/E 旋转，滚轮/+- 缩放，鼠标右键或中键拖动平移（需由上层转发，见 pan_pixels）。

const Style := preload("res://addons/pixel_world/style/pw_style_data.gd")

@export_range(15.0, 85.0) var pitch_deg := Style.CAMERA_PITCH_DEG:
	set(v):
		pitch_deg = v
		_update()
@export var yaw_deg := 0.0:
	set(v):
		yaw_deg = v
		_update()
@export var distance := Style.CAMERA_DISTANCE:
	set(v):
		distance = clampf(v, min_distance, max_distance)
		_update()
@export var fov := Style.CAMERA_FOV:
	set(v):
		fov = v
		_update()
@export var min_distance := 15.0
@export var max_distance := 110.0
@export var pan_speed := 16.0
## 注视点活动范围（XZ）
@export var bounds := Rect2(-60, -60, 120, 120)
## WASD / 方向键平移镜头。镜头跟随角色时关闭，把这些键让给角色
@export var keyboard_pan := true

var camera: Camera3D
## 像素对齐：> 0 时镜头位置对齐到这个间距（米，= 对准的地面上一个渲染像素的大小），由 PWPixelDisplay 每帧设置
var pixel_snap_m := 0.0
## 对齐时镜头挪动了多少（渲染像素，x 右、y 上）；PWPixelDisplay 把画面反向平移这么多，看起来仍是平滑移动
var snap_offset := Vector2.ZERO


func _ready() -> void:
	process_priority = 100  # 在跟随角色等移动镜头的逻辑之后再对齐像素
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.far = 400.0
	add_child(camera)
	_update()
	if not Engine.is_editor_hint():
		camera.make_current()


func _update() -> void:
	if camera == null:
		return
	var p := deg_to_rad(pitch_deg)
	var y := deg_to_rad(yaw_deg)
	var off := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * distance
	camera.fov = fov
	camera.transform = Transform3D(Basis.looking_at(-off, Vector3.UP), off)
	_snap()


## 镜头沿自己的右 / 上方向对齐到像素网格：静止的物体每帧都落在同样的渲染像素上，移动镜头时不会闪烁「爬像素」
func _snap() -> void:
	snap_offset = Vector2.ZERO
	if camera == null or pixel_snap_m <= 0.0:
		return
	var b := camera.transform.basis
	var base := global_position + camera.transform.origin
	var a := base.dot(b.x) / pixel_snap_m
	var c := base.dot(b.y) / pixel_snap_m
	var da := roundf(a) - a
	var dc := roundf(c) - c
	camera.position = camera.transform.origin + (b.x * da + b.y * dc) * pixel_snap_m
	snap_offset = Vector2(da, dc)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var mv := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		mv.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		mv.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		mv.y += 1
	if mv != Vector2.ZERO and keyboard_pan:
		move_local(mv.normalized() * pan_speed * delta * (distance / Style.CAMERA_DISTANCE))
	if Input.is_physical_key_pressed(KEY_Q):
		yaw_deg += 60.0 * delta
	if Input.is_physical_key_pressed(KEY_E):
		yaw_deg -= 60.0 * delta
	if Input.is_physical_key_pressed(KEY_EQUAL):
		zoom(1.0 - delta)
	if Input.is_physical_key_pressed(KEY_MINUS):
		zoom(1.0 + delta)
	_update()  # 每帧重新对齐（位置可能被跟随逻辑改过）


## 按屏幕方向平移（x 右，y 下），单位米
func move_local(v: Vector2) -> void:
	var y := deg_to_rad(yaw_deg)
	var right := Vector3(cos(y), 0, -sin(y))
	var down := Vector3(sin(y), 0, cos(y))
	var pos := position + right * v.x + down * v.y
	pos.x = clampf(pos.x, bounds.position.x, bounds.end.x)
	pos.z = clampf(pos.z, bounds.position.y, bounds.end.y)
	position = pos


## 鼠标拖动平移；viewport_height 为屏幕像素高度
func pan_pixels(rel: Vector2, viewport_height: float) -> void:
	var meters_per_px := 2.0 * distance * tan(deg_to_rad(fov) * 0.5) / maxf(viewport_height, 1.0)
	move_local(-rel * meters_per_px * Vector2(1.0, 1.0 / sin(deg_to_rad(pitch_deg))))


func zoom(factor: float) -> void:
	distance = distance * factor
