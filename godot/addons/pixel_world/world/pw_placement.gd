@tool
class_name PWPlacement
extends RefCounted
## 摆放登记与规则检查。场景里每个东西都在这里登记，摆放前先问「这里能不能放」，
## 所以树不会长进路灯、房子、路面，路灯不会立在门口，篱笆不会穿过树。
##
## 每个物体有两层占地：
##   - 地面层 r：树干 / 灯杆 / 墙体在地面的占地半径（矩形物体用 Rect2）
##   - 高空层 canopy：树冠、灯头、屋檐在半空的伸展半径（没有就等于 r）
## 两个物体允许的最小距离 = 两者对应层半径之和 + 类别间距（见 GAP 表）。
## 高空层只在两者都「高」（≥ 2 米）时比较：树冠可以伸到灌木上方，但不能和灯头、屋檐、别的树冠打架。
##
## 角色碰撞用另一份更紧的数据：solid（树干、墙体、灯杆的实际碰撞半径）。

## 类别
const HOUSE := &"house"
const ROAD := &"road"
const PATH := &"path"
const LAMP := &"lamp"
const TREE := &"tree"
const BUSH := &"bush"
const ROCK := &"rock"
const FENCE := &"fence"
const BENCH := &"bench"
const PROP := &"prop"       # 木箱、木桶、营火等
const LANDMARK := &"landmark"
const DOOR := &"door"       # 门前通道（保留区，什么都不能放）
const WATER := &"water"
const GRASS := &"grass"     # 草丛：只检查不登记（见 PWGrass）

## 类别之间额外的间距（米），按字母顺序的「a|b」查表；没列出的用 DEFAULT_GAP
const DEFAULT_GAP := 0.3
const GAP := {
	"lamp|tree": 0.6,      # 树冠和灯头之间要留出空隙，灯光才照得到地面
	"house|tree": 0.8,     # 树冠不能扎进屋檐
	"tree|tree": -0.35,    # 树冠允许轻微交叠（自然的林子），但树干不能挤在一起（见 TRUNK_GAP）
	"road|tree": 0.6,
	"path|tree": 0.4,
	"fence|tree": 0.4,
	"bench|tree": 0.3,
	"door|tree": 1.0,
	"landmark|tree": 1.0,
	"lamp|lamp": 4.0,
	"door|lamp": 0.8,
	"door|fence": 0.0,
	"bush|door": 0.4,
	"bush|road": 0.2,
	"bush|bush": -0.2,
	"rock|rock": 0.1,
	"road|rock": 0.4,
	"house|house": 1.5,
	"house|road": 1.2,
	"bench|lamp": 0.6,
	# 本来就伸进水里的东西
	"landmark|water": -99.0,
	"path|water": -99.0,
	# 「区域」之间本来就是相连的（相邻水块、道路接路口、土路接主路），互不检查
	"water|water": -99.0,
	"road|road": -99.0,
	"path|path": -99.0,
	"path|road": -99.0,
	"road|water": -99.0,
	"door|door": -99.0,
	"door|house": 0.0,         # 门前通道紧贴自家正门（相接可以，压进去不行）
	"landmark|path": -99.0,    # 小路通进兴趣点
	# 草丛（半径约 0.12 米）：不长在路、水、建筑、设施底下；树干和灌木旁边可以长
	"grass|road": 0.15,
	"grass|path": 0.05,
	"grass|door": 0.1,
	"grass|house": 0.15,
	"grass|water": 0.25,
	"grass|tree": 0.05,
	"grass|bush": -0.25,
	"grass|rock": 0.0,
	"grass|fence": 0.05,
	"grass|lamp": 0.05,
	"grass|bench": 0.1,
	"grass|prop": 0.1,
	"grass|landmark": 0.2,
}
## 两棵树的树干之间至少这么远（树冠可以交叠，但树干不能贴在一起）
const TRUNK_GAP := 1.6
## 「高」物体的门槛：高空层只在两个物体都超过这个高度时比较
const TALL := 2.0

const CELL := 4.0

## 一条记录：{cat, pos: Vector2, r: float, canopy: float, tall: bool, rect: Rect2（矩形物体）, id: int}
var _cells := {}   # Vector2i -> Array[Dictionary]
var _items: Array[Dictionary] = []
## 角色碰撞：圆 [Vector3(x, z, r)] 和矩形
var solid_circles: Array[Vector3] = []
var solid_rects: Array[Rect2] = []


static func gap(a: StringName, b: StringName) -> float:
	var k := "%s|%s" % [a, b] if String(a) < String(b) else "%s|%s" % [b, a]
	return GAP.get(k, DEFAULT_GAP)


## 登记圆形物体。canopy < 0 时取 r；tall = 是否有 2 米以上的部分（树、路灯）
func add_circle(cat: StringName, pos: Vector2, r: float, canopy := -1.0, tall := false) -> Dictionary:
	var it := {"cat": cat, "pos": pos, "r": r, "canopy": canopy if canopy >= 0.0 else r, "tall": tall,
		"rect": Rect2(), "id": _items.size()}
	_insert(it, Rect2(pos - Vector2.ONE * maxf(r, it.canopy), Vector2.ONE * 2.0 * maxf(r, it.canopy)))
	return it


## 登记矩形物体（房屋、道路、篱笆、保留区）。canopy = 屋檐等向外伸出的距离
func add_rect(cat: StringName, rect: Rect2, canopy := 0.0, tall := false) -> Dictionary:
	var it := {"cat": cat, "pos": rect.get_center(), "r": 0.0, "canopy": canopy, "tall": tall,
		"rect": rect, "id": _items.size()}
	_insert(it, rect.grow(canopy))
	return it


## 这个圆形物体能不能放在这里
func can_place(cat: StringName, pos: Vector2, r: float, canopy := -1.0, tall := false) -> bool:
	return _first_conflict({"cat": cat, "pos": pos, "r": r, "canopy": canopy if canopy >= 0.0 else r,
		"tall": tall, "rect": Rect2(), "id": -1}).is_empty()


## 这个矩形物体能不能放在这里
func can_place_rect(cat: StringName, rect: Rect2, canopy := 0.0, tall := false) -> bool:
	return _first_conflict({"cat": cat, "pos": rect.get_center(), "r": 0.0, "canopy": canopy,
		"tall": tall, "rect": rect, "id": -1}).is_empty()


## 检查已登记的所有物体，返回违规列表（每项是一段说明文字）。生成器最后调用一次作为保险。
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	for it in _items:
		var c := _first_conflict(it)
		if not c.is_empty() and c.id > it.id:
			out.append("%s@(%.1f,%.1f) 与 %s@(%.1f,%.1f) 太近" % [it.cat, it.pos.x, it.pos.y, c.cat, c.pos.x, c.pos.y])
	return out


func count(cat: StringName = &"") -> int:
	if cat == &"":
		return _items.size()
	var n := 0
	for it in _items:
		if it.cat == cat:
			n += 1
	return n


func items() -> Array[Dictionary]:
	return _items


# ---------------------------------------------------------------- 内部

func _insert(it: Dictionary, bounds: Rect2) -> void:
	_items.append(it)
	for k in _cell_keys(bounds):
		if not _cells.has(k):
			_cells[k] = []
		_cells[k].append(it)


func _cell_keys(b: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0 := floori(b.position.x / CELL)
	var x1 := floori(b.end.x / CELL)
	var y0 := floori(b.position.y / CELL)
	var y1 := floori(b.end.y / CELL)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			out.append(Vector2i(x, y))
	return out


func _first_conflict(it: Dictionary) -> Dictionary:
	var reach := maxf(it.r, it.canopy) + 6.0  # 最大间距 + 对方半径的保守上限
	var b: Rect2 = it.rect.grow(reach) if it.rect.has_area() else Rect2(it.pos - Vector2.ONE * reach, Vector2.ONE * 2.0 * reach)
	var seen := {}
	for k in _cell_keys(b):
		if not _cells.has(k):
			continue
		for o: Dictionary in _cells[k]:
			if o.id == it.id or seen.has(o.id):
				continue
			seen[o.id] = true
			if _conflicts(it, o):
				return o
	return {}


func _conflicts(a: Dictionary, b: Dictionary) -> bool:
	var g := gap(a.cat, b.cat)
	# 地面层
	if _dist(a, b, a.r, b.r) < g:
		return true
	# 两棵树：树干间距
	if a.cat == TREE and b.cat == TREE and a.pos.distance_to(b.pos) < TRUNK_GAP:
		return true
	# 高空层：两者都高时，树冠 / 灯头 / 屋檐不能相互穿插
	if a.tall and b.tall:
		if _dist(a, b, a.canopy, b.canopy) < g:
			return true
	# 树冠伸到矮的矩形区（道路、门前通道）上方：道路上空要留出净空，门口不能被树冠挡住
	elif (a.cat == TREE and (b.cat == ROAD or b.cat == DOOR)) or (b.cat == TREE and (a.cat == ROAD or a.cat == DOOR)):
		if _dist(a, b, a.canopy * 0.6, b.canopy * 0.6) < g:
			return true
	return false


## 两个物体（圆或矩形）在给定半径下的间距（负数 = 重叠）
func _dist(a: Dictionary, b: Dictionary, ra: float, rb: float) -> float:
	var ar: bool = a.rect.has_area()
	var br: bool = b.rect.has_area()
	if not ar and not br:
		return (a.pos as Vector2).distance_to(b.pos) - ra - rb
	if ar and br:
		var r1: Rect2 = (a.rect as Rect2).grow(ra)
		var r2: Rect2 = (b.rect as Rect2).grow(rb)
		var gx := maxf(r1.position.x - r2.end.x, r2.position.x - r1.end.x)  # >0 分开，=0 贴边，<0 重叠
		var gy := maxf(r1.position.y - r2.end.y, r2.position.y - r1.end.y)
		if gx < -0.001 and gy < -0.001:
			return maxf(gx, gy)  # 真正重叠：负的穿入深度
		return Vector2(maxf(gx, 0.0), maxf(gy, 0.0)).length()
	var rect: Rect2 = a.rect if ar else b.rect
	var p: Vector2 = b.pos if ar else a.pos
	var rr := (ra if ar else rb)
	var rc := (rb if ar else ra)
	var g := rect.grow(rr)
	var q := Vector2(clampf(p.x, g.position.x, g.end.x), clampf(p.y, g.position.y, g.end.y))
	if g.has_point(p):
		return -1.0
	return p.distance_to(q) - rc
