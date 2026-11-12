@tool
extends RefCounted
## 统一材质库：所有模型都用 pixel_world.gdshader，只是贴图和少量参数不同。

const Tex := preload("res://addons/pixel_world/core/pw_textures.gd")
const SHADER := preload("res://addons/pixel_world/shaders/pixel_world.gdshader")

## 材质定义：tex = 贴图键；其余字段直接作为 shader 参数。
const DEFS := {
	"wall_red": {"tex": "wall_red"},
	"wall_ochre": {"tex": "wall_ochre"},
	"wall_teal": {"tex": "wall_teal"},
	"wall_wood": {"tex": "wall_wood"},
	"roof_grey": {"tex": "roof_grey"},
	"roof_red": {"tex": "roof_red"},
	"roof_under": {"tex": "wall_wood", "snow_receive": 0.0},
	"trim": {"tex": "trim", "snow_receive": 0.6},
	"stone": {"tex": "stone"},
	"brick": {"tex": "brick"},
	"pine": {"tex": "pine", "sway": 1.0},
	"trunk": {"tex": "trunk"},
	"metal": {"tex": "metal"},
	"bulb": {"tex": "lamp_glass", "emission_full": 1.0, "emission_energy": 2.2, "snow_receive": 0.0},
	"grass": {"tex": "grass"},
	"dirt": {"tex": "dirt"},
	"earth": {"tex": "earth", "snow_receive": 0.0},
	"cobble": {"tex": "cobble", "snow_receive": 0.62, "snow_patchiness": 0.8},
	"window": {"tex": "window", "uv_in_meters": false, "emission_tex": "window_emit",
		"emission_random_off": 0.3, "snow_receive": 0.0, "roughness_base": 0.3},
	"door": {"tex": "door", "uv_in_meters": false, "snow_receive": 0.0},
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
			"emission_tex":
				m.set_shader_parameter("emission_tex", Tex.get_tex(v))
			_:
				m.set_shader_parameter(p, v)
	_cache[key] = m
	return m
