@tool
extends VBoxContainer
## 编辑器面板「Pixel World」：设置主题、种子、尺寸、密度，一键生成 / 随机 / 另存为场景。
## 作用对象：当前场景里选中的 PWWorld；没有选中时用场景里第一个 PWWorld；都没有就新建一个。

var _theme: OptionButton
var _seed: SpinBox
var _size: SpinBox
var _trees: HSlider
var _houses: HSlider
var _bushes: HSlider
var _lamps: SpinBox
var _lake: CheckBox
var _status: Label
var _save_dialog: EditorFileDialog


func _ready() -> void:
	name = "Pixel World"
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "场景生成（P2）"
	add_child(title)

	_theme = OptionButton.new()
	for id in PWStyles.ready_ids():
		var st := PWStyles.get_style(id)
		_theme.add_item("%s %s" % [st.name, id])
	_theme.item_selected.connect(func(i): _size.value = PWStyles.get_style(PWStyles.ready_ids()[i]).size)
	_row("主题", _theme)
	_seed = _spin(0, 999999, 1, 7)
	_row("种子", _seed)
	_size = _spin(32, 192, 8, 80)
	_row("尺寸（米）", _size)
	_trees = _slider(1.0)
	_row("树木密度", _trees)
	_houses = _slider(1.0)
	_row("房屋密度", _houses)
	_bushes = _slider(1.0)
	_row("灌木密度", _bushes)
	_lamps = _spin(6, 20, 0.5, 10)
	_row("路灯间距", _lamps)
	_lake = CheckBox.new()
	_lake.text = "带湖"
	_lake.button_pressed = true
	add_child(_lake)

	var buttons := HBoxContainer.new()
	add_child(buttons)
	var gen := Button.new()
	gen.text = "生成"
	gen.pressed.connect(_generate)
	buttons.add_child(gen)
	var rnd := Button.new()
	rnd.text = "重新随机"
	rnd.pressed.connect(func():
		_seed.value = randi() % 1000000
		_generate())
	buttons.add_child(rnd)
	var save := Button.new()
	save.text = "另存为 .tscn"
	save.pressed.connect(_ask_save)
	buttons.add_child(save)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 200
	add_child(_status)

	_save_dialog = EditorFileDialog.new()
	_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.add_filter("*.tscn", "场景")
	_save_dialog.file_selected.connect(_save_to)
	add_child(_save_dialog)


func _row(label: String, control: Control) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 80
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	add_child(h)


func _spin(lo: float, hi: float, step: float, v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	return s


func _slider(v: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 2.0
	s.step = 0.05
	s.value = v
	s.custom_minimum_size.x = 100
	return s


## 找到要操作的 PWWorld：选中的 > 场景里第一个 > 新建
func _target() -> PWWorld:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_status.text = "请先打开或新建一个 3D 场景。"
		return null
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is PWWorld:
			return n
	var found := root.find_children("*", "PWWorld", true, false)
	if not found.is_empty():
		return found[0]
	if root is PWWorld:
		return root
	var w := PWWorld.new()
	w.name = "World"
	w.generate_on_ready = false
	root.add_child(w, true)
	w.owner = root
	return w


func _generate() -> void:
	var w := _target()
	if w == null:
		return
	w.theme = PWStyles.ready_ids()[_theme.selected]
	w.seed_value = int(_seed.value)
	w.size = int(_size.value)
	w.tree_density = _trees.value
	w.house_density = _houses.value
	w.bush_density = _bushes.value
	w.lamp_spacing = _lamps.value
	w.with_lake = _lake.button_pressed
	w.generate()
	EditorInterface.mark_scene_as_unsaved()
	_status.text = "已生成 %s #%d：%s\n摆放违规：%d" % [w.theme, w.seed_value, w.stats, w.violations.size()]


func _ask_save() -> void:
	var w := _target()
	if w == null or w.content() == null:
		_status.text = "先点「生成」。"
		return
	_save_dialog.current_file = "%s_%d.tscn" % [w.theme, w.seed_value]
	_save_dialog.popup_file_dialog()


## 把生成结果（静态网格、水面、鱼群）另存为独立场景：之后可以手工修改，不会被重新生成覆盖
func _save_to(path: String) -> void:
	var w := _target()
	if w == null or w.content() == null:
		return
	var root := Node3D.new()
	root.name = "%s_%d" % [w.theme.capitalize(), w.seed_value]
	var copy := w.content().duplicate()
	root.add_child(copy)
	_own(copy, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	root.free()
	_status.text = ("已保存到 " + path) if err == OK else ("保存失败：%s" % error_string(err))
	EditorInterface.get_resource_filesystem().scan()


func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)
	n.owner = owner_node
