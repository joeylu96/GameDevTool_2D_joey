extends SceneTree
## 闪烁指标：godot --headless --path godot --script res://tests/flicker_toggles.gd -- <前缀> <帧数> <x> <y> <w> <h>
## 对区域内每个像素的亮度序列，统计「方向翻转」次数（变亮后又变暗，或反之，每次变化超过阈值才算）。
## 正常移动的阴影边缘只会单向变化；电流式闪烁会反复翻转。
## 输出：toggles = 每千像素的翻转次数；moving = 有过明显变化的像素比例（千分比）

const THR := 0.025

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var prefix := a[0]
	var n := int(a[1])
	var r := Rect2i(int(a[2]), int(a[3]), int(a[4]), int(a[5]))
	var count := r.size.x * r.size.y
	var last := PackedFloat32Array()
	last.resize(count)
	var dir := PackedInt32Array()
	dir.resize(count)
	var moved := PackedByteArray()
	moved.resize(count)
	var toggles := 0
	for i in n:
		var img := Image.load_from_file("%s_%02d.png" % [prefix, i])
		img.convert(Image.FORMAT_RGB8)
		var crop := img.get_region(r)
		var data := crop.get_data()
		for p in count:
			var l := (data[p * 3] * 0.299 + data[p * 3 + 1] * 0.587 + data[p * 3 + 2] * 0.114) / 255.0
			if i == 0:
				last[p] = l
				continue
			var d := l - last[p]
			if absf(d) > THR:
				var s := 1 if d > 0.0 else -1
				if dir[p] != 0 and s != dir[p]:
					toggles += 1
				dir[p] = s
				moved[p] = 1
				last[p] = l
	var mv := 0
	for p in count:
		mv += moved[p]
	print("TOGGLE toggles=%.2f moving=%.2f" % [1000.0 * toggles / count, 1000.0 * mv / count])
	quit()
