class_name PWNavGrid
extends RefCounted
## NPC 寻路网格：把场景按 cell 米一格划分，用 can_stand 标出能走的格子，AStarGrid2D 求路径。
## 一个场景建一次（几十毫秒），所有 NPC 共用。
##   var nav := PWNavGrid.new()
##   nav.build(Rect2(-40, -40, 80, 80), world.can_stand)
##   var pts := nav.find_path(npc.position, target)   # 世界坐标的路点（不含 y）

var cell := 1.0
var origin := Vector2.ZERO
var astar := AStarGrid2D.new()


func build(area: Rect2, can_stand: Callable, cell_size := 1.0) -> void:
	cell = cell_size
	origin = area.position
	var n := Vector2i(ceili(area.size.x / cell), ceili(area.size.y / cell))
	astar.region = Rect2i(Vector2i.ZERO, n)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for j in n.y:
		for i in n.x:
			var p := origin + (Vector2(i, j) + Vector2(0.5, 0.5)) * cell
			if not can_stand.call(p):
				astar.set_point_solid(Vector2i(i, j), true)


func _to_cell(p: Vector3) -> Vector2i:
	var c := Vector2i(floori((p.x - origin.x) / cell), floori((p.z - origin.y) / cell))
	return c.clamp(astar.region.position, astar.region.end - Vector2i.ONE)


func is_walkable(p: Vector3) -> bool:
	return not astar.is_point_solid(_to_cell(p))


## 从 a 到 b 的路点（世界坐标，y = 0）。b 不可达时走到离它最近的可达格子；起点在障碍里（比如刚出门）也能找路
func find_path(a: Vector3, b: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var ca := _to_cell(a)
	var cb := _to_cell(b)
	var was_solid := astar.is_point_solid(ca)
	astar.set_point_solid(ca, false)
	var ids := astar.get_id_path(ca, cb, true)
	astar.set_point_solid(ca, was_solid)
	# 每隔一格取一个路点，最后一个用精确目标（如果目标格可走）
	for k in range(1, ids.size()):
		if k % 2 == 0 or k == ids.size() - 1:
			var c := ids[k]
			out.append(Vector3(origin.x + (c.x + 0.5) * cell, 0.0, origin.y + (c.y + 0.5) * cell))
	if not out.is_empty() and not astar.is_point_solid(cb):
		out[out.size() - 1] = Vector3(b.x, 0.0, b.z)
	return out
