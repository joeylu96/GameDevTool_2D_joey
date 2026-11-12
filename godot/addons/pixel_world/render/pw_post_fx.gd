@tool
class_name PWPostFX
extends CanvasLayer
## 全屏后期：移轴景深、阴天去饱和、闪电闪白、暗角。放在 3D 所在的 Viewport 里。

const SHADER := preload("res://addons/pixel_world/shaders/post_fx.gdshader")

## 移轴景深（画面上下边缘模糊，微缩模型感）。默认关闭：远处保持清晰。
@export var tilt_shift := false:
	set(v):
		tilt_shift = v
		_set_param("tilt_shift", v)
@export_range(0.0, 1.0) var focus_center := 0.55:
	set(v):
		focus_center = v
		_set_param("focus_center", v)
@export_range(0.0, 0.5) var focus_width := 0.16:
	set(v):
		focus_width = v
		_set_param("focus_width", v)
@export_range(0.0, 8.0) var blur_px := 2.5:
	set(v):
		blur_px = v
		_set_param("blur_px", v)

var _rect: ColorRect


func _ready() -> void:
	layer = 1
	_rect = ColorRect.new()
	_rect.name = "PostFX"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	_rect.material = m
	add_child(_rect)
	for p in ["tilt_shift", "focus_center", "focus_width", "blur_px"]:
		_set_param(p, get(p))


func _set_param(p: String, v: Variant) -> void:
	if _rect != null:
		(_rect.material as ShaderMaterial).set_shader_parameter(p, v)
