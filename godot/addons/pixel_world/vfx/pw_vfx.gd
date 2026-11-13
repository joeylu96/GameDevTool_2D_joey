@tool
class_name PWVFX
extends Node3D
## 动作特效库（战斗 / 技能 / 移动）。每个特效是一个自管理的节点：生成后自己播放、播完自动删除。
##   PWVFX.spawn("slash", parent, position, facing)   —— facing：特效朝向（世界 XZ 方向）
## 特效都只用 CPUParticles3D + 少量网格，Web / 兼容渲染器都能跑；颜色取自调色板，透明度分档，保持像素风。
##
## 分类见 CATALOG：动作（攻击、受击）、技能（法术、治疗、增益）、移动（尘土、落地）。

const MB := preload("res://addons/pixel_world/core/pw_mesh_builder.gd")
const SHADER := preload("res://addons/pixel_world/shaders/vfx.gdshader")
const Pal := preload("res://addons/pixel_world/core/pw_palette.gd")

## 特效清单（特效库界面用）：id、名称、分类、说明
const CATALOG := [
	{"id": "slash", "name": "斩击", "cat": "攻击", "desc": "一道横扫的弧形刀光，扫过后拖出渐隐的尾巴，带几颗火星。"},
	{"id": "slash_x", "name": "十字斩", "cat": "攻击", "desc": "两道交叉的刀光先后扫过。"},
	{"id": "hit", "name": "打击火花", "cat": "受击", "desc": "命中瞬间的白闪 + 向四周迸射的火花。"},
	{"id": "fireball", "name": "火球", "cat": "法术", "desc": "向前飞出的火球拖着火星尾迹，命中后爆炸。"},
	{"id": "explosion", "name": "爆炸", "cat": "法术", "desc": "火球膨胀 + 地面冲击波 + 闪光，随后升起烟尘。"},
	{"id": "lightning", "name": "落雷", "cat": "法术", "desc": "一道折线雷电从天而降，落点迸出电火花。"},
	{"id": "heal", "name": "治疗", "cat": "增益", "desc": "脚下绿色光环，光点螺旋上升。"},
	{"id": "magic_circle", "name": "魔法阵", "cat": "增益", "desc": "地面旋转的符文法阵 + 升起的光柱。"},
	{"id": "shield", "name": "护盾", "cat": "增益", "desc": "半透明的护盾球体闪现后慢慢消散。"},
	{"id": "dust", "name": "冲刺尘土", "cat": "移动", "desc": "冲刺 / 急停时脚下扬起的一团尘土。"},
	{"id": "land", "name": "落地冲击", "cat": "移动", "desc": "从高处落地时向四周扩散的尘土环。"},
]

var duration := 1.0
var _age := 0.0
var _mats: Array[ShaderMaterial] = []
var _tick: Callable  # func(t: float, age: float)


static func spawn(id: String, parent: Node, pos: Vector3, facing := Vector3.FORWARD) -> PWVFX:
	var v := PWVFX.new()
	v.name = "VFX_" + id
	parent.add_child(v)
	v.global_position = pos
	var f := Vector3(facing.x, 0, facing.z)
	if f.length() > 0.01:
		v.basis = Basis.looking_at(f.normalized(), Vector3.UP)  # 局部 -Z 朝向 facing
	v.call("_build_" + id)
	return v


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / duration, 0.0, 1.0)
	for m in _mats:
		m.set_shader_parameter("progress", t)
	if _tick.is_valid():
		_tick.call(t, _age)
	if _age >= duration + 1.5:  # 留出粒子飘散的时间
		queue_free()


# ---------------------------------------------------------------- 工具

## cover：盖住背后的程度（0 纯发光叠加，1 完全不透明）；rim：1 = 中间透明、边缘亮（泡泡）
func _mat(core: Color, edge: Color, mode := 0, intensity := 1.0, cover := 0.35, rim := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("color_core", core)
	m.set_shader_parameter("color_edge", edge)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("cover", cover)
	m.set_shader_parameter("rim", rim)
	_mats.append(m)
	return m


func _mesh(mesh: Mesh, mat: Material, xf := Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## 粒子：小方块（像素点），无光照、叠加发光
func _particles(amount: int, lifetime: float, color: Color, opts := {}) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = opts.get("one_shot", true)
	p.explosiveness = opts.get("explosiveness", 0.9)
	p.local_coords = opts.get("local", false)
	p.emission_shape = opts.get("shape", CPUParticles3D.EMISSION_SHAPE_SPHERE)
	p.emission_sphere_radius = opts.get("radius", 0.1)
	p.emission_ring_radius = opts.get("ring_radius", 1.0)
	p.emission_ring_inner_radius = opts.get("ring_inner", 0.8)
	p.emission_ring_height = 0.05
	p.emission_ring_axis = Vector3.UP
	p.direction = opts.get("dir", Vector3.UP)
	p.spread = opts.get("spread", 180.0)
	p.initial_velocity_min = opts.get("vmin", 1.0)
	p.initial_velocity_max = opts.get("vmax", 3.0)
	p.gravity = opts.get("gravity", Vector3(0, -6, 0))
	p.damping_min = opts.get("damping", 0.0)
	p.damping_max = opts.get("damping", 0.0)
	p.scale_amount_min = opts.get("smin", 0.6)
	p.scale_amount_max = opts.get("smax", 1.2)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color, 0.0))
	if opts.has("color_end"):
		grad.set_color(1, opts.color_end)
	p.color_ramp = grad
	var q := BoxMesh.new()
	var s: float = opts.get("size", 0.06)
	q.size = Vector3(s, s, s)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if opts.get("solid", false) else BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.mesh = q
	p.position = opts.get("pos", Vector3.ZERO)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	return p


## 弧形刀光网格：中心在原点，在 XZ 平面内从 a0 扫到 a1（弧度），半径 r0..r1；UV.x 沿弧，UV.y 沿宽度
static func _arc_mesh(r0: float, r1: float, a0: float, a1: float, segs := 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var b0 := lerpf(a0, a1, t0)
		var b1 := lerpf(a0, a1, t1)
		# 刀光中间宽、两头尖
		var w0 := sin(t0 * PI) * 0.8 + 0.2
		var w1 := sin(t1 * PI) * 0.8 + 0.2
		var rm := (r0 + r1) * 0.5
		var hw := (r1 - r0) * 0.5
		var pts := [
			[Vector3(cos(b0), 0, sin(b0)) * (rm - hw * w0), Vector2(t0, 0)],
			[Vector3(cos(b1), 0, sin(b1)) * (rm - hw * w1), Vector2(t1, 0)],
			[Vector3(cos(b1), 0, sin(b1)) * (rm + hw * w1), Vector2(t1, 1)],
			[Vector3(cos(b0), 0, sin(b0)) * (rm + hw * w0), Vector2(t0, 1)],
		]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(pts[k][1])
			st.add_vertex(pts[k][0])
	return st.commit()


static func _ring_mesh(r: float, w: float, segs := 40) -> ArrayMesh:
	return _arc_mesh(r - w * 0.5, r + w * 0.5, 0.0, TAU, segs)


static func _ball_mesh(r: float) -> Mesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 6
	return s


static func _quad_mesh(size: float) -> Mesh:
	var q := PlaneMesh.new()
	q.size = Vector2(size, size)
	return q


func _flash_light(color: Color, energy: float, range_m: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.position = Vector3(0, 0.8, 0)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)


# ---------------------------------------------------------------- 攻击 / 受击

## 刀光的摆放：弧本来在 XZ 平面，先绕前进轴转 90° 立起来（弧的弦变成竖直、朝 facing 方向鼓出），
## 再绕横轴倾斜 tilt —— 从侧面（镜头方向）看就是一道斜劈的月牙，而不是一条压扁的横线。
static func _slash_xf(tilt: float, center := Vector3(0, 1.0, -0.15)) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, tilt) * Basis(Vector3.BACK, PI * 0.5), center)


func _build_slash() -> void:
	duration = 0.45
	_mesh(_arc_mesh(0.55, 1.05, -PI * 0.88, -PI * 0.12, 32), _mat(Color("fffbf0"), Pal.c("light_1"), 1, 1.3, 0.55), _slash_xf(0.55))
	_particles(16, 0.4, Pal.c("light_0"), {"pos": Vector3(0, 1.0, -0.9), "vmin": 2.0, "vmax": 4.5, "dir": Vector3(0, -0.4, -1), "spread": 45.0, "size": 0.04, "damping": 4.0})


func _build_slash_x() -> void:
	duration = 0.55
	_mesh(_arc_mesh(0.55, 1.05, -PI * 0.88, -PI * 0.12, 32), _mat(Color("f6faff"), Pal.c("water_0"), 1, 1.3, 0.55), _slash_xf(0.65))
	var m2 := _mat(Color("f6faff"), Pal.c("water_0"), 1, 1.3, 0.55)
	var second := _mesh(_arc_mesh(0.55, 1.05, -PI * 0.88, -PI * 0.12, 32), m2, _slash_xf(-0.65))
	second.visible = false
	_mats.erase(m2)
	_tick = func(t: float, age: float) -> void:
		var t2 := clampf((age - 0.18) / 0.35, 0.0, 1.0)
		second.visible = age > 0.18
		m2.set_shader_parameter("progress", t2)
	_particles(14, 0.4, Pal.c("snow_0"), {"pos": Vector3(0, 1.0, -0.9), "vmin": 2.0, "vmax": 5.0, "spread": 70.0, "size": 0.04, "damping": 4.0})


func _build_hit() -> void:
	duration = 0.25
	var flash := _mesh(_ball_mesh(0.22), _mat(Color.WHITE, Pal.c("light_1"), 0, 1.2, 0.6), Transform3D(Basis(), Vector3(0, 1.0, 0)))
	_tick = func(t: float, _age: float) -> void:
		flash.scale = Vector3.ONE * (0.6 + t * 1.2)
	_particles(24, 0.45, Pal.c("light_1"), {"pos": Vector3(0, 1.0, 0), "vmin": 3.0, "vmax": 7.0, "size": 0.05, "damping": 6.0, "gravity": Vector3(0, -9, 0)})
	_particles(10, 0.3, Color.WHITE, {"pos": Vector3(0, 1.0, 0), "vmin": 5.0, "vmax": 9.0, "size": 0.035, "damping": 10.0})


# ---------------------------------------------------------------- 法术

func _build_explosion() -> void:
	duration = 0.7
	var ball := _mesh(_ball_mesh(0.5), _mat(Color("fff0b0"), Color("e8541c"), 0, 1.15, 0.75), Transform3D(Basis(), Vector3(0, 0.6, 0)))
	var ring := _mesh(_ring_mesh(1.0, 0.35), _mat(Pal.c("light_0"), Color("e8541c"), 2, 1.1, 0.5), Transform3D(Basis(), Vector3(0, 0.08, 0)))
	_tick = func(t: float, _age: float) -> void:
		ball.scale = Vector3.ONE * (0.4 + smoothstep(0.0, 0.45, t) * 2.0)
		ring.scale = Vector3.ONE * (0.3 + t * 3.2)
	_flash_light(Pal.c("light_1"), 6.0, 9.0, 0.6)
	_particles(40, 0.9, Pal.c("light_1"), {"pos": Vector3(0, 0.6, 0), "vmin": 3.0, "vmax": 8.0, "size": 0.08, "damping": 4.0, "color_end": Color(Pal.c("red_2"), 0.0)})
	# 烟尘：很多小颗粒（不是大方块），先暖灰后变淡，慢慢上升
	_particles(70, 1.8, Color(Pal.c("stone_1"), 0.55), {"pos": Vector3(0, 0.6, 0), "vmin": 0.6, "vmax": 2.2, "size": 0.09, "gravity": Vector3(0, 0.8, 0),
		"damping": 1.5, "explosiveness": 0.8, "solid": true, "color_end": Color(Pal.c("stone_0"), 0.0), "radius": 0.5})


func _build_fireball() -> void:
	duration = 0.9
	var ball := _mesh(_ball_mesh(0.28), _mat(Color("fff0b0"), Color("e8541c"), 0, 1.2, 0.8), Transform3D(Basis(), Vector3(0, 1.0, -0.6)))
	var trail := _particles(40, 0.35, Pal.c("light_1"), {"one_shot": false, "explosiveness": 0.0, "pos": ball.position, "vmin": 0.2, "vmax": 0.8,
		"size": 0.08, "gravity": Vector3(0, 1.0, 0), "color_end": Color(Pal.c("red_1"), 0.0)})
	var mats := _mats.duplicate()
	_mats.clear()  # 火球飞行时保持实心，不按 progress 淡出
	var exploded := [false]
	_tick = func(t: float, _age: float) -> void:
		var z := -0.6 - t * 5.0
		ball.position.z = z
		trail.position.z = z
		if t >= 1.0 and not exploded[0]:
			exploded[0] = true
			ball.visible = false
			trail.emitting = false
			PWVFX.spawn("explosion", get_parent(), to_global(Vector3(0, 0, z - 0.2)) - Vector3(0, 0.6, 0))
	for m in mats:
		m.set_shader_parameter("progress", 0.0)


func _build_lightning() -> void:
	duration = 0.5
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pts: Array[Vector3] = [Vector3(0, 9, 0)]
	for i in 10:
		var y := 9.0 - (i + 1) * 0.9
		pts.append(Vector3(rng.randf_range(-0.6, 0.6), y, rng.randf_range(-0.6, 0.6)) * Vector3(1, 1, 1))
	pts[pts.size() - 1] = Vector3(0, 0, 0)
	var mb := MB.new()
	for i in pts.size() - 1:
		mb.tube("flat_snow_0", pts[i], pts[i + 1], 0.09, 0.07, 4)
	var bolt := _mesh(mb.commit(), _mat(Color.WHITE, Pal.c("water_0"), 0, 1.4, 0.7))
	_tick = func(t: float, _age: float) -> void:
		bolt.visible = fmod(t * 7.0, 1.0) < 0.7 and t < 0.8
	_flash_light(Pal.c("snow_1"), 8.0, 12.0, 0.45)
	_particles(30, 0.5, Pal.c("water_0"), {"vmin": 3.0, "vmax": 7.0, "size": 0.05, "damping": 5.0, "pos": Vector3(0, 0.1, 0)})
	_mesh(_ring_mesh(0.8, 0.3), _mat(Pal.c("snow_0"), Pal.c("water_1"), 2, 1.2, 0.4), Transform3D(Basis().scaled(Vector3.ONE * 1.5), Vector3(0, 0.06, 0)))


# ---------------------------------------------------------------- 增益

func _build_heal() -> void:
	duration = 1.4
	var ring := _mesh(_ring_mesh(0.8, 0.18), _mat(Color("e8ffe0"), Pal.c("grass_0"), 2, 1.2, 0.4), Transform3D(Basis(), Vector3(0, 0.06, 0)))
	_tick = func(t: float, _age: float) -> void:
		ring.scale = Vector3.ONE * (0.7 + t * 0.5)
	_particles(40, 1.2, Color("c8ffb0"), {"shape": CPUParticles3D.EMISSION_SHAPE_RING, "ring_radius": 0.7, "ring_inner": 0.4,
		"vmin": 0.8, "vmax": 1.6, "dir": Vector3.UP, "spread": 10.0, "gravity": Vector3(0, 0.5, 0), "size": 0.06,
		"explosiveness": 0.2, "color_end": Color(Pal.c("grass_0"), 0.0)})
	_particles(6, 1.0, Color("ffffff"), {"pos": Vector3(0, 1.0, 0), "vmin": 0.3, "vmax": 0.8, "size": 0.12, "gravity": Vector3(0, 0.6, 0), "radius": 0.3})


func _build_magic_circle() -> void:
	duration = 2.0
	var circle := _mesh(_quad_mesh(3.2), _mat(Color("f0e8ff"), Pal.c("cloth_blue"), 3, 1.3, 0.45), Transform3D(Basis(), Vector3(0, 0.05, 0)))
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 1.1
	cyl.height = 4.0
	cyl.radial_segments = 16
	cyl.cap_top = false
	cyl.cap_bottom = false
	var pillar := _mesh(cyl, _mat(Color("e8f0ff"), Pal.c("cloth_blue"), 4, 0.8, 0.15), Transform3D(Basis(), Vector3(0, 2.0, 0)))
	_tick = func(t: float, _age: float) -> void:
		pillar.scale = Vector3(1.0, smoothstep(0.1, 0.4, t), 1.0)
		circle.rotation.y = t * 2.0
	_particles(30, 1.4, Color("d8e0ff"), {"shape": CPUParticles3D.EMISSION_SHAPE_RING, "ring_radius": 1.3, "ring_inner": 0.2,
		"vmin": 1.0, "vmax": 2.2, "dir": Vector3.UP, "spread": 5.0, "gravity": Vector3.ZERO, "size": 0.05, "explosiveness": 0.0})


func _build_shield() -> void:
	duration = 1.6
	var bubble := _mesh(_ball_mesh(1.1), _mat(Color("e8f8ff"), Pal.c("water_0"), 0, 0.9, 0.25, 1.0), Transform3D(Basis(), Vector3(0, 0.9, 0)))
	_tick = func(t: float, _age: float) -> void:
		bubble.scale = Vector3.ONE * (0.6 + smoothstep(0.0, 0.15, t) * 0.4 + sin(t * 30.0) * 0.01)
	_particles(16, 0.6, Pal.c("water_0"), {"pos": Vector3(0, 0.9, 0), "radius": 1.0, "vmin": 0.2, "vmax": 0.6, "size": 0.05, "gravity": Vector3.ZERO})


# ---------------------------------------------------------------- 移动

func _build_dust() -> void:
	duration = 0.6
	_particles(36, 0.8, Color(Pal.c("dirt_0"), 0.85), {"pos": Vector3(0, 0.1, 0.3), "dir": Vector3(0, 0.6, 1), "spread": 40.0,
		"vmin": 1.0, "vmax": 2.6, "size": 0.08, "damping": 3.0, "gravity": Vector3(0, 0.3, 0), "solid": true,
		"color_end": Color(Pal.c("dirt_0"), 0.0), "radius": 0.15})


func _build_land() -> void:
	duration = 0.6
	_particles(50, 0.7, Color(Pal.c("dirt_0"), 0.85), {"shape": CPUParticles3D.EMISSION_SHAPE_RING, "ring_radius": 0.35, "ring_inner": 0.3,
		"pos": Vector3(0, 0.08, 0), "dir": Vector3.UP, "spread": 80.0, "vmin": 1.5, "vmax": 2.8, "size": 0.08, "damping": 4.0,
		"gravity": Vector3(0, 0.2, 0), "solid": true, "color_end": Color(Pal.c("dirt_0"), 0.0)})
	var ring := _mesh(_ring_mesh(0.6, 0.2), _mat(Pal.c("dirt_0"), Pal.c("dirt_1"), 2, 0.9, 0.7), Transform3D(Basis(), Vector3(0, 0.05, 0)))
	_tick = func(t: float, _age: float) -> void:
		ring.scale = Vector3.ONE * (0.6 + t * 1.8)
