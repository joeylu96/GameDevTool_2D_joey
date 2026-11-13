extends SceneTree
## 场景生成回归测试（无界面）：
##   godot --headless --path godot --script res://tests/test_world_gen.gd
## 对两种主题各跑多个种子，检查：
##   1. PWPlacement.validate() 没有任何违规
##   2. 独立复核：每盏路灯与每棵树之间，地面距离和树冠 / 灯头间距都满足规则（不依赖 validate 的实现）
##   3. 出生点能站人
##   4. 生成结果能打包成 .tscn
## 全部通过时打印 "ALL PASSED" 并以 0 退出，否则以 1 退出。

const P := preload("res://addons/pixel_world/world/pw_placement.gd")

var failures := 0


func _init() -> void:
	var seeds := [1, 7, 42, 1234, 99999]
	for theme in ["town", "forest", "plains"]:
		for s in seeds:
			_check(theme, s)
	print("ALL PASSED" if failures == 0 else "FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)


func _check(theme: String, s: int) -> void:
	var w := PWWorld.new()
	w.generate_on_ready = false
	w.theme = theme
	w.seed_value = s
	w.size = PWStyles.get_style(theme).size
	root.add_child(w)
	w.generate()
	var label := "%s#%d" % [theme, s]
	if not w.violations.is_empty():
		_fail(label, "摆放违规 %d 处，例如 %s" % [w.violations.size(), w.violations[0]])
	# 独立复核路灯与树
	var lamps: Array[Dictionary] = []
	var trees: Array[Dictionary] = []
	for it in w.placement.items():
		if it.cat == P.LAMP:
			lamps.append(it)
		elif it.cat == P.TREE:
			trees.append(it)
	var g := P.gap(P.LAMP, P.TREE)
	var bad := 0
	for l in lamps:
		for t in trees:
			var d: float = (l.pos as Vector2).distance_to(t.pos)
			if d < l.canopy + t.canopy + g - 0.001 or d < l.r + t.r + g - 0.001:
				bad += 1
	if bad > 0:
		_fail(label, "%d 对路灯和树靠得太近" % bad)
	# 土路要接在某条路上：土路矩形的上沿必须贴着一条道路
	if theme == "town" and w.with_lake:
		var paths: Array[Rect2] = []
		var roads: Array[Rect2] = []
		for it in w.placement.items():
			if it.cat == P.PATH:
				paths.append(it.rect)
			elif it.cat == P.ROAD:
				roads.append(it.rect)
		var linked := false
		for r in roads:
			if r.grow(0.3).intersects(paths[0]):
				linked = true
		if not linked:
			_fail(label, "通往码头的土路没有接到任何道路上：土路 %s，道路 %s" % [paths[0], roads])
	# 自然风格：水只能是大湖 / 河，不能有零散的小水坑（每片连通水域至少 60 平方米）
	if PWStyles.get_style(theme).get("generator", "") == "nature":
		var sizes := _water_components(w)
		if sizes.is_empty():
			_fail(label, "没有湖")
		for area in sizes:
			if area < 60:
				_fail(label, "有一片只有 %d 平方米的小水坑" % area)
				break
	var sp := Vector2(w.spawn_point.x, w.spawn_point.z)
	if not w.can_stand(sp):
		_fail(label, "出生点 %s 站不住" % sp)
	var packed := PackedScene.new()
	var copy := w.content().duplicate()
	_own(copy, copy)
	if packed.pack(copy) != OK:
		_fail(label, "无法打包成场景")
	copy.free()
	print("%s ok  lamps=%d trees=%d stats=%s" % [label, lamps.size(), trees.size(), w.stats])
	w.free()


## 每片连通水域的面积（网格顶点数 ≈ 平方米）
func _water_components(w: PWWorld) -> Array[int]:
	var n := w.grid_n + 1
	var seen := PackedByteArray()
	seen.resize(n * n)
	var out: Array[int] = []
	for j in n:
		for i in n:
			if seen[j * n + i] != 0 or w.get_h(i, j) >= w.water_y:
				continue
			var count := 0
			var stack: Array[Vector2i] = [Vector2i(i, j)]
			seen[j * n + i] = 1
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				count += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = c + d
					if q.x < 0 or q.y < 0 or q.x >= n or q.y >= n or seen[q.y * n + q.x] != 0:
						continue
					if w.get_h(q.x, q.y) < w.water_y:
						seen[q.y * n + q.x] = 1
						stack.append(q)
			out.append(count)
	return out


func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)


func _fail(label: String, msg: String) -> void:
	failures += 1
	print("FAIL %s: %s" % [label, msg])
