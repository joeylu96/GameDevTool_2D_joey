@tool
class_name PWSpriteVisual
extends MeshInstance3D
## HD-2D 像素角色的显示部分：一块 Y 轴公告板，播放 Blender 渲染好的 8 方向精灵表（tools/blender_build_sprites.py）。
##
##   var v := PWSpriteVisual.create("swordsman")   # 角色 id 见 res://assets/sprites/catalog.json
##   v.anim = "walk"; v.rate = 1.0                  # 循环动作（待机 / 走路 / 跑步 / 挥手……），每帧自己推进
##   v.play_once("attack")                          # 一次性动作（攻击 / 受击 / 施法），播完回到 anim，发 action_finished
## 每个动作一张精灵表（8 行方向 × N 帧），用到时才加载，显存只花在用到的动作上。
## 方向：按父节点的朝向（局部 +Z 为正面，和 PWCharacter 一致）和当前镜头的夹角，选 8 行里的一行。
## demo = true 时自己轮流播放全部动作（资源库预览用）。

signal action_finished(action: String)

const DIR := "res://assets/sprites/"
const SHADER := preload("res://addons/pixel_world/shaders/sprite.gdshader")

static var _catalog: Dictionary = {}
static var _textures: Dictionary = {}  # 路径 -> Texture2D（同一角色的多个实例共用）

var character_id := ""
var anim := "idle"
var rate := 1.0
var demo := false
var _entry: Dictionary = {}
var _mat: ShaderMaterial
var _t := 0.0
var _cur := ""
var _once := ""
var _demo_i := 0
var _demo_t := 0.0


## 读精灵目录（只读一次）。没有生成过精灵时返回空字典
static func catalog() -> Dictionary:
	if _catalog.is_empty() and FileAccess.file_exists(DIR + "catalog.json"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "catalog.json"))
		if data is Dictionary:
			_catalog = data
	return _catalog


## 重新读目录（资产工坊生成了新角色后调用）
static func reload_catalog() -> void:
	_catalog = {}
	_textures = {}
	catalog()


static func characters() -> Array:
	var out := []
	for c: Dictionary in catalog().get("characters", []):
		if c.has("anims"):
			out.append(c)
	return out


static func has_character(id: String) -> bool:
	return not _find(id).is_empty()


static func _find(id: String) -> Dictionary:
	for c: Dictionary in characters():
		if c.id == id:
			return c
	return {}


static func create(id: String) -> PWSpriteVisual:
	var v := PWSpriteVisual.new()
	v.name = "Sprite"
	if not v.setup(id):
		push_warning("PWSpriteVisual: 没有角色 %s（先运行 tools/blender_build_sprites.py）" % id)
	return v


func setup(id: String) -> bool:
	var cat := catalog()
	_entry = _find(id)
	if _entry.is_empty():
		return false
	character_id = id
	var f: float = cat.frame
	var ppm: float = cat.px_per_m
	var q := QuadMesh.new()
	# 精灵是按 elev_deg 俯角渲染的；公告板竖直，竖向拉长 1/cos(俯角)，从同样的俯角看过去不变形、像素一一对应
	# 竖向拉长 1/cos(游戏镜头俯角)：从那个俯角看过去，精灵的每一行正好是一行屏幕像素（渲染俯角可以更正面一些，脸看得清）
	var stretch := 1.0 / cos(deg_to_rad(float(cat.get("view_pitch_deg", cat.get("elev_deg", 0.0)))))
	q.size = Vector2(f / ppm, f / ppm * stretch)
	# 脚底（精灵表里的 origin 像素）对准节点原点
	q.center_offset = Vector3(0, (float(cat.origin[1]) - f * 0.5) / ppm * stretch, 0)
	mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	extra_cull_margin = 1.0  # 公告板会转向镜头，包围盒放大一点，避免边缘被视锥剔除
	_use("idle")
	return true


func anims() -> PackedStringArray:
	return PackedStringArray((_entry.get("anims", {}) as Dictionary).keys())


func has_anim(a: String) -> bool:
	return (_entry.get("anims", {}) as Dictionary).has(a)


## 播一次动作（攻击 / 受击 / 施法……），播完回到当前的循环动作。返回动作时长（秒），没有这个动作返回 0
func play_once(a: String) -> float:
	if not has_anim(a):
		return 0.0
	_once = a
	_t = 0.0
	_use(a)
	var info: Dictionary = _entry.anims[a]
	return float(info.count) / float(info.fps)


func is_busy() -> bool:
	return _once != ""


func _use(a: String) -> void:
	if a == _cur or not has_anim(a):
		return
	_cur = a
	var info: Dictionary = _entry.anims[a]
	var path: String = DIR + info.file
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	_mat.set_shader_parameter("sheet", _textures[path])
	_mat.set_shader_parameter("grid", Vector2(int(info.count), int(catalog().get("dirs", 8))))


func _process(delta: float) -> void:
	if _mat == null:
		return
	if demo:
		_demo_step(delta)
	var a := _once if _once != "" else anim
	if not has_anim(a):
		a = "idle"
	if _once == "" and a != _cur:
		_t = 0.0
	_use(a)
	_t += delta * (1.0 if _once != "" else rate)
	var info: Dictionary = _entry.anims[a]
	var n := int(info.count)
	var frame := int(floor(_t * float(info.fps)))
	if _once != "":
		if frame >= n:
			var done := _once
			_once = ""
			_t = 0.0
			action_finished.emit(done)
			_use(anim if has_anim(anim) else "idle")
			frame = 0
		frame = mini(frame, n - 1)
	else:
		frame = frame % n
	_mat.set_shader_parameter("cell", Vector2(frame, _view_dir()))


## 资源库预览：依次播放全部动作，每个约 2.5 秒
func _demo_step(delta: float) -> void:
	_demo_t += delta
	if _once != "" or _demo_t < 2.5:
		return
	_demo_t = 0.0
	var list := anims()
	_demo_i = (_demo_i + 1) % list.size()
	var a := list[_demo_i]
	var info: Dictionary = _entry.anims[a]
	if info.get("loop", true):
		anim = a
	else:
		anim = "idle"
		play_once(a)


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
