@tool
class_name PWWeatherPreset
extends Resource
## 一种天气的全部参数。WeatherSystem 在两个预设之间平滑插值。
## 可在编辑器里新建 .tres 自定义天气，再放进 WeatherSystem.custom_presets。

@export var id := "clear"
@export var display_name := "Clear"
@export_range(0.0, 1.0) var rain := 0.0
@export_range(0.0, 1.0) var snow := 0.0
@export_range(0.0, 1.0) var cloud := 0.0
@export_range(0.0, 0.1, 0.001) var fog := 0.002
## 风向 * 风力（世界 XZ 平面）
@export var wind := Vector2(0.2, 0.05)
@export_range(0.0, 1.0) var desaturate := 0.0
## 积雪目标：-1 = 保持当前积雪；0 = 融化；1 = 积满
@export_range(-1.0, 1.0) var snow_target := -1.0
## 潮湿目标：0 = 变干；1 = 全湿
@export_range(0.0, 1.0) var wet_target := 0.0
@export var lightning := false
## 闪电间隔（秒）min/max
@export var lightning_interval := Vector2(3.0, 9.0)

const NUMERIC := ["rain", "snow", "cloud", "fog", "desaturate"]


func apply_dict(d: Dictionary) -> void:
	for k: String in d:
		set(k, d[k])
