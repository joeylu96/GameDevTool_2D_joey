extends SceneTree
## 鱼群回归测试（无界面）：godot --headless --path godot --script res://tests/test_fish.gd
## 两种主题各几个种子，模拟 60 秒（每帧 1/60 秒），其中一半时间有「玩家」在岸边来回走、不断惊吓鱼群；
## 每一帧检查每条鱼都在水里（水深 ≥ min_depth）且在活动范围内。

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame  # 等场景树开始运行，节点才算「在树里」
	for theme in ["town", "wild"]:
		for s in [1, 7, 42]:
			_check(theme, s)
	print("ALL PASSED" if failures == 0 else "FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)


func _check(theme: String, s: int) -> void:
	var w := PWWorld.new()
	w.generate_on_ready = false
	w.theme = theme
	w.seed_value = s
	w.size = 128 if theme == "wild" else 80
	root.add_child(w)
	w.generate()
	var label := "%s#%d" % [theme, s]
	var fish := w.fish
	if fish == null:
		print("%s 没有鱼群，跳过" % label)
		w.free()
		return
	var threat := Node3D.new()
	root.add_child(threat)
	fish.threat = threat
	var bad := 0
	var frames := 3600
	for i in frames:
		# 后半段让「玩家」沿着鱼群的出生点来回扫，逼鱼逃跑
		if i > frames / 2 and not fish._fish.is_empty():
			var f: Dictionary = fish._fish[(i / 30) % fish._fish.size()]
			threat.global_position = (f.pos as Vector3) + Vector3(0.8, 0, 0.8)
		else:
			threat.global_position = Vector3(9999, 0, 9999)
		fish._process(1.0 / 60.0)
		for f in fish._fish:
			var p: Vector3 = f.pos
			if fish._depth(p) < fish.min_depth - 0.001 or not fish.area.has_point(Vector2(p.x, p.z)):
				bad += 1
	if bad > 0:
		failures += 1
		print("FAIL %s: %d 次出现在浅水 / 岸上" % [label, bad])
	else:
		print("%s ok  鱼 %d 条，%d 帧全部在水里" % [label, fish._fish.size(), frames])
	threat.free()
	w.free()
