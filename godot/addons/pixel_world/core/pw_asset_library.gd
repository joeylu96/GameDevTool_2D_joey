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
##   sub：子分类 id（可选）；blender：true 表示来自 Blender 资产目录
##
## 分类结构可以改（资源库里新增分类 / 子分类、把资源挪到别的分类；AI 资产工坊生成时选放到哪）：
##   res://assets/library.json = {"categories": [{id, name, builtin?, children: [{id, name}]}],
##                                "assign": {"资源 id": ["分类 id", "子分类 id"]}}
## 工具箱和资产工坊共用这一份；网页版通过工坊服务（/api/library）读写，桌面 / 编辑器里直接读写文件。

const Trees := preload("res://addons/pixel_world/assets/placeholder/pw_tree_builder.gd")
const House := preload("res://addons/pixel_world/assets/placeholder/pw_house_builder.gd")
const Props := preload("res://addons/pixel_world/assets/placeholder/pw_props_builder.gd")

## 内置分类（library.json 缺失或少了某个内置分类时补上）
const DEFAULT_CATEGORIES := [
	{"id": "trees", "name": "树木"},
	{"id": "plants", "name": "灌木与草"},
	{"id": "rocks", "name": "岩石"},
	{"id": "buildings", "name": "建筑"},
	{"id": "landmarks", "name": "地标"},
	{"id": "street", "name": "街道设施"},
	{"id": "props", "name": "杂物"},
	{"id": "water", "name": "水生"},
	{"id": "characters", "name": "角色"},
]
const LIBRARY_PATH := "res://assets/library.json"
static var _lib: Dictionary = {}


# ---------------------------------------------------------------- 分类结构

static func library() -> Dictionary:
	if _lib.is_empty():
		var d: Variant = null
		if FileAccess.file_exists(LIBRARY_PATH):
			d = JSON.parse_string(FileAccess.get_file_as_string(LIBRARY_PATH))
		_lib = _normalize(d)
	return _lib


## 网页版从工坊服务拿到最新的分类结构后调用
static func set_library(d: Variant) -> void:
	_lib = _normalize(d)


static func _normalize(d: Variant) -> Dictionary:
	var out := {"version": 1, "categories": [], "assign": {}}
	var cats: Array = (d as Dictionary).get("categories", []) if d is Dictionary else []
	var seen := {}
	for c: Variant in cats:
		if not (c is Dictionary) or not c.has("id"):
			continue
		var kids: Array = []
		for k: Variant in c.get("children", []):
			if k is Dictionary and k.has("id"):
				kids.append({"id": String(k.id), "name": String(k.get("name", k.id))})
		out.categories.append({"id": String(c.id), "name": String(c.get("name", c.id)), "builtin": bool(c.get("builtin", false)),
			"children": kids})
		seen[String(c.id)] = true
	for i in DEFAULT_CATEGORIES.size():
		var dc: Dictionary = DEFAULT_CATEGORIES[i]
		if not seen.has(dc.id):
			out.categories.insert(mini(i, out.categories.size()), {"id": dc.id, "name": dc.name, "builtin": true, "children": []})
	if d is Dictionary and (d as Dictionary).get("assign") is Dictionary:
		for k: String in d.assign:
			var v: Variant = d.assign[k]
			if v is Array and v.size() >= 1:
				out.assign[k] = [String(v[0]), String(v[1]) if v.size() > 1 else ""]
	return out


static func categories() -> Array:
	return library().categories


static func category(id: String) -> Dictionary:
	for c: Dictionary in categories():
		if c.id == id:
			return c
	return {}


static func _new_id(prefix: String) -> String:
	return "%s%x" % [prefix, (Time.get_unix_time_from_system() * 1000.0) as int & 0xFFFFFFFF]


## 新增分类，返回 id
static func add_category(name: String) -> String:
	var id := _new_id("c")
	categories().append({"id": id, "name": name, "builtin": false, "children": []})
	return id


## 在某个分类下新增子分类，返回 id
static func add_subcategory(cat_id: String, name: String) -> String:
	var c := category(cat_id)
	if c.is_empty():
		return ""
	var id := _new_id("s")
	(c.children as Array).append({"id": id, "name": name})
	return id


## 删除分类（内置分类不能删）或子分类；放在里面的资源回到默认位置
static func remove(cat_id: String, sub_id := "") -> bool:
	var lib := library()
	if sub_id == "":
		var c := category(cat_id)
		if c.is_empty() or c.get("builtin", false):
			return false
		lib.categories.erase(c)
	else:
		var c := category(cat_id)
		for k: Dictionary in c.get("children", []):
			if k.id == sub_id:
				(c.children as Array).erase(k)
				break
	for item_id: String in lib.assign.keys():
		var v: Array = lib.assign[item_id]
		if v[0] == cat_id and (sub_id == "" or v[1] == sub_id):
			lib.assign.erase(item_id)
	return true


## 把资源放到某个分类 / 子分类
static func move_item(item_id: String, cat_id: String, sub_id := "") -> void:
	library().assign[item_id] = [cat_id, sub_id]


## 桌面版 / 编辑器：直接写 library.json。网页版写不了（返回 false），由界面通过工坊服务保存
static func save_library() -> bool:
	if OS.has_feature("web"):
		return false
	var f := FileAccess.open(LIBRARY_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(library(), "  "))
	return true

## Blender 生成的资产（P3）：读 res://assets/blender/catalog.json 追加进来；也可以用 register() 手动登记
const BLENDER_DIR := "res://assets/blender/"
const Mats := preload("res://addons/pixel_world/core/pw_materials.gd")
const SHADER := preload("res://addons/pixel_world/shaders/pixel_world.gdshader")
static var _extra: Array[Dictionary] = []
static var _blender_loaded := false
static var _blender_meshes := {}  # "文件名" -> ArrayMesh（材质已换成 pixel_world）


## 读 Blender 资产目录。资产登记到「Blender 资产」分类（semantic 记录它本来属于哪一类，如 buildings）
## 按标签挑 Blender 资产（场景生成器用）：带有 any_tags 里任意一个标签、且 id 不在 exclude 里的
static func blender_with_tags(any_tags: Array, exclude: Array = []) -> Array[Dictionary]:
	if not _blender_loaded:
		load_blender_catalog()
	var out: Array[Dictionary] = []
	for it in _extra:
		if not it.get("blender", false) or it.id in exclude:
			continue
		for t in it.get("tags", []):
			if t in any_tags:
				out.append(it)
				break
	return out


## 气候标签（winter / desert / island / canyon）：带气候标签的资产只在对应风格里出现（雪人不会出现在夏天的小镇）；
## 也带了当前风格名（town / forest / plains）标签的除外；没有气候标签的通用资产哪里都能用。
const CLIMATE_TAGS := {"winter": "snowfield", "desert": "desert", "island": "island", "canyon": "canyon"}


static func fits_climate(item: Dictionary, theme: String) -> bool:
	var tags: Array = item.get("tags", [])
	var has_climate := false
	for t in tags:
		if CLIMATE_TAGS.has(t):
			has_climate = true
			if CLIMATE_TAGS[t] == theme:
				return true
	return not has_climate or theme in tags


## 重新读 Blender 资产目录（资产工坊生成了新资产后调用）
static func reload_blender_catalog() -> int:
	_blender_meshes.clear()
	var keep: Array[Dictionary] = []
	for it in _extra:
		if not it.get("blender", false):
			keep.append(it)
	_extra = keep
	return load_blender_catalog()


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
		# 展示规则：树随机撒几棵；建筑排 3 个变体；其余把导出的变体排成一排
		var sem: String = a.get("category", "")
		var show: Variant = [3, 6] if sem == "trees" else ("styles:%d" % mini(files.size(), 3 if sem == "buildings" else 4))
		register({
			"id": a.id, "cat": sem if not category(sem).is_empty() else "props", "blender": true, "semantic": sem,
			"name": a.name + "（Blender）", "show": show,
			"tags": a.get("tags", []), "footprint": fp, "height": float(a.get("height", 2.0)), "source": a.get("source", "generator"),
			"variants": files.size(),
			"variant_info": a.get("variant_info", []),
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
				var src_mat := mi.get_active_material(s)
				var key := src_mat.resource_name.trim_prefix("pw_") if src_mat != null else ""
				var arr := st.commit_to_arrays()
				_fix_surface(arr, key, file)
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				out.surface_set_material(out.get_surface_count() - 1, _convert_material(src_mat))
		inst.free()
	_blender_meshes[file] = out
	return out


## 导入时按材质修一下顶点数据：
##   草叶：法线偏向正上方（和代码版草丛一样），背面不会发黑，草地整体受光均匀
##   窗玻璃：每块玻璃（相连的一组三角形）随机一个顶点 alpha，夜里按 emission_random_off 有的亮有的不亮
static func _fix_surface(arr: Array, key: String, file: String) -> void:
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if key.begins_with("blade"):
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in nrm.size():
			nrm[i] = nrm[i].lerp(Vector3.UP, 0.7).normalized()
		arr[Mesh.ARRAY_NORMAL] = nrm
	elif key == "glass":
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		# 并查集：同一个三角形的顶点、位置重合的顶点归到一块玻璃
		var parent := PackedInt32Array()
		parent.resize(verts.size())
		for i in verts.size():
			parent[i] = i
		var find := func(x: int) -> int:
			while parent[x] != x:
				parent[x] = parent[parent[x]]
				x = parent[x]
			return x
		var by_pos := {}
		for i in verts.size():
			var k := Vector3i((verts[i] * 100.0).round())
			if by_pos.has(k):
				parent[find.call(i)] = find.call(by_pos[k])
			else:
				by_pos[k] = i
		for t in range(0, idx.size() - 2, 3):
			var r0: int = find.call(idx[t])
			parent[find.call(idx[t + 1])] = r0
			parent[find.call(idx[t + 2])] = find.call(r0)
		var cols := PackedColorArray()
		var old: Variant = arr[Mesh.ARRAY_COLOR]
		cols.resize(verts.size())
		var h0 := hash(file)
		for i in verts.size():
			var c: Color = (old as PackedColorArray)[i] if old != null else Color.WHITE
			c.a = float(hash(h0 + find.call(i)) % 1000) / 1000.0
			cols[i] = c
		arr[Mesh.ARRAY_COLOR] = cols


## 同一个材质键（pw_<键>）的所有 Blender 资产共用一份材质：贴图是 Blender 按同样的种子画的，完全一样；
## 共用材质后场景合批（PWBatcher 按材质分组）不会因为换成 Blender 模型而多出绘制调用
static var _bl_mats := {}


static func _convert_material(src: Material) -> Material:
	var key := ""
	if src != null:
		key = src.resource_name.trim_prefix("pw_")
	if key != "" and _bl_mats.has(key):
		return _bl_mats[key]
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
	if key != "":
		_bl_mats[key] = m
	return m


## 有 Blender 版的资源，资源库和场景生成都用 Blender 版（Godot 代码版只在没有 Blender 资产目录时兜底）
const REPLACED_BY := {"pine": "bl_pine", "oak": "bl_oak", "birch": "bl_birch", "poplar": "bl_poplar", "bush": "bl_bush",
	"rock": "bl_rock", "grass": "bl_grass_tuft", "weed": "bl_weed", "fish": "bl_fish", "house": "bl_town_house",
	"lighthouse": "bl_lighthouse", "lamp": "bl_street_lamp", "fence": "bl_fence", "bench": "bl_bench",
	"crate": "bl_crate", "barrel": "bl_barrel", "haystack": "bl_haystack"}
## 只作为部件用的 Blender 资产（风车叶片 / 塔身由「风车」条目组装，篱笆柱跟着篱笆走），资源库里不单独列
const PARTS_ONLY := ["bl_windmill_tower", "bl_windmill_blades", "bl_fence_post"]


## 每个变体自己的尺寸（catalog 里的 variant_info：footprint / height / width / depth / floors）；没有就返回空数组
static func blender_variant_info(id: String) -> Array:
	for it in blender_items():
		if it.id == id:
			return it.get("variant_info", [])
	return []


## Blender 资产的全部变体（网格）；没有这个资产时返回空数组
static func blender_variants(id: String) -> Array[Mesh]:
	var out: Array[Mesh] = []
	for it in blender_items():
		if it.id == id:
			for i in int(it.get("variants", 1)):
				out.append(it.build.call(i))
	return out


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
			"vary": "有 Blender 资产时：屋顶 / 塔身 / 门 3 种 × 帆布 3 种（Blender 风车塔身 + 叶片组装）；叶片转速可调。",
			"build": func(s: int) -> Node3D:
				var root := Node3D.new()
				var tower := MeshInstance3D.new()
				var bt := blender_variants("bl_windmill_tower")
				var bb := blender_variants("bl_windmill_blades")
				tower.mesh = bt[s % bt.size()] if not bt.is_empty() else Props.build_windmill_tower()
				root.add_child(tower)
				var blades := MeshInstance3D.new()
				blades.mesh = bb[s % bb.size()] if not bb.is_empty() else Props.build_windmill_blades()
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
	# P4：Blender 渲染的 HD-2D 像素精灵角色（tools/blender_build_sprites.py 生成）
	for c: Dictionary in PWSpriteVisual.characters():
		var cid: String = c.id
		out.append({"id": "sprite_" + cid, "show": 1, "cat": "characters", "name": c.name + "（像素精灵）", "size": 1.7,
			"plant": false, "desc": c.desc + "  Blender 搭模、8 方向渲染、分档上色 + 描边的 HD-2D 精灵，场景里受光照和阴影影响。",
			"vary": "8 个方向 × 待机 4 帧 + 走路 6 帧；预览里在待机和原地走路之间切换，转动视角可以看不同方向。",
			"build": func(s: int) -> Node3D:
				var v := PWSpriteVisual.create(cid)
				v.demo = true
				return v})
	out.append_array(_extra)
	# 有 Blender 版的就不再列 Godot 代码版
	var have := {}
	for it in _extra:
		have[it.id] = true
	out = out.filter(func(it: Dictionary) -> bool: return not (REPLACED_BY.has(it.id) and have.has(REPLACED_BY[it.id])) \
		and not PARTS_ONLY.has(it.id))
	# 代码版小人：有 Blender 渲染的像素精灵角色时不再列出
	if not PWSpriteVisual.characters().is_empty():
		out = out.filter(func(it: Dictionary) -> bool: return it.id != "villager")
	# 用户调整过的位置（资源库里「移动到」、资产工坊生成时选的分类）
	var assign: Dictionary = library().assign
	for it in out:
		it["sub"] = ""
		if assign.has(it.id):
			var v: Array = assign[it.id]
			var c := category(v[0])
			if not c.is_empty():
				it.cat = v[0]
				for k: Dictionary in c.children:
					if k.id == v[1]:
						it.sub = v[1]
	return out


## 某个分类（sub 为空 = 整个分类，含所有子分类）里的资源
static func in_category(cat: String, sub := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in items():
		if it.cat == cat and (sub == "" or it.get("sub", "") == sub):
			out.append(it)
	return out


## 全部 Blender 资产（场景生成器、测试用）
static func blender_items() -> Array[Dictionary]:
	if not _blender_loaded:
		load_blender_catalog()
	var out: Array[Dictionary] = []
	for it in _extra:
		if it.get("blender", false):
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
