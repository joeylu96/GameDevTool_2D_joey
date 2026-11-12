@tool
extends RefCounted
## 全局 Shader 参数。天气与昼夜系统只改这些参数，所有使用 pixel_world 材质的模型自动响应。

const PARAMS := {
	"pw_snow_amount": ["float", 0.0],   # 积雪 0..1
	"pw_wetness": ["float", 0.0],       # 潮湿 0..1
	"pw_night_factor": ["float", 0.0],  # 夜晚程度 0..1（窗户/路灯发光）
	"pw_wind": ["vec2", Vector2(0.3, 0.0)],  # 风向 * 风力（世界 XZ）
	"pw_flash": ["float", 0.0],         # 闪电闪光 0..1
	"pw_desaturate": ["float", 0.0],    # 阴天去饱和 0..1
	"pw_light_color": ["color", Color(1, 1, 1)],  # 当前整体光照色（给无光照特效着色）
	"pw_rain": ["float", 0.0],          # 降雨强度 0..1（水洼 / 水面的雨滴涟漪）
	"pw_sky_color": ["color", Color(0.74, 0.83, 0.93)],  # 天空色（水洼、水面反射）
	# 涟漪源（脚步、物体入水）：x, z = 世界坐标，y = 已经过的秒数，w = 强度（0 = 无）
	"pw_step0": ["vec4", Vector4(0, 0, 99, 0)],
	"pw_step1": ["vec4", Vector4(0, 0, 99, 0)],
	"pw_step2": ["vec4", Vector4(0, 0, 99, 0)],
	"pw_step3": ["vec4", Vector4(0, 0, 99, 0)],
}


static func _type_enum(t: String) -> int:
	match t:
		"vec2":
			return RenderingServer.GLOBAL_VAR_TYPE_VEC2
		"vec4":
			return RenderingServer.GLOBAL_VAR_TYPE_VEC4
		"color":
			return RenderingServer.GLOBAL_VAR_TYPE_COLOR
	return RenderingServer.GLOBAL_VAR_TYPE_FLOAT


## 运行时补齐缺失的全局参数（插件被拷到未配置的工程时兜底）。
static var _runtime_checked := false


static func ensure_runtime() -> void:
	if _runtime_checked:
		return
	_runtime_checked = true
	# 注：global_shader_parameter_get_list() 只在编辑器里可用，这里改查项目设置
	for key: String in PARAMS:
		if not ProjectSettings.has_setting("shader_globals/" + key):
			var p: Array = PARAMS[key]
			RenderingServer.global_shader_parameter_add(key, _type_enum(p[0]), p[1])


## 写入 project.godot（插件启用时调用）。
static func ensure_project_settings() -> bool:
	var changed := false
	for key: String in PARAMS:
		var setting := "shader_globals/" + key
		if not ProjectSettings.has_setting(setting):
			ProjectSettings.set_setting(setting, {"type": PARAMS[key][0], "value": PARAMS[key][1]})
			changed = true
	if changed:
		ProjectSettings.save()
	return changed


static func set_param(key: StringName, value: Variant) -> void:
	RenderingServer.global_shader_parameter_set(key, value)
