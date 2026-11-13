@tool
class_name PWNPC
extends PWCharacter
## 场景里的 NPC（像素精灵角色）：按作息活动——
##   白天（wake_hour..sleep_hour）：在家附近闲逛：走一段、停下来站一会儿、再换个地方
##   天黑：走回家门口，进门（隐藏）；第二天起床时间到了再从门口出来
## 没有寻路：直线走，被房子 / 树挡住超过一会儿就换一个目标（回家被挡太久就直接「进门」）。
## 场景要提供 hour: Callable -> float（当前钟点），以及父类的 ground_height / can_stand / water_depth。

@export var home := Vector3.ZERO
@export var wander_radius := 9.0
@export var wake_hour := 7.0
@export var sleep_hour := 19.5

var hour: Callable
var _rng := RandomNumberGenerator.new()
var _state := "idle"  # idle / walk / going_home / asleep
var _target := Vector3.ZERO
var _wait := 0.0
var _stuck := 0.0
var _home_timer := 0.0


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
	if not awake and _state != "asleep" and _state != "going_home":
		_state = "going_home"
		_target = home
		_home_timer = 0.0
	elif awake and _state == "asleep":
		visible = true
		_place_at_home()
		_state = "idle"
		_wait = _rng.randf_range(0.5, 2.5)
	match _state:
		"asleep":
			return
		"idle":
			walk(Vector3.ZERO, delta)
			_wait -= delta
			if _wait <= 0.0:
				_pick_target()
		"walk", "going_home":
			_home_timer += delta
			var to := _target - position
			to.y = 0.0
			if to.length() < 0.5 or (_state == "going_home" and _home_timer > 40.0):
				_arrive()
				return
			var before := position
			# 快到了就放慢（不会一下子刹住）
			walk(to.normalized() * clampf(to.length() / 1.2, 0.35, 1.0), delta)
			if before.distance_to(position) < walk_speed * delta * 0.25:
				_stuck += delta
				if _stuck > 0.8:
					_stuck = 0.0
					if _state == "going_home":
						_home_timer += 8.0  # 回家路被挡：多等几次就直接进门
						_target = home + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
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
			_target = p
			_state = "walk"
			return
	_wait = 1.0


func _standable(p: Vector3) -> bool:
	return not can_stand.is_valid() or can_stand.call(Vector2(p.x, p.z))


## 家门口可能正好被占（营地中心的篝火、水井）：螺旋向外找一个能站的地方
func _free_spot_near(p: Vector3, max_r: float) -> Vector3:
	if _standable(p):
		return p
	var r := 0.5
	while r <= max_r:
		for k in 12:
			var a := TAU * k / 12.0
			var q := p + Vector3(cos(a) * r, 0.0, sin(a) * r)
			if _standable(q):
				return q
		r += 0.5
	return p
