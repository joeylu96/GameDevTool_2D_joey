@tool
extends EditorPlugin
## Pixel World 编辑器插件入口。
## - 编辑器顶部多一个主屏幕「Pixel World」（和 2D / 3D / 脚本 并列）：资源库、场景生成器、特效库、天气光照
##   （与 Demo 启动时看到的主界面是同一个 PWHub）。场景生成器的按钮是「生成到当前场景」。
## - 启用时把全局 shader 参数写入 project.godot
## - 工具菜单：一键给当前 3D 场景加上「昼夜 + 天气 + 相机」
## - 右侧停靠面板「Pixel World」：快速生成（主题 / 种子 / 尺寸 / 密度 → 生成 / 重新随机 / 另存为 .tscn）

const Globals := preload("res://addons/pixel_world/core/pw_globals.gd")
const Dock := preload("res://addons/pixel_world/editor/pw_world_dock.gd")
const MENU_ADD_RIG := "Pixel World: 添加昼夜/天气/相机"

var _dock: Control
var _hub: PWHub


func _enable_plugin() -> void:
	if Globals.ensure_project_settings():
		print("[PixelWorld] 已写入全局 shader 参数，如材质报错请重启编辑器。")
	Globals.ensure_runtime()


func _enter_tree() -> void:
	Globals.ensure_runtime()
	add_tool_menu_item(MENU_ADD_RIG, _add_rig)
	_dock = Dock.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_hub = PWHub.new()
	_hub.editor_mode = true
	_hub.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hub.generate_in_editor.connect(_generate_in_editor)
	EditorInterface.get_editor_main_screen().add_child(_hub)
	_make_visible(false)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ADD_RIG)
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _hub != null:
		_hub.queue_free()
		_hub = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Pixel World"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("WorldEnvironment", "EditorIcons")


func _make_visible(visible: bool) -> void:
	if _hub != null:
		_hub.visible = visible
		# 不显示时整个主界面（含预览里的昼夜和天气）停止运行，不占资源、不改全局参数
		_hub.process_mode = Node.PROCESS_MODE_INHERIT if visible else Node.PROCESS_MODE_DISABLED


## 场景生成器「生成到当前场景」：用当前场景里的 PWWorld（没有就新建一个）
func _generate_in_editor(cfg: Dictionary) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_warning("[PixelWorld] 请先打开或新建一个 3D 场景，再点「生成到当前场景」。")
		return
	var w: PWWorld = null
	var found := root.find_children("*", "PWWorld", true, false)
	if not found.is_empty():
		w = found[0]
	elif root is PWWorld:
		w = root
	else:
		w = PWWorld.new()
		w.name = "World"
		w.generate_on_ready = false
		root.add_child(w, true)
		w.owner = root
	PWHub.apply_config(w, cfg)
	w.generate()
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.set_main_screen_editor("3D")
	print("[PixelWorld] 已生成 %s #%d 到 %s" % [w.theme, w.seed_value, root.name])


func _add_rig() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_warning("[PixelWorld] 请先打开一个 3D 场景。")
		return
	var ur := get_undo_redo()
	ur.create_action("Pixel World: Add Rig")
	for spec in [["TimeOfDay", PWTimeOfDay], ["WeatherSystem", PWWeatherSystem], ["CameraRig", PWCameraRig]]:
		if root.find_child(spec[0], false) != null:
			continue
		var n: Node = spec[1].new()
		n.name = spec[0]
		ur.add_do_method(root, "add_child", n, true)
		ur.add_do_method(n, "set_owner", root)
		ur.add_do_reference(n)
		ur.add_undo_method(root, "remove_child", n)
	ur.commit_action()
