@tool
class_name PWPixelDisplay
extends SubViewportContainer
## 3D 渲染容器。默认是全像素风（pixel_mode）：低分辨率渲染、关掉抗锯齿，再整数倍最近邻放大，
## 场景、贴图、人物精灵都落在同一套像素网格上。
## 缩放倍数按镜头距离自动选：让 1 个渲染像素 ≈ 1 个人物精灵像素（64 像素/米，正好是场景贴图 32 texel/米的两倍，
## 贴图一个像素 = 2×2 渲染像素，整数对齐），人物的细节不丢，拉远也不会糊成大块。
## 防闪烁：镜头位置对齐到渲染像素网格（PWCameraRig.pixel_snap_m），不到 1 像素的余量用整个画面的平移补上，
## 镜头移动时画面平滑、静止的东西不会一闪一闪地「爬像素」。
## 关闭 pixel_mode 则按原生分辨率渲染并开启 4x MSAA。
## 3D 场景请放到 `viewport` 里（本节点的子 SubViewport）。

const Style := preload("res://addons/pixel_world/style/pw_style_data.gd")
## 人物精灵的像素密度（tools/blender_build_sprites.py 的 PX_PER_M）
const SPRITE_DENSITY := 64.0

@export var pixel_height := Style.PIXEL_HEIGHT:
	set(v):
		pixel_height = maxi(v, 64)
		_update()
## 全像素风（默认开启）。pixel_height 只在找不到 PWCameraRig 时用来估算缩放倍数
@export var pixel_mode := true:
	set(v):
		pixel_mode = v
		_update()

var viewport: SubViewport
var _rig: Node = null
var _offset := Vector2.ZERO


func _init() -> void:
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.handle_input_locally = false
	viewport.audio_listener_enable_3d = true
	add_child(viewport)


func _ready() -> void:
	process_priority = 200  # 在镜头（PWCameraRig，100）对齐之后读它的 snap_offset，同一帧里画面平移和镜头对齐配套
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_update)
	_update()


## 当前每个渲染像素放大的倍数
func get_scale_factor() -> int:
	return stretch_shrink


func _process(_delta: float) -> void:
	if pixel_mode:
		_update()
		_snap()


## 镜头对准的地面上，一个渲染像素是多少米 → 告诉镜头按这个网格对齐；镜头挪掉的零头（渲染像素）用画面平移补回
func _snap() -> void:
	var rig := _find_rig()
	if rig == null:
		return
	var rows := float(viewport.size.y)
	rig.pixel_snap_m = 2.0 * float(rig.distance) * tan(deg_to_rad(float(rig.fov)) * 0.5) / maxf(rows, 1.0)
	var off: Vector2 = rig.snap_offset * float(stretch_shrink)
	if not off.is_equal_approx(_offset):
		_offset = off
		_apply_offsets()


func _find_rig() -> Node:
	if _rig != null and is_instance_valid(_rig) and _rig.is_inside_tree():
		return _rig
	_rig = null
	var cam := viewport.get_camera_3d()
	if cam != null and cam.get_parent() is PWCameraRig:
		_rig = cam.get_parent()
	return _rig


func _apply_offsets() -> void:
	# 四周各多出 1 个渲染像素，平移时边上不会露出空白
	var m := float(stretch_shrink) if pixel_mode else 0.0
	offset_left = -m + _offset.x
	offset_right = m + _offset.x
	offset_top = -m - _offset.y
	offset_bottom = m - _offset.y


func _update() -> void:
	if not is_inside_tree():
		return
	var s := 1
	if pixel_mode:
		# 1 个渲染像素 ≈ 1 个精灵像素：屏幕高度 ÷（画面纵向能看到多少米 × 64），四舍五入取整
		var rig := _find_rig()
		var rows_wanted := float(pixel_height)
		if rig != null:
			rows_wanted = 2.0 * float(rig.distance) * tan(deg_to_rad(float(rig.fov)) * 0.5) * SPRITE_DENSITY
		s = maxi(1, roundi(size.y / maxf(rows_wanted, 1.0)))
	else:
		var rig := _find_rig()
		if rig != null:
			rig.pixel_snap_m = 0.0
		if _offset != Vector2.ZERO:
			_offset = Vector2.ZERO
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_mode else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	viewport.msaa_3d = Viewport.MSAA_DISABLED if pixel_mode else Viewport.MSAA_4X
	if stretch_shrink != s:
		stretch_shrink = s
		_apply_offsets()
