@tool
class_name PWWeatherSystem
extends Node3D
## 天气系统：雨 / 雪 / 雷暴 / 雾 / 阴天，平滑过渡。
## - 粒子跟随当前相机的注视点（局部生成，适合大地图）
## - 积雪 / 潮湿随时间累积，写入全局 shader 参数，所有 pixel_world 材质自动响应
## - 自动联动同场景的 PWTimeOfDay（云量、雾、闪电亮度）
##
## 代码用法：weather_system.set_weather("snow", 3.0)

signal weather_changed(id: String)
signal lightning_struck(delay_seconds: float)

const Globals := preload("res://addons/pixel_world/core/pw_globals.gd")
const Preset := preload("res://addons/pixel_world/weather/pw_weather_preset.gd")

const BUILTIN := {
	"clear": {"display_name": "Clear", "cloud": 0.0, "fog": 0.002, "wind": Vector2(0.2, 0.05)},
	"cloudy": {"display_name": "Cloudy", "cloud": 0.65, "fog": 0.006, "wind": Vector2(0.5, 0.1), "desaturate": 0.25},
	"rain": {"display_name": "Rain", "rain": 0.6, "cloud": 0.8, "fog": 0.01, "wind": Vector2(0.6, 0.2),
		"desaturate": 0.35, "snow_target": 0.0, "wet_target": 1.0},
	"storm": {"display_name": "Storm", "rain": 1.0, "cloud": 0.95, "fog": 0.014, "wind": Vector2(1.4, 0.4),
		"desaturate": 0.45, "snow_target": 0.0, "wet_target": 1.0, "lightning": true},
	"snow": {"display_name": "Snow", "snow": 0.55, "cloud": 0.55, "fog": 0.008, "wind": Vector2(0.3, 0.1),
		"desaturate": 0.15, "snow_target": 1.0},
	"blizzard": {"display_name": "Blizzard", "snow": 1.0, "cloud": 0.85, "fog": 0.028, "wind": Vector2(2.2, 0.6),
		"desaturate": 0.4, "snow_target": 1.0},
	"fog": {"display_name": "Fog", "cloud": 0.5, "fog": 0.035, "wind": Vector2(0.05, 0.0),
		"desaturate": 0.35, "wet_target": 0.3},
}

@export var weather := "clear":
	set(v):
		weather = v
		if is_node_ready():
			_begin(v)
@export var transition_time := 5.0
## 积雪/潮湿每秒增加量（满强度时）
@export var accumulate_rate := 0.05
## 积雪融化/变干每秒减少量
@export var melt_rate := 0.02
## 留空则自动查找同级 PWTimeOfDay
@export var time_of_day: Node
@export var custom_presets: Array[Resource] = []
@export var thunder_sound: AudioStream
@export var preview_in_editor := true

@export_group("Particles (Web 预算)")
@export var snow_particles := 5000
@export var rain_particles := 3500
@export var area_half_size := 32.0

var presets := {}
var snow_amount := 0.0
var wetness := 0.0
var flash := 0.0

var _cur := {}
var _from := {}
var _to: Resource
var _t := 1.0
var _dur := 1.0
var _next_duration := -1.0
var _lightning_wait := 5.0
var _snow: GPUParticles3D
var _rain: GPUParticles3D
var _snow_mat: StandardMaterial3D
var _rain_mat: StandardMaterial3D
var _thunder: AudioStreamPlayer
var _last_wind := Vector2(INF, INF)


func _ready() -> void:
	Globals.ensure_runtime()
	for id: String in BUILTIN:
		var p := Preset.new()
		p.id = id
		p.apply_dict(BUILTIN[id])
		presets[id] = p
	for p in custom_presets:
		if p != null:
			presets[p.id] = p
	if time_of_day == null and get_parent() != null:
		for c in get_parent().get_children():
			if c is PWTimeOfDay:
				time_of_day = c
	_make_particles()
	_thunder = AudioStreamPlayer.new()
	add_child(_thunder)
	_to = presets.get(weather, presets["clear"])
	_cur = _values_of(_to)
	_from = _cur.duplicate()
	_t = 1.0


## 切换天气。duration < 0 用默认过渡时间；snap = true 时积雪/潮湿直接到位（截图、读档用）。
func set_weather(id: String, duration := -1.0, snap := false) -> void:
	_next_duration = duration
	weather = id
	if snap and _to != null:
		# 「立刻到位」= 直接跳到这种天气的稳定状态。snow_target < 0 表示「不下雪、慢慢融化」，
		# 稳定状态就是没有雪（以前这里保持原值，导致从雪天切回晴天时积雪一直不消失）
		snow_amount = maxf(_to.snow_target, 0.0)
		wetness = 0.0 if snow_amount > 0.5 else _to.wet_target
		_t = 1.0
		_cur = _values_of(_to)
		# 空中残留的雨雪也一起清掉：不下的那种直接隐藏，下的那种从头开始飘
		if _snow != null:
			_snow.visible = _to.snow > 0.01
			_rain.visible = _to.rain > 0.01
			if _snow.visible:
				_snow.restart()
			if _rain.visible:
				_rain.restart()


func get_preset_ids() -> Array:
	return presets.keys()


func _begin(id: String) -> void:
	if not presets.has(id):
		push_warning("PWWeatherSystem: 未知天气 '%s'" % id)
		return
	_from = _cur.duplicate()
	_to = presets[id]
	_dur = transition_time if _next_duration < 0.0 else _next_duration
	_next_duration = -1.0
	_t = 0.0 if _dur > 0.0 else 1.0
	if _t >= 1.0:
		_cur = _values_of(_to)
	_lightning_wait = randf_range(1.0, 3.0)
	weather_changed.emit(id)


func _values_of(p: Resource) -> Dictionary:
	var d := {}
	for k: String in Preset.NUMERIC:
		d[k] = p.get(k)
	d["wind"] = p.wind
	return d


func _process(delta: float) -> void:
	if _to == null:
		return
	if Engine.is_editor_hint() and not preview_in_editor:
		return

	# 1. 预设插值
	if _t < 1.0:
		_t = minf(1.0, _t + delta / maxf(_dur, 0.001))
		var k := smoothstep(0.0, 1.0, _t)
		for key: String in Preset.NUMERIC:
			_cur[key] = lerpf(_from[key], _to.get(key), k)
		_cur["wind"] = (_from["wind"] as Vector2).lerp(_to.wind, k)

	# 2. 积雪 / 潮湿累积
	if _to.snow_target >= 0.0:
		var rising: bool = _to.snow_target > snow_amount
		var rate: float = accumulate_rate * maxf(_cur["snow"], 0.2) if rising else melt_rate * (1.0 + _cur["rain"] * 3.0)
		snow_amount = move_toward(snow_amount, _to.snow_target, rate * delta)
	var wet_target: float = 0.0 if snow_amount > 0.5 else _to.wet_target
	var wet_rate: float = accumulate_rate * maxf(_cur["rain"], 0.2) if wet_target > wetness else melt_rate
	wetness = move_toward(wetness, wet_target, wet_rate * delta)

	# 3. 粒子
	_update_particles()

	# 4. 闪电
	if _to.lightning and not Engine.is_editor_hint():
		_lightning_wait -= delta
		if _lightning_wait <= 0.0:
			_lightning_wait = randf_range(_to.lightning_interval.x, _to.lightning_interval.y)
			strike_lightning()

	# 5. 输出
	Globals.set_param(&"pw_snow_amount", snow_amount)
	Globals.set_param(&"pw_wetness", wetness)
	Globals.set_param(&"pw_wind", _cur["wind"])
	Globals.set_param(&"pw_flash", flash)
	Globals.set_param(&"pw_desaturate", _cur["desaturate"])
	Globals.set_param(&"pw_rain", _cur["rain"])
	if time_of_day != null:
		time_of_day.cloud_cover = _cur["cloud"]
		time_of_day.fog_density = _cur["fog"]
		time_of_day.flash = flash


## 手动触发一次闪电（雷暴预设会自动随机触发）
func strike_lightning() -> void:
	var delay := randf_range(0.3, 3.0)
	var tw := create_tween()
	tw.tween_property(self, "flash", 1.0, 0.04)
	tw.tween_property(self, "flash", 0.15, 0.08)
	tw.tween_property(self, "flash", 0.8, 0.05)
	tw.tween_property(self, "flash", 0.0, 0.6)
	lightning_struck.emit(delay)
	if thunder_sound != null:
		_thunder.stream = thunder_sound
		get_tree().create_timer(delay).timeout.connect(_thunder.play)


func _make_particles() -> void:
	var aabb := AABB(Vector3(-area_half_size - 10, -40, -area_half_size - 10), Vector3(area_half_size * 2 + 20, 60, area_half_size * 2 + 20))

	# 雪：1~2 像素大小的方块，正好是像素风雪花
	_snow = GPUParticles3D.new()
	_snow.name = "Snow"
	_snow.amount = snow_particles
	_snow.lifetime = 12.0
	_snow.preprocess = 12.0
	_snow.local_coords = false
	_snow.visibility_aabb = aabb
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spm := ParticleProcessMaterial.new()
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spm.emission_box_extents = Vector3(area_half_size, 1.0, area_half_size)
	spm.direction = Vector3(0, -1, 0)
	spm.spread = 10.0
	spm.initial_velocity_min = 1.2
	spm.initial_velocity_max = 2.0
	spm.gravity = Vector3.ZERO
	spm.turbulence_enabled = true
	spm.turbulence_noise_strength = 1.2
	spm.turbulence_noise_scale = 6.0
	spm.turbulence_influence_min = 0.03
	spm.turbulence_influence_max = 0.1
	spm.scale_min = 0.8
	spm.scale_max = 1.6
	_snow.process_material = spm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.07, 0.07)
	_snow_mat = StandardMaterial3D.new()
	_snow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_snow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sq.material = _snow_mat
	_snow.draw_pass_1 = sq
	_snow.emitting = false
	add_child(_snow)

	# 雨：竖直细线
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = rain_particles
	_rain.lifetime = 1.0
	_rain.preprocess = 1.0
	_rain.local_coords = false
	_rain.visibility_aabb = aabb
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rpm := ParticleProcessMaterial.new()
	rpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rpm.emission_box_extents = Vector3(area_half_size, 1.0, area_half_size)
	rpm.direction = Vector3(0, -1, 0)
	rpm.spread = 2.0
	rpm.initial_velocity_min = 20.0
	rpm.initial_velocity_max = 24.0
	rpm.gravity = Vector3.ZERO
	_rain.process_material = rpm
	var rq := QuadMesh.new()
	rq.size = Vector2(0.025, 0.75)
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rq.material = _rain_mat
	_rain.draw_pass_1 = rq
	_rain.emitting = false
	add_child(_rain)


func _focus_point() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return global_position
	var o := cam.global_position
	var f := -cam.global_basis.z
	if f.y < -0.05:
		return o + f * (-o.y / f.y)
	return o + f * 30.0


func _update_particles() -> void:
	var focus := _focus_point()
	_snow.global_position = focus + Vector3(0, 16, 0)
	_rain.global_position = focus + Vector3(0, 14, 0)

	var snow_i: float = _cur["snow"]
	var rain_i: float = _cur["rain"]
	_snow.amount_ratio = clampf(snow_i, 0.0, 1.0)
	_rain.amount_ratio = clampf(rain_i, 0.0, 1.0)
	if _snow.emitting != (snow_i > 0.01):
		_snow.emitting = snow_i > 0.01
	if _rain.emitting != (rain_i > 0.01):
		_rain.emitting = rain_i > 0.01
	if snow_i > 0.01:
		_snow.visible = true
	if rain_i > 0.01:
		_rain.visible = true

	var wind: Vector2 = _cur["wind"]
	if wind.distance_to(_last_wind) > 0.02:
		_last_wind = wind
		(_snow.process_material as ParticleProcessMaterial).direction = Vector3(wind.x * 0.8, -1.0, wind.y * 0.8).normalized()
		(_rain.process_material as ParticleProcessMaterial).direction = Vector3(wind.x * 0.15, -1.0, wind.y * 0.15).normalized()

	# 无光照粒子按当前环境亮度着色，夜里不会「发光」
	var lc: Color = time_of_day.light_level if time_of_day != null else Color.WHITE
	var bright := lc.lerp(Color.WHITE, flash)
	_snow_mat.albedo_color = (Color(0.96, 0.97, 1.0) * bright * 1.3).clamp()
	_rain_mat.albedo_color = Color(minf(0.85 * bright.r * 1.3, 1.0), minf(0.9 * bright.g * 1.3, 1.0), minf(1.0 * bright.b * 1.3, 1.0), 0.75)
