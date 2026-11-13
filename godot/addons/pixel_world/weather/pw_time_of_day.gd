@tool
class_name PWTimeOfDay
extends Node
## 昼夜循环：驱动太阳/月光、环境光、背景与雾颜色，以及全局参数 pw_night_factor。
## 自动创建内部的 DirectionalLight3D 和 WorldEnvironment。
## 夜晚自动点亮：把 Light3D 节点加入 "pw_night_lights" 组即可（Web 端建议少用实时光源）。

signal hour_changed(hour: int)

const Globals := preload("res://addons/pixel_world/core/pw_globals.gd")

@export_range(0.0, 24.0, 0.01) var hour := 10.0:
	set(v):
		hour = fposmod(v, 24.0)
@export var running := true
## 游戏内一整天对应的现实秒数
@export var day_length_seconds := 300.0
@export var run_in_editor := false

@export_group("Sun")
@export var max_sun_elevation := 60.0
@export var min_sun_elevation := 14.0
@export var sun_azimuth := -30.0
@export var shadows := true
## 太阳方向每隔多少游戏分钟更新一次（默认 1 分钟 ≈ 一天 300 秒时的 0.2 秒现实时间）。
## 每次只挪约 0.17°，影子边缘最多动 1 个像素，看起来仍是连续移动；
## 但阴影贴图不再每帧重新光栅化，细物体（栏杆、灯杆）的影子和树影锯齿不会每帧闪动。
## 0 = 每帧连续转动（不推荐：细阴影会像电流一样抖）。
## 注：不能用两盏光交叉淡入来做平滑过渡——兼容渲染器（含 Web）对带阴影的平行光逐盏叠加，
## 叠加不是线性的，两盏各一半亮度时画面会明显发亮（实测平均差异 69 vs 0.87）。
@export_range(0.0, 30.0, 0.5) var shadow_step_minutes := 1.0
## 辉光（bloom）只在用得到时开启：夜晚（灯光、窗户）、闪电、有积雪（阳光下的雪会发亮）。
## 晴天白天没有超过阈值的像素，关掉画面不变，省掉一组全屏模糊 pass（性能）。
@export var auto_glow := true

## 以下由 WeatherSystem 每帧写入
var cloud_cover := 0.0
var fog_density := 0.002
var flash := 0.0

var night_factor := 0.0
## 当前整体亮度色（给无光照的粒子/特效着色）
var light_level := Color.WHITE
var sun: DirectionalLight3D
var environment: Environment
var _last_hour := -1
var _last_night := -1.0

# 关键帧：时刻, 太阳色, 太阳强度, 环境光色, 环境光强度, 天空/背景色
const KEYS := [
	[0.0, Color("7f93d6"), 0.16, Color("2f3a66"), 0.62, Color("0e1226")],
	[4.5, Color("7f93d6"), 0.16, Color("2f3a66"), 0.62, Color("151b36")],
	[6.0, Color("ffb38a"), 0.45, Color("6d6a8e"), 0.55, Color("e7a894")],
	[8.0, Color("fff1dc"), 0.85, Color("a9b8d8"), 0.55, Color("bcd3ec")],
	[16.0, Color("fff4e2"), 0.85, Color("a9b8d8"), 0.55, Color("bcd3ec")],
	[18.0, Color("ffa36b"), 0.6, Color("8f7491"), 0.55, Color("f0a07a")],
	[19.5, Color("7f8fd8"), 0.18, Color("3a3f6a"), 0.6, Color("27295a")],
	[24.0, Color("7f93d6"), 0.16, Color("2f3a66"), 0.62, Color("0e1226")],
]


func _ready() -> void:
	Globals.ensure_runtime()
	sun = _make_sun("Sun")

	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = environment
	add_child(we)
	_apply()


func _make_sun(n: String) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = n
	l.shadow_enabled = shadows
	# 阴影范围和级联由 fit_shadows() 按镜头距离调整
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	l.directional_shadow_max_distance = 80.0
	l.directional_shadow_split_1 = 0.35
	l.directional_shadow_blend_splits = true
	l.shadow_blur = 1.0
	add_child(l)
	return l


## 第一级阴影覆盖到镜头距离的多少倍。默认 1.35：俯角 40°、FOV 30° 时，画面里的地面离镜头约
## 0.8~1.5 倍镜头距离，所以画面主体都落在精度最高的第一级里。（之前 split 固定 0.35 时，
## 第一级只到 18.8 米，镜头离地 22 米——画面里所有东西都落在粗糙的第二级，细阴影因此抖得厉害。）
var shadow_near_factor := 1.35
var _fit_distance := -1.0


## 按镜头到注视点的距离调整阴影范围和级联分割。镜头距离不变时不做任何事（改动会让阴影重新对齐）。
func fit_shadows(camera_distance: float) -> void:
	if sun == null or absf(camera_distance - _fit_distance) < 0.01:
		return
	_fit_distance = camera_distance
	var max_d := clampf(camera_distance * 1.9 + 12.0, 40.0, 120.0)
	sun.directional_shadow_max_distance = max_d
	sun.directional_shadow_split_1 = clampf(camera_distance * shadow_near_factor / max_d, 0.2, 0.8)


## 某个时刻的太阳（或月亮）方向，返回 rotation_degrees。
## 太阳 5:00-19:00，其余时间同一盏灯当月光（在最暗时切换）
func _sun_rotation(h: float) -> Vector3:
	h = fposmod(h, 24.0)
	var t: float
	if h >= 5.0 and h < 19.0:
		t = (h - 5.0) / 14.0
	else:
		t = fposmod(h - 19.0, 24.0) / 10.0
	var elev := lerpf(min_sun_elevation, max_sun_elevation, sin(t * PI))
	var az := sun_azimuth + lerpf(-70.0, 70.0, t)
	return Vector3(-elev, az, 0.0)


func _process(delta: float) -> void:
	if running and (not Engine.is_editor_hint() or run_in_editor):
		hour = hour + delta * 24.0 / maxf(day_length_seconds, 1.0)
	_apply()


func get_clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]


func _sample(h: float) -> Array:
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if h >= a[0] and h <= b[0]:
			var t: float = (h - a[0]) / (b[0] - a[0])
			return [
				(a[1] as Color).lerp(b[1], t), lerpf(a[2], b[2], t),
				(a[3] as Color).lerp(b[3], t), lerpf(a[4], b[4], t),
				(a[5] as Color).lerp(b[5], t),
			]
	return KEYS[0].slice(1)


static func _grey(c: Color, amount: float) -> Color:
	var l := c.get_luminance()
	return c.lerp(Color(l, l, l), amount)


func _apply() -> void:
	if sun == null:
		return
	var s := _sample(hour)
	var sun_col: Color = s[0]
	var sun_e: float = s[1]
	var amb: Color = s[2]
	var amb_e: float = s[3]
	var sky: Color = s[4]

	# 方向按 shadow_step_minutes 小步更新（见该参数说明）
	var hs := hour
	if shadow_step_minutes > 0.0:
		hs = floorf(hour * 60.0 / shadow_step_minutes) * shadow_step_minutes / 60.0
	sun.rotation_degrees = _sun_rotation(hs)

	# 云量：削弱直射光、阴影变淡、整体发灰；闪电：瞬间提亮
	var cloud := clampf(cloud_cover, 0.0, 1.0)
	var energy := sun_e * (1.0 - 0.75 * cloud) + flash * 1.6
	sun.light_color = _grey(sun_col, cloud * 0.6)
	sun.shadow_opacity = lerpf(1.0, 0.3, cloud)
	sun.light_energy = energy
	environment.ambient_light_color = _grey(amb, cloud * 0.5)
	environment.ambient_light_energy = amb_e * (1.0 + 0.25 * cloud) + flash * 0.8
	var bg := _grey(sky, cloud * 0.6)
	environment.background_color = bg
	environment.fog_light_color = bg.lerp(environment.ambient_light_color, 0.5)
	environment.fog_density = fog_density

	var sun_h := sin((hour - 6.0) / 12.0 * PI)
	night_factor = maxf(1.0 - smoothstep(-0.05, 0.25, sun_h), cloud * 0.3)
	Globals.set_param(&"pw_night_factor", night_factor)
	if auto_glow:
		environment.glow_enabled = night_factor > 0.005 or flash > 0.001 \
			or float(Globals.get_param(&"pw_snow_amount", 0.0)) > 0.05
	var ll := sun.light_color * energy * 0.5 + environment.ambient_light_color * environment.ambient_light_energy
	light_level = Color(minf(ll.r, 1.0), minf(ll.g, 1.0), minf(ll.b, 1.0))
	Globals.set_param(&"pw_light_color", light_level)
	Globals.set_param(&"pw_sky_color", bg)

	if absf(night_factor - _last_night) > 0.01:
		_last_night = night_factor
		_update_night_lights()
	var hi := int(hour)
	if hi != _last_hour:
		_last_hour = hi
		hour_changed.emit(hi)


func _update_night_lights() -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("pw_night_lights"):
		if n is Light3D:
			if not n.has_meta("pw_base_energy"):
				n.set_meta("pw_base_energy", n.light_energy)
			n.light_energy = n.get_meta("pw_base_energy") * night_factor
			n.visible = night_factor > 0.02
