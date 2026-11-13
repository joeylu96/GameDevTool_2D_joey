@tool
class_name PWCharacter
extends Node3D
## 简单的小镇居民：Q 版低模身体（约 1.6 米），程序化走路动画。
## 设置 sprite_id（加入场景前）就换成 HD-2D 像素精灵角色（PWSpriteVisual，8 方向，见 tools/blender_build_sprites.py）。
## 脚步会写入全局涟漪源 pw_step0..3：踩进雨天的水洼或浅水时，shader 会画出向外扩散的波纹。
##
## 用法：每帧调用 walk(dir, delta)，dir 为世界 XZ 方向（长度 0..1，0 = 站着不动）。
## 可选回调（由场景提供）：
##   ground_height(x, z) -> float   脚下高度（浅水里会踩到湖底）
##   can_stand(Vector2) -> bool     这个位置能不能站（房屋、树、深水等返回 false）
##   water_depth(x, z) -> float     这里的水深（>0 时原地站着也会泛起小涟漪）

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")
const Globals := preload("res://addons/pixel_world/core/pw_globals.gd")
const STEP_PARAMS: Array[StringName] = [&"pw_step0", &"pw_step1", &"pw_step2", &"pw_step3"]

@export var walk_speed := 3.2
@export var turn_speed := 10.0
## 像素精灵角色 id（res://assets/sprites/catalog.json）。为空或找不到时用低模身体
@export var sprite_id := ""

var ground_height: Callable
var can_stand: Callable
var water_depth: Callable

var velocity := Vector3.ZERO
var _heading := 0.0
var _phase := 0.0
var _move := 0.0
var _time := 0.0
var _last_side := 0
var _idle_ripple := 0.0
# 脚步涟漪源是全局的 4 个槽（shader 参数 pw_step0..3），所有角色（玩家 + NPC）共用一个环形缓冲，
# 每帧只由第一个更新的角色统一计龄、上传一次，互相不会覆盖
static var _steps: Array[Vector4] = []
static var _step_i := 0
static var _steps_frame := -1

var _body: Node3D
var _head: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _sprite: PWSpriteVisual


func _ready() -> void:
	Globals.ensure_runtime()
	if _steps.is_empty():
		for i in 4:
			_steps.append(Vector4(0, 0, 99, 0))
	_build()


## 让角色朝 dir（世界 XZ，长度 0..1）走一帧
func walk(dir: Vector3, delta: float) -> void:
	_time += delta
	dir.y = 0.0
	velocity = velocity.lerp(dir.limit_length(1.0) * walk_speed, 1.0 - exp(-delta * 10.0))
	var p := position + velocity * delta
	if not _ok(p):
		var px := Vector3(p.x, position.y, position.z)
		var pz := Vector3(position.x, position.y, p.z)
		if _ok(px):
			p = px
			velocity.z = 0.0
		elif _ok(pz):
			p = pz
			velocity.x = 0.0
		else:
			p = position
			velocity = Vector3.ZERO
	position.x = p.x
	position.z = p.z
	if ground_height.is_valid():
		position.y = lerpf(position.y, ground_height.call(p.x, p.z), 1.0 - exp(-delta * 15.0))
	var spd := Vector2(velocity.x, velocity.z).length()
	if spd > 0.15:
		_heading = lerp_angle(_heading, atan2(velocity.x, velocity.z), 1.0 - exp(-delta * turn_speed))
		rotation.y = _heading
	_move = move_toward(_move, clampf(spd / walk_speed, 0.0, 1.0), delta * 4.0)
	_phase += delta * spd * 3.4
	_animate()
	_update_ripples(delta, spd)


func _ok(p: Vector3) -> bool:
	return not can_stand.is_valid() or can_stand.call(Vector2(p.x, p.z))


func _animate() -> void:
	if _sprite != null:
		_sprite.anim = "walk" if _move > 0.15 else "idle"
		_sprite.rate = clampf(_move * walk_speed / 3.2, 0.6, 1.4) if _move > 0.15 else 1.0
		return
	var sw := sin(_phase) * 0.6 * _move
	_leg_l.rotation.x = sw
	_leg_r.rotation.x = -sw
	_arm_l.rotation.x = -sw * 0.8
	_arm_r.rotation.x = sw * 0.8
	_body.position.y = absf(sin(_phase)) * 0.04 * _move + sin(_time * 2.2) * 0.006 * (1.0 - _move)
	_body.rotation.x = 0.07 * _move
	_head.rotation.y = sin(_time * 0.7) * 0.25 * (1.0 - _move)  # 站着时左右张望


## 脚步涟漪：每迈一步记一个源；站在水里时每隔一会儿泛一圈小涟漪
func _update_ripples(delta: float, spd: float) -> void:
	var f := Engine.get_process_frames()
	if f != _steps_frame:
		_steps_frame = f
		for i in 4:
			_steps[i].z += delta
			Globals.set_param(STEP_PARAMS[i], _steps[i])
	if not visible:
		return
	var side := 1 if sin(_phase) > 0.0 else -1
	if _move > 0.3 and side != _last_side:
		_last_side = side
		var foot := global_position + global_transform.basis.x * (0.1 * side)
		_emit(Vector2(foot.x, foot.z), 1.0)
	var depth := 0.0
	if water_depth.is_valid():
		depth = water_depth.call(position.x, position.z)
	if depth > 0.05 and spd < 0.5:
		_idle_ripple -= delta
		if _idle_ripple <= 0.0:
			_idle_ripple = 1.3
			_emit(Vector2(position.x, position.z), 0.6)


func _emit(p: Vector2, strength: float) -> void:
	_steps[_step_i] = Vector4(p.x, p.y, 0.0, strength)
	_step_i = (_step_i + 1) % 4


# ---------------------------------------------------------------- 模型

func _build() -> void:
	if sprite_id != "" and PWSpriteVisual.has_character(sprite_id):
		_sprite = PWSpriteVisual.create(sprite_id)
		add_child(_sprite)
		return
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_body.add_child(_mi(_torso_mesh()))
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 1.02, 0)
	_body.add_child(_head)
	_head.add_child(_mi(_head_mesh()))
	_leg_l = _limb(_leg_mesh(), Vector3(0.1, 0.58, 0), self)
	_leg_r = _limb(_leg_mesh(), Vector3(-0.1, 0.58, 0), self)
	_arm_l = _limb(_arm_mesh(), Vector3(0.27, 0.95, 0), _body)
	_arm_r = _limb(_arm_mesh(), Vector3(-0.27, 0.95, 0), _body)


func _mi(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _limb(mesh: Mesh, pivot: Vector3, parent: Node3D) -> Node3D:
	var n := Node3D.new()
	n.position = pivot
	parent.add_child(n)
	n.add_child(_mi(mesh))
	return n


func _torso_mesh() -> ArrayMesh:
	var mb := MB.new()
	var r := PI / 8.0  # 八边形的一个面正对 +Z
	mb.ngon_frustum("cloth_red", Vector3.ZERO, 0.46, 0.62, 0.26, 0.23, 8, r, false, true)
	mb.ngon_frustum("cloth_red", Vector3.ZERO, 0.62, 0.97, 0.23, 0.19, 8, r, true)
	for y in [0.58, 0.7, 0.82]:
		var z := 0.23 * cos(PI / 8.0) * lerpf(1.0, 0.85, (y - 0.62) / 0.35)
		mb.box("brass", Vector3(-0.02, y, z - 0.01), Vector3(0.02, y + 0.035, z + 0.012))
	# 围巾：一圈 + 垂在胸前的一段
	mb.ngon_frustum("knit", Vector3.ZERO, 0.92, 1.05, 0.2, 0.17, 8, r, true)
	mb.box("knit", Vector3(0.04, 0.66, 0.17), Vector3(0.13, 0.95, 0.21))
	return mb.commit()


func _head_mesh() -> ArrayMesh:
	var mb := MB.new()
	var r := PI / 8.0
	mb.ngon_frustum("skin", Vector3.ZERO, 0.0, 0.07, 0.15, 0.2, 8, r, false, true)
	mb.ngon_frustum("skin", Vector3.ZERO, 0.07, 0.33, 0.2, 0.2, 8, r, false)
	mb.ngon_frustum("skin", Vector3.ZERO, 0.33, 0.4, 0.2, 0.15, 8, r, true)
	var fz := 0.2 * cos(PI / 8.0)
	for sx in [-1.0, 1.0]:
		mb.box("flat_ink", Vector3(sx * 0.05 - 0.016, 0.17, fz - 0.005), Vector3(sx * 0.05 + 0.016, 0.23, fz + 0.01))
		mb.box("flat_red_0", Vector3(sx * 0.055 - 0.022, 0.12, fz - 0.005), Vector3(sx * 0.055 + 0.022, 0.14, fz + 0.006))
	mb.box("flat_skin_1", Vector3(-0.012, 0.14, fz - 0.005), Vector3(0.012, 0.165, fz + 0.02))
	# 头发：后脑 + 刘海
	mb.box("hair", Vector3(-0.2, 0.08, -0.205), Vector3(0.2, 0.36, -0.02))
	mb.box("hair", Vector3(-0.17, 0.29, 0.1), Vector3(0.17, 0.35, fz + 0.012))
	# 毛线帽 + 绒球
	mb.ngon_frustum("knit", Vector3.ZERO, 0.31, 0.46, 0.215, 0.19, 8, r, false, true)
	mb.ngon_frustum("knit", Vector3.ZERO, 0.46, 0.53, 0.19, 0.1, 8, r, true)
	mb.ngon_frustum("flat_frame_0", Vector3.ZERO, 0.52, 0.61, 0.065, 0.05, 6, 0.0, true)
	return mb.commit()


func _leg_mesh() -> ArrayMesh:
	var mb := MB.new()
	mb.box("cloth_dark", Vector3(-0.065, -0.46, -0.07), Vector3(0.065, 0.0, 0.07))
	mb.box("boots", Vector3(-0.075, -0.58, -0.08), Vector3(0.075, -0.44, 0.12))
	return mb.commit()


func _arm_mesh() -> ArrayMesh:
	var mb := MB.new()
	mb.box("cloth_red", Vector3(-0.06, -0.38, -0.06), Vector3(0.06, 0.03, 0.06))
	mb.box("knit", Vector3(-0.055, -0.47, -0.055), Vector3(0.055, -0.37, 0.055))
	return mb.commit()
