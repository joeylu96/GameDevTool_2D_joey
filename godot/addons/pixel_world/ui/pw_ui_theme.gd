@tool
class_name PWUITheme
extends RefCounted
## 工具链界面的统一主题：深色半透明面板、圆角、暖色强调色、中文字体（思源黑体裁剪版，见 tools/subset_font.py）。

const FONT_PATH := "res://addons/pixel_world/ui/fonts/NotoSansSC-PW.otf"
const BG := Color(0.07, 0.08, 0.12, 0.96)
const PANEL := Color(0.11, 0.12, 0.18, 0.92)
const PANEL_HI := Color(0.16, 0.18, 0.26, 1.0)
const ACCENT := Color("ffc965")
const ACCENT_DARK := Color("f29a3f")
const TEXT := Color(0.92, 0.93, 0.96)
const TEXT_DIM := Color(0.62, 0.65, 0.74)

static var _theme: Theme


static func font() -> Font:
	if ResourceLoader.exists(FONT_PATH):
		var f: FontFile = load(FONT_PATH)
		if f.fallbacks.is_empty() and ThemeDB.fallback_font != null:
			f.fallbacks = [ThemeDB.fallback_font]
		return f
	return ThemeDB.fallback_font


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 15
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 8, 12))
	t.set_stylebox("panel", "Panel", box(PANEL, 8, 0))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var c := PANEL_HI
		match state:
			"hover":
				c = PANEL_HI.lightened(0.12)
			"pressed":
				c = ACCENT_DARK.darkened(0.25)
			"disabled":
				c = PANEL_HI.darkened(0.3)
			"focus":
				c = Color(0, 0, 0, 0)
		var sb := box(c, 6, 0)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		if state == "focus":
			sb.border_color = ACCENT
			sb.set_border_width_all(1)
		t.set_stylebox(state, "Button", sb)
		t.set_stylebox(state, "OptionButton", sb.duplicate())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_DIM.darkened(0.3))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_stylebox("panel", "ItemList", box(Color(0, 0, 0, 0.25), 6, 6))
	t.set_stylebox("selected", "ItemList", box(ACCENT_DARK.darkened(0.35), 4, 0))
	t.set_stylebox("selected_focus", "ItemList", box(ACCENT_DARK.darkened(0.25), 4, 0))
	t.set_stylebox("hovered", "ItemList", box(PANEL_HI, 4, 0))
	t.set_constant("v_separation", "ItemList", 6)
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.12), 3, 2))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT_DARK, 3, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 3, 2))
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.3), 4, 6))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.05, 0.08, 0.95), 4, 8))
	_theme = t
	return t


static func box(c: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


static func label(text: String, size := 15, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	if accent:
		var sb := box(ACCENT_DARK, 6, 0)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		b.add_theme_stylebox_override("normal", sb)
		var hv := sb.duplicate()
		hv.bg_color = ACCENT
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05))
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.05))
	return b
