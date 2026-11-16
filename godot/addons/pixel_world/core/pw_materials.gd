@tool
extends RefCounted
## 统一材质库：所有模型都用 pixel_world.gdshader，只是贴图和少量参数不同。
## 没有登记的键按 {"tex": 键名} 处理，例如 "flat_ink" 就是纯色材质。

const Tex := preload("res://addons/pixel_world/core/pw_textures.gd")
const SHADER := preload("res://addons/pixel_world/shaders/pixel_world.gdshader")

## 材质定义：tex = 贴图键；其余字段直接作为 shader 参数。
const DEFS := {
	# 墙面 / 屋顶 / 木作
	"wall_red": {"tex": "wall_red"},
	"wall_ochre": {"tex": "wall_ochre"},
	"wall_teal": {"tex": "wall_teal"},
	"wall_wood": {"tex": "wall_wood"},
	"roof_grey": {"tex": "roof_grey"},
	"roof_red": {"tex": "roof_red"},
	"roof_under": {"tex": "wall_wood", "snow_receive": 0.0},
	"roof_cap": {"tex": "roof_cap"},
	"trim": {"tex": "trim", "snow_receive": 0.6},
	"door_wood": {"tex": "door_wood", "snow_receive": 0.3},
	"door_red": {"tex": "door_red", "snow_receive": 0.3},
	"door_teal": {"tex": "door_teal", "snow_receive": 0.3},
	"door_green": {"tex": "door_green", "snow_receive": 0.3},
	"glass": {"tex": "glass", "emission_full": 1.0, "emission_energy": 1.8, "emission_random_off": 0.3,
		"snow_receive": 0.0, "roughness_base": 0.15, "wet_receive": 0.0},
	"brass": {"tex": "brass", "roughness_base": 0.35, "snow_receive": 0.0},
	"flowers": {"tex": "flowers"},
	"crate": {"tex": "crate"},
	"boards": {"tex": "boards"},
	"barrel": {"tex": "barrel"},
	"trunk": {"tex": "trunk"},
	"hay": {"tex": "hay", "snow_receive": 0.8},
	"deck": {"tex": "deck", "puddles": 0.4},
	"birch_bark": {"tex": "birch_bark"},
	# 石作 / 金属
	"stone": {"tex": "stone"},
	"brick": {"tex": "brick"},
	"curb": {"tex": "curb", "snow_patchiness": 0.4},
	"earth": {"tex": "earth", "snow_receive": 0.0},
	"rock": {"tex": "rock"},
	"plaster_white": {"tex": "plaster_white"},
	"plaster_red": {"tex": "plaster_red"},
	"metal": {"tex": "metal", "roughness_base": 0.6},
	"metal_green": {"tex": "metal_green", "roughness_base": 0.55},
	"metal_red": {"tex": "metal_red", "roughness_base": 0.55},
	"bulb": {"tex": "lamp_glass", "emission_full": 1.0, "emission_energy": 2.2, "snow_receive": 0.0},
	"beacon": {"tex": "lamp_glass", "emission_full": 1.0, "emission_energy": 3.0, "snow_receive": 0.0},
	# 植物
	"pine": {"tex": "pine", "sway": 1.0},
	"pine_skirt": {"tex": "pine_skirt", "sway": 1.0},
	"leaf": {"tex": "leaf", "sway": 0.6},
	"leaf_dark": {"tex": "leaf_dark", "sway": 0.6},
	"leaf_birch": {"tex": "leaf_birch", "sway": 0.8},
	"leaf_birch_dark": {"tex": "leaf_birch_dark", "sway": 0.8},
	# Blender 资产（P3 / 资产工坊）用到的材质：贴图来自 glb，这里只定义行为（摆动、积雪、发光）
	"palm_leaf": {"tex": "leaf", "sway": 1.2},
	"cactus": {"tex": "leaf_dark", "snow_receive": 0.3},
	"snow": {"tex": "plaster_white", "snow_receive": 0.0, "roughness_base": 0.8},
	"coal": {"tex": "metal", "snow_receive": 0.0},
	"siding_white": {"tex": "plaster_white"},
	"siding_ochre": {"tex": "wall_ochre"},
	"rock_red": {"tex": "rock_red"},
	"bulb_warm": {"tex": "lamp_glass", "emission_full": 1.0, "emission_energy": 2.2, "snow_receive": 0.0},
	"weed": {"tex": "weed", "sway": 2.0, "snow_receive": 0.0, "caustics": 1.0},
	# 草叶：纯白贴图，颜色全靠顶点色（根部深、尖端亮）；从根部开始随风摆
	"blade": {"tex": "flat_snow_0", "sway": 30.0, "sway_base": 0.0, "snow_receive": 0.0, "roughness_base": 0.8},
	"blade_dry": {"tex": "flat_snow_0", "sway": 30.0, "sway_base": 0.0, "snow_receive": 0.0, "roughness_base": 0.85},
	"canvas_red": {"tex": "cloth_red", "snow_receive": 0.4},
	"canvas_ochre": {"tex": "wall_ochre", "snow_receive": 0.4},
	"canvas_teal": {"tex": "cloth_blue", "snow_receive": 0.4},
	"fruit_red": {"tex": "cloth_red", "snow_receive": 0.0},
	"fruit_green": {"tex": "leaf", "snow_receive": 0.0},
	"fruit_yellow": {"tex": "wall_ochre", "snow_receive": 0.0},
	"door": {"tex": "door_wood", "snow_receive": 0.3},
	# 中世纪小镇（Blender 资产；贴图来自 glb，这里定义积雪 / 发光等行为）
	"timber": {"tex": "trunk", "snow_receive": 0.6},
	"plaster_ochre": {"tex": "plaster_white"},
	"thatch": {"tex": "hay", "snow_receive": 1.0, "snow_patchiness": 0.4},
	"slate": {"tex": "roof_grey"},
	"castle_stone": {"tex": "stone", "snow_receive": 0.8},
	"cobble_wall": {"tex": "stone", "snow_receive": 0.8},
	"forge_coal": {"tex": "lamp_glass", "emission_full": 1.0, "emission_energy": 2.4, "snow_receive": 0.0},
	"glass_lead": {"tex": "glass", "emission_full": 1.0, "emission_energy": 1.6, "emission_random_off": 0.35, "snow_receive": 0.0},
	"cloth_green": {"tex": "cloth_blue", "snow_receive": 0.0},
	"cloth_gold": {"tex": "cloth_red", "snow_receive": 0.0},
	"iron": {"tex": "metal", "snow_receive": 0.4},
	"water": {"tex": "glass", "snow_receive": 0.0, "roughness_base": 0.2},
	"blade_flower": {"tex": "flat_snow_0", "sway": 30.0, "sway_base": 0.0, "snow_receive": 0.0, "roughness_base": 0.7},
	# 现代风格（Blender 资产）
	"render_white": {"tex": "plaster_white"},
	"render_grey": {"tex": "plaster_white"},
	"render_sand": {"tex": "plaster_white"},
	"clad_wood": {"tex": "boards"},
	"clad_dark": {"tex": "boards"},
	"metal_roof": {"tex": "roof_grey", "roughness_base": 0.5},
	"glass_modern": {"tex": "glass", "emission_full": 1.0, "emission_energy": 1.6, "emission_random_off": 0.35,
		"snow_receive": 0.0, "roughness_base": 0.12, "wet_receive": 0.0},
	"glass_car": {"tex": "glass", "snow_receive": 0.0, "roughness_base": 0.1, "wet_receive": 0.0},  # 不发光（车窗、栏板、公交亭）
	"steel": {"tex": "metal", "roughness_base": 0.4, "snow_receive": 0.4},
	"concrete": {"tex": "curb", "snow_patchiness": 0.4},
	"paint_red": {"tex": "metal_red", "roughness_base": 0.35, "snow_receive": 0.5},
	"paint_blue": {"tex": "metal_red", "roughness_base": 0.35, "snow_receive": 0.5},
	"paint_white": {"tex": "metal_red", "roughness_base": 0.35, "snow_receive": 0.5},
	"paint_grey": {"tex": "metal_red", "roughness_base": 0.35, "snow_receive": 0.5},
	"paint_yellow": {"tex": "metal_red", "roughness_base": 0.35, "snow_receive": 0.5},
	"paint_teal": {"tex": "metal_red", "roughness_base": 0.35, "snow_receive": 0.5},
	"paint_black": {"tex": "metal_red", "roughness_base": 0.35, "snow_receive": 0.5},
	"paint_green": {"tex": "metal_red", "roughness_base": 0.35, "snow_receive": 0.5},
	"tyre": {"tex": "metal", "roughness_base": 0.9, "snow_receive": 0.0},
	# 八九十年代中国乡村（Blender 资产）
	"brick_red_cn": {"tex": "brick", "snow_receive": 0.7},
	"brick_grey": {"tex": "brick", "snow_receive": 0.7},
	"mudbrick": {"tex": "brick", "snow_receive": 0.7},
	"whitewash": {"tex": "plaster_white"},
	"tile_cn": {"tex": "roof_grey"},
	"red_paper": {"tex": "cloth_red", "snow_receive": 0.0},
	"cement": {"tex": "curb", "snow_patchiness": 0.4, "puddles": 0.6},
	"glaze": {"tex": "barrel", "roughness_base": 0.25, "snow_receive": 0.3},
	# 地面：puddles = 下雨时积水的程度
	"grass": {"tex": "grass", "puddles": 0.55},
	"dirt": {"tex": "dirt", "puddles": 1.0},
	"cobble": {"tex": "cobble", "snow_receive": 0.5, "snow_patchiness": 0.8, "puddles": 0.9},
	"asphalt": {"tex": "asphalt", "snow_receive": 0.5, "snow_patchiness": 0.8, "puddles": 1.0, "roughness_base": 0.85},
	"road_paint": {"tex": "road_paint", "snow_receive": 0.5, "snow_patchiness": 0.8, "puddles": 0.6},
	"shore": {"tex": "shore", "snow_patchiness": 0.5, "puddles": 0.7},
	"sand": {"tex": "sand", "caustics": 1.0},
	"lakebed": {"tex": "lakebed", "caustics": 1.0},
	# 生物 / 人物（会移动，不接积雪，否则积雪图案会跟着闪）
	"fish_orange": {"tex": "fish_orange", "snow_receive": 0.0, "roughness_base": 0.4},
	"fish_silver": {"tex": "fish_silver", "snow_receive": 0.0, "roughness_base": 0.4},
	"cloth_red": {"tex": "cloth_red", "snow_receive": 0.0},
	"cloth_blue": {"tex": "cloth_blue", "snow_receive": 0.0},
	"cloth_dark": {"tex": "cloth_dark", "snow_receive": 0.0},
	"knit": {"tex": "knit", "snow_receive": 0.0},
	"skin": {"tex": "skin", "snow_receive": 0.0, "roughness_base": 0.7},
	"hair": {"tex": "hair", "snow_receive": 0.0},
	"boots": {"tex": "boots", "snow_receive": 0.0},
	# 野外地形：草地 + 沙 / 岩石 / 湖底按顶点权重混合（见 pixel_world.gdshader 的 terrain_mode）
	"terrain": {"tex": "grass", "terrain_mode": true, "sand_tex": "sand", "rock_tex": "rock",
		"bed_tex": "lakebed", "puddles": 0.55, "caustics": 1.0},
	# 沙漠：基底还是草（只有绿洲一圈），沙地靠顶点权重铺满；岩石是红岩
	"terrain_desert": {"tex": "grass", "terrain_mode": true, "sand_tex": "sand", "rock_tex": "rock_red",
		"bed_tex": "lakebed", "puddles": 0.2, "caustics": 1.0},
	# 峡谷：台地是偏红的细沙土（颗粒细、远看均匀），崖壁是一层层的岩层
	"terrain_canyon": {"tex": "canyon_soil", "terrain_mode": true, "sand_tex": "sand", "rock_tex": "rock",
		"bed_tex": "lakebed", "puddles": 0.6, "caustics": 1.0, "strata": 1.0},
}

static var _cache := {}


static func get_mat(key: String) -> Material:
	if _cache.has(key):
		return _cache[key]
	var def: Dictionary = DEFS.get(key, {"tex": key})
	var m := ShaderMaterial.new()
	m.shader = SHADER
	for p: String in def:
		var v: Variant = def[p]
		match p:
			"tex":
				m.set_shader_parameter("albedo_tex", Tex.get_tex(v))
			_:
				# 以 _tex 结尾、值是字符串的参数都是贴图键
				if p.ends_with("_tex") and v is String:
					m.set_shader_parameter(p, Tex.get_tex(v))
				else:
					m.set_shader_parameter(p, v)
	if key.begins_with("flat_") or key in ["skin", "cloth_red", "cloth_blue", "cloth_dark", "knit", "hair", "boots"]:
		m.set_shader_parameter("snow_receive", 0.0)
	_cache[key] = m
	return m
