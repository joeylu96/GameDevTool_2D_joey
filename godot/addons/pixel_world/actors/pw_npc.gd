@tool
class_name PWNPC
extends PWCharacter
## 场景里的 NPC（像素精灵角色）：按作息活动——
##   白天（wake_hour..sleep_hour）：在家附近闲逛：沿寻路网格走到一个随机地点，停下来站一会儿，再换个地方
##   玩家走近：转身挥手打招呼（每个 NPC 有冷却，不会一直挥）
##   天黑：沿路走回家门口，进门（隐藏）；第二天起床时间到了再从门口出来
## 场景要提供 hour: Callable -> float（当前钟点）、nav: PWNavGrid（寻路网格，可选，没有就直线走），
## player（可选，用来打招呼），以及父类的 ground_height / can_stand / water_depth。

@export var home := Vector3.ZERO
@export var wander_radius := 10.0
@export var wake_hour := 7.0
@export var sleep_hour := 19.5
@export var greet_distance := 2.6

var hour: Callable
var nav: PWNavGrid
var player: Node3D
var _rng := RandomNumberGenerator.new()
var _state := "idle"  # idle / walk / going_home / asleep / greet
var _path := PackedVector3Array()
var _wait := 0.0
var _stuck := 0.0
var _home_timer := 0.0
var _greet_cd := 0.0
var _greet_t := 0.0
var _resume := "idle"


func _ready() -> void:
	super()
	_rng.seed = hash([name, home])
	walk_speed = _rng.randf_range(1.3, 1.9)
	_wait = _rng.randf_range(0.2, 3.0)
	home = _free_spot_near(home, 3.0)
	_place_at_home()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var h: float = hour.call() if hour.is_valid() else 12.0
	var awake := h >= wake_hour and h < sleep_hour
	_greet_cd = maxf(0.0, _greet_cd - delta)
	if not awake and _state not in ["asleep", "going_home"]:
		_go_home()
	elif awake and _state == "asleep":
		visible = true
		_place_at_home()
		_state = "idle"
		_wait = _rng.randf_range(0.5, 2.5)
	if _state in ["idle", "walk"] and _should_greet():
		_resume = _state
		_state = "greet"
		_greet_t = 0.0
		_greet_cd = _rng.randf_range(12.0, 20.0)
		face(player.global_position - global_position)
		wave()
	match _state:
		"asleep":
			return
		"greet":
			walk(Vector3.ZERO, delta)
			_greet_t += delta
			if _greet_t > 0.75 and _greet_t - delta <= 0.75:
				wave()
			if _greet_t > 1.6:
				_state = _resume
				if _state == "walk" and _path.is_empty():
					_state = "idle"
		"idle":
			walk(Vector3.ZERO, delta)
			_wait -= delta
			if _wait <= 0.0:
				_pick_target()
		"walk", "going_home":
			_follow(delta)


func _should_greet() -> bool:
	if player == null or _greet_cd > 0.0 or not is_instance_valid(player):
		return false
	var d := player.global_position - global_position
	d.y = 0.0
	return d.length() < greet_distance


func _go_home() -> void:
	_state = "going_home"
	_home_timer = 0.0
	_path = _route(home)


func _route(target: Vector3) -> PackedVector3Array:
	if nav != null:
		var p := nav.find_path(position, target)
		if not p.is_empty():
			return p
	return PackedVector3Array([Vector3(target.x, 0.0, target.z)])


func _follow(delta: float) -> void:
	_home_timer += delta
	if _path.is_empty() or (_state == "going_home" and _home_timer > 45.0):
		_arrive()
		return
	var tgt := _path[0]
	var to := tgt - position
	to.y = 0.0
	if to.length() < (0.5 if _path.size() == 1 else 0.7):
		_path.remove_at(0)
		if _path.is_empty():
			_arrive()
		return
	var before := position
	var last := _path.size() == 1
	walk(to.normalized() * (clampf(to.length() / 1.2, 0.35, 1.0) if last else 1.0), delta)
	if before.distance_to(position) < walk_speed * delta * 0.25:
		_stuck += delta
		if _stuck > 1.0:
			_stuck = 0.0
			if _state == "going_home":
				_home_timer += 10.0  # 回家路被挡：多卡几次就直接进门
				_path = _route(home)
			else:
				_pick_target()
	else:
		_stuck = maxf(0.0, _stuck - delta)


func _arrive() -> void:
	walk(Vector3.ZERO, 0.016)
	if _state == "going_home":
		_state = "asleep"
		visible = false
	else:
		_state = "idle"
		_wait = _rng.randf_range(1.5, 5.0)


func _place_at_home() -> void:
	position = home
	if ground_height.is_valid():
		position.y = ground_height.call(home.x, home.z)


func _pick_target() -> void:
	for attempt in 16:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(2.0, wander_radius)
		var p := home + Vector3(cos(a) * r, 0.0, sin(a) * r)
		if _standable(p) and (not water_depth.is_valid() or water_depth.call(p.x, p.z) < 0.05):
			_path = _route(p)
			_state = "walk"
			return
	_wait = 1.0


func _standable(p: Vector3) -> bool:
	if nav != null and not nav.is_walkable(p):
		return false
	return not can_stand.is_valid() or can_stand.call(Vector2(p.x, p.z))


## 家门口可能正好被占（营地中心的篝火、水井）：螺旋向外找一个能站的地方
func _free_spot_near(p: Vector3, max_r: float) -> Vector3:
	if not can_stand.is_valid() or can_stand.call(Vector2(p.x, p.z)):
		return p
	var r := 0.5
	while r <= max_r:
		for k in 12:
			var a := TAU * k / 12.0
			var q := p + Vector3(cos(a) * r, 0.0, sin(a) * r)
			if can_stand.call(Vector2(q.x, q.z)):
				return q
		r += 0.5
	return p
