@tool
class_name PWPostFX
extends CanvasLayer
## 全屏后期：移轴景深、阴天去饱和、闪电闪白、暗角。放在 3D 所在的 Viewport 里。
## 性能：只有移轴和去饱和需要读取屏幕（整屏拷贝 + 一个全屏 pass），只在用到时才开；
## 暗角（乘法混合）和闪电（普通混合）用不读屏幕的覆盖层实现，结果与原来的单 pass 一致。

const Globals := preload("res://addons/pixel_world/core/pw_globals.gd")
const SHADER := preload("res://addons/pixel_world/shaders/post_fx.gdshader")
const VIGNETTE_SHADER := preload("res://addons/pixel_world/shaders/post_vignette.gdshader")

## 移轴景深（画面上下边缘模糊，微缩模型感）。默认关闭：远处保持清晰。
@export var tilt_shift := false:
	set(v):
		tilt_shift = v
		_set_param("tilt_shift", v)
@export_range(0.0, 1.0) var focus_center := 0.55:
	set(v):
		focus_center = v
		_set_param("focus_center", v)
@export_range(0.0, 0.5) var focus_width := 0.18:
	set(v):
		focus_width = v
		_set_param("focus_width", v)
@export_range(0.0, 8.0) var blur_px := 3.2:
	set(v):
		blur_px = v
		_set_param("blur_px", v)
@export_range(0.0, 1.0) var vignette := 0.22
@export var flash_color := Color(0.88, 0.92, 1.0)
@export_range(0.0, 1.0) var flash_strength := 0.55

var _rect: ColorRect      # 读屏幕：移轴 + 去饱和
var _vignette: ColorRect  # 乘法混合的暗角
var _flash: ColorRect     # 闪电闪白


func _ready() -> void:
	layer = 1
	_rect = _full_rect("PostFX")
	var m := ShaderMaterial.new()
	m.shader = SHADER
	_rect.material = m
	for p in ["tilt_shift", "focus_center", "focus_width", "blur_px"]:
		_set_param(p, get(p))
	_vignette = _full_rect("Vignette")
	var vm := ShaderMaterial.new()
	vm.shader = VIGNETTE_SHADER
	vm.set_shader_parameter("vignette", vignette)
	_vignette.material = vm
	_flash = _full_rect("Flash")
	_flash.visible = false


func _process(_delta: float) -> void:
	if _rect == null:
		return
	var desat: float = Globals.get_param(&"pw_desaturate", 0.0)
	_rect.visible = tilt_shift or desat > 0.001
	var f: float = clampf(float(Globals.get_param(&"pw_flash", 0.0)) * flash_strength, 0.0, 1.0)
	_flash.visible = f > 0.001
	_flash.color = Color(flash_color, f)


func _full_rect(n: String) -> ColorRect:
	var r := ColorRect.new()
	r.name = n
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(r)
	return r


func _set_param(p: String, v: Variant) -> void:
	if _rect != null:
		(_rect.material as ShaderMaterial).set_shader_parameter(p, v)
