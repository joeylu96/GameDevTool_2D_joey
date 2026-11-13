@tool
class_name PWAssetLibrary
extends RefCounted
## 资源注册表：工具链里所有可以放进场景的资源。资源库界面、场景生成器、Blender 资产（P3）都在这里登记。
##
## 每一项：
##   id、cat（分类 id）、name、desc
##   vary：放进场景时会怎么变化（说明文字）
##   build：func(seed: int) -> Mesh 或 Node3D —— 不同种子得到不同的形状 / 款式
##   plant：true 表示放进场景时还会再加随机朝向、宽高比例和色调（和场景里完全一样的做法）
##   size：大致尺寸（米），预览时用来排布和取景

const Trees := preload("res://addons/pixel_world/assets/placeholder/pw_tree_builder.gd")
const House := preload("res://addons/pixel_world/assets/placeholder/pw_house_builder.gd")
const Props := preload("res://addons/pixel_world/assets/placeholder/pw_props_builder.gd")

const CATEGORIES := [
	{"id": "trees", "name": "树木"},
	{"id": "plants", "name": "灌木与草"},
	{"id": "rocks", "name": "岩石"},
	{"id": "buildings", "name": "建筑"},
	{"id": "landmarks", "name": "地标"},
	{"id": "street", "name": "街道设施"},
	{"id": "props", "name": "杂物"},
	{"id": "water", "name": "水生"},
	{"id": "characters", "name": "角色"},
	{"id": "blender", "name": "Blender 资产"},
]

## Blender 生成的资产（P3）：读 res://assets/blender/catalog.json 追加进来；也可以用 register() 手动登记
const BLENDER_DIR := "res://assets/blender/"
const Mats := preload("res://addons/pixel_world/core/pw_materials.gd")
const SHADER := preload("res://addons/pixel_world/shaders/pixel_world.gdshader")
static var _extra: Array[Dictionary] = []
static var _blender_loaded := false
static var _blender_meshes := {}  # "文件名" -> ArrayMesh（材质已换成 pixel_world）


## 读 Blender 资产目录。资产登记到「Blender 资产」分类（semantic 记录它本来属于哪一类，如 buildings）
static func load_blender_catalog() -> int:
	_blender_loaded = true
	var path := BLENDER_DIR + "catalog.json"
	if not FileAccess.file_exists(path):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		push_warning("PWAssetLibrary: %s 格式不对" % path)
		return 0
	var n := 0
	for a: Dictionary in data.get("assets", []):
		var files: Array = a.get("files", [])
		if files.is_empty():
			continue
		var fp: Array = a.get("footprint", [2, 2])
		register({
			"id": a.id, "cat": "blender", "semantic": a.get("category", ""), "name": a.name + "（Blender）",
			"size": maxf(maxf(fp[0], fp[1]), float(a.get("height", 2.0)) * 0.8),
			"plant": a.get("plant", false),
			"desc": a.get("desc", "") + "  来源：%s，%d 个变体。" % [data.get("generator", "Blender"), files.size()],
			"vary": a.get("vary", ""),
			"build": func(s: int) -> Mesh: return blender_mesh(files[s % files.size()]),
		})
		n += 1
	return n


## 加载一个 Blender 导出的 .glb，合并成一个 ArrayMesh，并把每个材质换成统一的 pixel_world 材质：
## 贴图沿用导出的像素贴图；其余参数按材质名（pw_<键>）从 PWMaterials.DEFS 取，所以积雪、潮湿、
## 夜间发光（窗玻璃）等效果和代码生成的资产完全一样。
static func blender_mesh(file: String) -> Mesh:
	if _blender_meshes.has(file):
		return _blender_meshes[file]
	var res: Variant = load(BLENDER_DIR + file) if ResourceLoader.exists(BLENDER_DIR + file) else null
	var out := ArrayMesh.new()
	if res is PackedScene:
		var inst := (res as PackedScene).instantiate()
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			var xf := mi.transform
			for s in mi.mesh.get_surface_count():
				var st := SurfaceTool.new()
				st.append_from(mi.mesh, s, xf)
				out = st.commit(out)
				out.surface_set_material(out.get_surface_count() - 1, _convert_material(mi.get_active_material(s)))
		inst.free()
	_blender_meshes[file] = out
	return out


static func _convert_material(src: Material) -> Material:
	var key := ""
	if src != null:
		key = src.resource_name.trim_prefix("pw_")
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("uv_in_meters", false)  # Blender 端已经按 32 texel/米 算好了 UV
	if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
		m.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
	var def: Dictionary = Mats.DEFS.get(key, {})
	for p: String in def:
		if p == "tex" or p == "uv_in_meters" or (p.ends_with("_tex") and def[p] is String):
			continue
		m.set_shader_parameter(p, def[p])
	if key == "glass":
		m.set_shader_parameter("emission_full", 1.0)
		m.set_shader_parameter("emission_random_off", 0.3)
	return m


static func items() -> Array[Dictionary]:
	if not _blender_loaded:
		load_blender_catalog()
	var out: Array[Dictionary] = [
		{"id": "pine", "show": [3, 8], "cat": "trees", "name": "松树 / 冷杉", "size": 6.0, "plant": true,
			"desc": "八边形层层叠起的针叶树，深色裙边 + 浅色顶盖，下雪时每层顶盖整块积白。",
			"vary": "层数 4~8、底部粗细、收分、坡度、扭转角每棵不同；约三成是更窄更高的冷杉。放进场景时再随机朝向、宽高 ±12%、色调 ±10%。",
			"build": func(s: int) -> Mesh: return Trees.build_pine(1000 + s)},
		{"id": "oak", "show": [3, 7], "cat": "trees", "name": "橡树", "size": 6.0, "plant": true,
			"desc": "主干在约三分之二处分成 2~3 根粗枝，每根枝头一团树冠，中间盖一团主冠。",
			"vary": "主冠大小、分叉高度、枝条方向和长度、侧冠数量随机；场景里再随机朝向、比例、色调。",
			"build": func(s: int) -> Mesh: return Trees.build_broadleaf(2000 + s, "oak")},
		{"id": "birch", "show": [3, 7], "cat": "trees", "name": "白桦", "size": 6.0, "plant": true,
			"desc": "微弯的白色树干带黑色皮孔，3~4 根斜枝，嫩绿的椭圆形树冠。",
			"vary": "树高、弯曲方向、枝条位置、叶团数量和大小随机。",
			"build": func(s: int) -> Mesh: return Trees.build_broadleaf(2100 + s, "birch")},
		{"id": "poplar", "show": [3, 7], "cat": "trees", "name": "杨树", "size": 6.0, "plant": true,
			"desc": "竖长的卵形树冠，三四团由大到小往上叠。",
			"vary": "树冠大小、层数、每团的偏移随机。",
			"build": func(s: int) -> Mesh: return Trees.build_broadleaf(2200 + s, "poplar")},
		{"id": "bush", "show": [3, 8], "cat": "plants", "name": "灌木", "size": 1.6, "plant": true,
			"desc": "贴地的 2~3 个叶团，约三成开花。",
			"vary": "团块数量和大小、是否开花随机；场景里再随机朝向、比例、色调。",
			"build": func(s: int) -> Mesh: return Trees.build_bush(3000 + s)},
		{"id": "grass", "show": [6, 14], "cat": "plants", "name": "草丛", "size": 0.8, "plant": true,
			"desc": "6~12 片细长草叶，根部深、尖端浅，随风从根部摆动。",
			"vary": "四种：普通、高草、干草、带花；每种 5 个变体，叶片数量、高度、倾斜、颜色不同。场景里按 PWGrass 规则成片撒。",
			"build": func(s: int) -> Mesh: return PWGrass.build_tuft(7000 + s, PWGrass.KINDS[s % 4])},
		{"id": "weed", "show": [4, 10], "cat": "water", "name": "水草", "size": 1.0, "plant": true,
			"desc": "长在浅水湖底的细长叶片，水下有焦散光斑。",
			"vary": "叶片数量、高度、位置随机。",
			"build": func(s: int) -> Mesh: return Props.build_weed(5000 + s)},
		{"id": "fish", "show": [3, 8], "cat": "water", "name": "小鱼", "size": 0.5, "plant": false,
			"desc": "在浅水带游动，人靠近时受惊游开，不会游上岸。",
			"vary": "银色 / 橙色两种，大小随机，游速和转向各不相同。",
			"build": func(s: int) -> Mesh: return Props.build_fish("fish_orange" if s % 2 else "fish_silver")},
		{"id": "rock", "show": [3, 8], "cat": "rocks", "name": "石头", "size": 1.4, "plant": true,
			"desc": "两段多边形棱台，顶面能积雪。",
			"vary": "边数 5~7、扁平程度、是否带一块小石头随机；场景里再随机朝向、比例、色调。",
			"build": func(s: int) -> Mesh: return Trees.build_rock(4000 + s)},
		{"id": "house", "show": 1, "cat": "buildings", "name": "小镇房屋", "size": 11.0, "plant": false,
			"desc": "木板墙 + 双坡屋顶，门窗是独立 3D 部件，夜里窗户随机亮灯。",
			"vary": "宽度、进深、层数、墙色、屋顶色、坡度、烟囱、老虎窗、雨棚、花箱、百叶窗、门色、窗格数都由参数随机。",
			"build": func(s: int) -> Mesh:
				var r := RandomNumberGenerator.new()
				r.seed = 9000 + s
				return House.build(House.random_params(r))},
		{"id": "lighthouse", "show": 1, "cat": "landmarks", "name": "灯塔", "size": 14.0, "plant": false,
			"desc": "红白条纹塔身、环形走廊和栏杆，灯室夜里发光。",
			"vary": "目前单一款式。",
			"build": func(s: int) -> Mesh: return Props.build_lighthouse()},
		{"id": "windmill", "show": 1, "cat": "landmarks", "name": "风车", "size": 10.0, "plant": false,
			"desc": "石砌塔身 + 红色锥顶，四片格栅叶片匀速转动（平原风格）。",
			"vary": "目前单一款式；叶片转速可调。",
			"build": func(s: int) -> Node3D:
				var root := Node3D.new()
				var tower := MeshInstance3D.new()
				tower.mesh = Props.build_windmill_tower()
				root.add_child(tower)
				var blades := MeshInstance3D.new()
				blades.mesh = Props.build_windmill_blades()
				blades.set_script(load("res://addons/pixel_world/world/pw_spinner.gd"))
				blades.position = Props.windmill_hub()
				root.add_child(blades)
				return root},
		{"id": "lamp", "show": "styles:4", "cat": "street", "name": "路灯", "size": 3.0, "plant": false,
			"desc": "夜里灯头发光，地面有柔和的光斑。",
			"vary": "4 种款式（灯笼、悬臂、球形、双头）× 3 种金属色，每盏随机。",
			"build": func(s: int) -> Mesh: return Trees.build_lamp(Trees.LAMP_STYLES[s % 4], Trees.LAMP_METALS[(s / 4) % 3])},
		{"id": "fence", "show": "styles:3", "cat": "street", "name": "篱笆", "size": 3.0, "plant": false,
			"desc": "沿前院或田地围起来，门口留缺口。",
			"vary": "3 种：白色尖头栅栏、乡村木栏、矮石墙。",
			"build": func(s: int) -> Mesh: return Props.build_fence(3.0, [], Props.FENCE_STYLES[s % 3])},
		{"id": "bench", "show": "styles:3", "cat": "street", "name": "长椅", "size": 1.8, "plant": false,
			"desc": "放在路灯旁，面朝道路。",
			"vary": "3 种：木条长椅、公园绿漆长椅、原木凳。",
			"build": func(s: int) -> Mesh: return Props.build_bench(Props.BENCH_STYLES[s % 3])},
		{"id": "crate", "show": [2, 5], "cat": "props", "name": "木箱", "size": 0.8, "plant": false,
			"desc": "码头、营地边的货物。", "vary": "大小随机。",
			"build": func(s: int) -> Mesh: return Props.build_crate(0.5 + (s % 3) * 0.12)},
		{"id": "barrel", "show": [2, 5], "cat": "props", "name": "木桶", "size": 0.9, "plant": false,
			"desc": "中间鼓、上下收口，两道铁箍。", "vary": "目前单一款式。",
			"build": func(s: int) -> Mesh: return Props.build_barrel()},
		{"id": "haystack", "show": [2, 4], "cat": "props", "name": "草垛", "size": 2.5, "plant": false,
			"desc": "平原农田里的干草卷或草堆。", "vary": "卷 / 堆两种形状，大小随机。",
			"build": func(s: int) -> Mesh: return Props.build_haystack(6000 + s)},
		{"id": "villager", "show": 1, "cat": "characters", "name": "小镇居民", "size": 1.7, "plant": false,
			"desc": "Q 版低模小人，走路动画、碰撞、涉水和水面涟漪。WASD 可以操控。",
			"vary": "目前单一造型；P4 会接入「原画 → 参数」的换装体系。",
			"build": func(s: int) -> Node3D: return PWCharacter.new()},
	]
	out.append_array(_extra)
	return out


static func in_category(cat: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in items():
		if it.cat == cat:
			out.append(it)
	return out


static func register(item: Dictionary) -> void:
	for i in _extra.size():
		if _extra[i].id == item.id:
			_extra[i] = item
			return
	_extra.append(item)


## 按场景里的做法生成一个实例：Mesh 会套上随机朝向 / 比例 / 色调（plant = true 时）
static func instantiate(item: Dictionary, seed_value: int, rng: RandomNumberGenerator) -> Node3D:
	var built: Variant = item.build.call(seed_value)
	if built is Node3D:
		return built
	var mi := MeshInstance3D.new()
	mi.mesh = built
	if item.get("plant", false):
		var s := rng.randf_range(0.85, 1.15)
		mi.basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
		# 色调：和场景里一样乘到顶点色上（通过 MultiMesh 风格的实例数据不方便，这里复制一份顶点色）
		var k := rng.randf_range(0.9, 1.06)
		mi.mesh = _tinted(built, Color(k * rng.randf_range(0.95, 1.05), k, k * rng.randf_range(0.93, 1.05)))
	return mi


static func _tinted(mesh: Mesh, tint: Color) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var n: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var cols := PackedColorArray()
		var src: Variant = arr[Mesh.ARRAY_COLOR]
		if src is PackedColorArray and (src as PackedColorArray).size() == n:
			cols = (src as PackedColorArray).duplicate()
		else:
			cols.resize(n)
			cols.fill(Color.WHITE)
		for i in n:
			cols[i] = Color(cols[i].r * tint.r, cols[i].g * tint.g, cols[i].b * tint.b, cols[i].a)
		arr[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out
