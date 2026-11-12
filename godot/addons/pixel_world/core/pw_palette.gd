@tool
extends RefCounted
## 调色板访问。数据来自 style/pw_style_data.gd（由 shared/style/style.json 生成）。

const Data := preload("res://addons/pixel_world/style/pw_style_data.gd")


static func c(name: String) -> Color:
	return Data.PALETTE.get(name, Color.MAGENTA)


static func texel_density() -> float:
	return Data.TEXEL_DENSITY


## 把任意颜色吸附到调色板中最近的颜色（用于导入的贴图/原画取色）。
static func nearest(col: Color) -> Color:
	var best := Color.MAGENTA
	var best_d := INF
	for k: String in Data.PALETTE:
		var p: Color = Data.PALETTE[k]
		var d := Vector3(p.r - col.r, p.g - col.g, p.b - col.b).length_squared()
		if d < best_d:
			best_d = d
			best = p
	return best
