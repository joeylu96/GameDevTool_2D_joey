@tool
extends EditorPlugin
## Pixel World 编辑器插件入口。
## - 启用时把全局 shader 参数写入 project.godot
## - 工具菜单：一键给当前 3D 场景加上「昼夜 + 天气 + 相机」

const Globals := preload("res://addons/pixel_world/core/pw_globals.gd")
const MENU_ADD_RIG := "Pixel World: 添加昼夜/天气/相机"


func _enable_plugin() -> void:
	if Globals.ensure_project_settings():
		print("[PixelWorld] 已写入全局 shader 参数，如材质报错请重启编辑器。")
	Globals.ensure_runtime()


func _enter_tree() -> void:
	Globals.ensure_runtime()
	add_tool_menu_item(MENU_ADD_RIG, _add_rig)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ADD_RIG)


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
