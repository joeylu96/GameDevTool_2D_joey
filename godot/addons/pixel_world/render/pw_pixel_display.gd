@tool
class_name PWPixelDisplay
extends SubViewportContainer
## 像素渲染容器：3D 画面先以约 pixel_height 的低分辨率渲染，再整数倍、最近邻放大。
## 贴图像素 ≈ 屏幕像素，得到「真」像素感；对 Web 也是很大的性能节省。
## 3D 场景请放到 `viewport` 里（本节点的子 SubViewport）。

const Style := preload("res://addons/pixel_world/style/pw_style_data.gd")

@export var pixel_height := Style.PIXEL_HEIGHT:
	set(v):
		pixel_height = maxi(v, 64)
		_update()
## 关闭后按原生分辨率渲染（对比用）
@export var pixel_mode := true:
	set(v):
		pixel_mode = v
		_update()

var viewport: SubViewport


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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_update)
	_update()


## 当前每个渲染像素放大的倍数
func get_scale_factor() -> int:
	return stretch_shrink


func _update() -> void:
	if not is_inside_tree():
		return
	var s := 1
	if pixel_mode:
		s = maxi(1, int(floor(size.y / float(pixel_height))))
	if stretch_shrink != s:
		stretch_shrink = s
