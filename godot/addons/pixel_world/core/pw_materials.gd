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
	"weed": {"tex": "weed", "sway": 2.0, "snow_receive": 0.0, "caustics": 1.0},
	# 草叶：纯白贴图，颜色全靠顶点色（根部深、尖端亮）；从根部开始随风摆
	"blade": {"tex": "flat_snow_0", "sway": 30.0, "sway_base": 0.0, "snow_receive": 0.0, "roughness_base": 0.8},
	"blade_flower": {"tex": "flat_snow_0", "sway": 30.0, "sway_base": 0.0, "snow_receive": 0.0, "roughness_base": 0.7},
	# 地面：puddles = 下雨时积水的程度
	"grass": {"tex": "grass", "puddles": 0.55},
	"dirt": {"tex": "dirt", "puddles": 1.0},
	"cobble": {"tex": "cobble", "snow_receive": 0.5, "snow_patchiness": 0.8, "puddles": 0.9},
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
