@tool
class_name PWPixelDisplay
extends SubViewportContainer
## 3D 渲染容器。默认按原生分辨率渲染（4x MSAA）；开启 pixel_mode 后以约 pixel_height 的
## 低分辨率渲染，再整数倍、最近邻放大，得到复古的「真」像素感，对低端设备 / Web 也是很大的性能节省。
## 3D 场景请放到 `viewport` 里（本节点的子 SubViewport）。

const Style := preload("res://addons/pixel_world/style/pw_style_data.gd")

@export var pixel_height := Style.PIXEL_HEIGHT:
	set(v):
		pixel_height = maxi(v, 64)
		_update()
## 开启后以约 pixel_height 的低分辨率渲染再整数倍放大（复古像素感）；
## 关闭（默认）按原生分辨率渲染并开启 4x MSAA，远近都清晰。
@export var pixel_mode := false:
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
		# 至少缩小 2 倍（720p 窗口约 360 行、1080p 540 行、4K 540 行），任何分辨率下都看得出像素感
		s = maxi(2, int(floor(size.y / float(pixel_height))))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_mode else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	viewport.msaa_3d = Viewport.MSAA_DISABLED if pixel_mode else Viewport.MSAA_4X
	if stretch_shrink != s:
		stretch_shrink = s
