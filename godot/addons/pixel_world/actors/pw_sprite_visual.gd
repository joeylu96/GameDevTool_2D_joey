@tool
class_name PWSpriteVisual
extends MeshInstance3D
## HD-2D 像素角色的显示部分：一块 Y 轴公告板，播放 Blender 渲染好的 8 方向精灵表（tools/blender_build_sprites.py）。
##
##   var v := PWSpriteVisual.create("swordsman")   # 角色 id 见 res://assets/sprites/catalog.json
##   v.anim = "walk"; v.rate = 1.0                  # 每帧自己推进动画
## 方向：按父节点的朝向（局部 +Z 为正面，和 PWCharacter 一致）和当前镜头的夹角，选 8 行里的一行。
## demo = true 时自己在「待机 ↔ 原地走路」之间切换（资源库预览用）。

const DIR := "res://assets/sprites/"
const SHADER := preload("res://addons/pixel_world/shaders/sprite.gdshader")

static var _catalog: Dictionary = {}

var character_id := ""
var anim := "idle"
var rate := 1.0
var demo := false
var _mat: ShaderMaterial
var _t := 0.0
var _demo_t := 0.0
var _cur_anim := ""


## 读精灵目录（只读一次）。没有生成过精灵时返回空字典
static func catalog() -> Dictionary:
	if _catalog.is_empty() and FileAccess.file_exists(DIR + "catalog.json"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "catalog.json"))
		if data is Dictionary:
			_catalog = data
	return _catalog


static func characters() -> Array:
	return catalog().get("characters", [])


static func has_character(id: String) -> bool:
	for c: Dictionary in characters():
		if c.id == id:
			return true
	return false


static func create(id: String) -> PWSpriteVisual:
	var v := PWSpriteVisual.new()
	v.name = "Sprite"
	if not v.setup(id):
		push_warning("PWSpriteVisual: 没有角色 %s（先运行 tools/blender_build_sprites.py）" % id)
	return v


func setup(id: String) -> bool:
	var cat := catalog()
	var entry: Dictionary = {}
	for c: Dictionary in cat.get("characters", []):
		if c.id == id:
			entry = c
	if entry.is_empty() or not ResourceLoader.exists(DIR + entry.file):
		return false
	character_id = id
	var tex: Texture2D = load(DIR + entry.file)
	var f: float = cat.frame
	var ppm: float = cat.px_per_m
	var cols := 0
	for a: Dictionary in (cat.anims as Dictionary).values():
		cols = maxi(cols, int(a.start) + int(a.count))
	var q := QuadMesh.new()
	q.size = Vector2(f / ppm, f / ppm)
	# 脚底（精灵表里的 origin 像素）对准节点原点
	q.center_offset = Vector3(0, (float(cat.origin[1]) - f * 0.5) / ppm, 0)
	mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("sheet", tex)
	_mat.set_shader_parameter("grid", Vector2(cols, int(cat.dirs)))
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# 公告板会转向镜头，包围盒放大一点，避免边缘被视锥剔除
	extra_cull_margin = 1.0
	return true


func _process(delta: float) -> void:
	if _mat == null:
		return
	if demo:
		_demo_t = fmod(_demo_t + delta, 6.0)
		anim = "idle" if _demo_t < 2.5 else "walk"
	var cat := catalog()
	var anims: Dictionary = cat.anims
	if not anims.has(anim):
		anim = "idle"
	if anim != _cur_anim:
		_cur_anim = anim
		_t = 0.0
	_t += delta * rate
	var a: Dictionary = anims[anim]
	var frame := int(a.start) + int(floor(_t * float(a.fps))) % int(a.count)
	_mat.set_shader_parameter("cell", Vector2(frame, _view_dir()))


## 镜头在角色的哪个方位：0 = 正面，逆时针（俯视）每 45° 一行
func _view_dir() -> int:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return 0
	var to_cam := cam.global_position - global_position
	to_cam.y = 0.0
	var fwd := global_transform.basis.z
	fwd.y = 0.0
	if to_cam.length_squared() < 1e-6 or fwd.length_squared() < 1e-6:
		return 0
	var ang := fwd.signed_angle_to(to_cam, Vector3.UP)
	var n: int = catalog().get("dirs", 8)
	return wrapi(roundi(ang / (TAU / n)), 0, n)


func set_flash(v: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("flash", v)
