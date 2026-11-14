@tool
class_name PWStyles
extends RefCounted
## 场景风格注册表。生成器、编辑器面板、主界面「场景生成器」都从这里读。
## 新增风格：在 STYLES 里加一项；ready = false 的风格会在界面上显示为「即将推出」。
##
## generator：
##   "town"   — pw_town_gen.gd（道路网 + 房屋 + 湖岸）
##   "nature" — pw_nature_gen.gd（连续地形 + 大湖 + 河流 + 植被），params 决定是森林还是平原

const STYLES := [
	{
		"id": "town", "name": "海边小镇", "en": "Seaside Town", "generator": "town", "size": 80, "ready": true,
		"desc": "街道网、朝路的房屋、路灯、篱笆、码头和灯塔，南边是湖。",
		"color": Color("c4473a"),
		"params": {},
	},
	{
		"id": "forest", "name": "森林", "en": "Forest", "generator": "nature", "size": 128, "ready": true,
		"desc": "起伏的林地，松树为主；一两片大湖，常有小河流出地图；营地、木屋、废墟由林间小路相连。",
		"color": Color("3a5f48"),
		"params": {
			"hill_amp": 4.2, "hill_freq": 0.022, "lakes": [1, 2], "lake_r": [11.0, 18.0], "river_chance": 0.75,
			"forest_cover": 0.42, "tree_density": 1.0, "pine_ratio": 0.78, "grove_trees": false, "hedgerows": false,
			"grass": 0.55, "flowers": 0.08, "rocks": 1.0, "pois": ["camp", "cabin", "ruins", "camp"],
		},
	},
	{
		"id": "plains", "name": "平原", "en": "Plains", "generator": "nature", "size": 128, "ready": true,
		"desc": "开阔的缓坡草原和花丛；一片大湖和一条河，零星的树丛与灌木篱；农舍、风车和草垛。",
		"color": Color("8fb36a"),
		"params": {
			"hill_amp": 1.6, "hill_freq": 0.014, "lakes": [1, 1], "lake_r": [14.0, 21.0], "river_chance": 1.0,
			"forest_cover": 0.86, "tree_density": 0.35, "lone_trees": 0.012, "pine_ratio": 0.2, "grove_trees": true, "hedgerows": true,
			"grass": 1.0, "flowers": 0.22, "rocks": 0.35, "pois": ["farm", "windmill", "camp"],
		},
	},
	{
		"id": "snowfield", "name": "雪原", "en": "Snowfield", "generator": "nature", "size": 128, "ready": true,
		"weather": "snow",
		"desc": "终年积雪的针叶林和起伏雪丘，一两片湖，木屋和营地；雪人等冬季摆件按标签自动摆放。",
		"color": Color("c9d3e3"),
		"params": {
			"hill_amp": 3.6, "hill_freq": 0.02, "lakes": [1, 2], "lake_r": [9.0, 15.0], "river_chance": 0.4,
			"forest_cover": 0.5, "tree_density": 0.9, "pine_ratio": 0.96, "grove_trees": false, "hedgerows": false,
			"grass": 0.12, "flowers": 0.0, "rocks": 1.1, "pois": ["cabin", "camp", "ruins", "cabin"],
			"blender": [{"tag": "winter", "density": 0.4, "where": "land", "semantic": ["props", "street"]},
				{"tag": "camp", "density": 0.05, "where": "land"}],
		},
	},
	{
		"id": "island", "name": "海岛", "en": "Island", "generator": "nature", "size": 112, "ready": true,
		"desc": "四面环海的小岛：一圈宽沙滩、椰子树和渔船，岛中间是长满阔叶树的小山，岸边有灯塔。",
		"color": Color("6f9c94"),
		"params": {
			"island": 0.8, "sand_h": 0.55, "hill_amp": 3.2, "hill_freq": 0.03, "lakes": [0, 1], "lake_r": [5.0, 7.0],
			"river_chance": 0.0, "forest_cover": 0.55, "tree_density": 0.55, "pine_ratio": 0.08, "grove_trees": false,
			"hedgerows": false, "grass": 0.75, "flowers": 0.16, "rocks": 0.6, "pois": ["cabin", "camp", "cabin"],
			"blender": [{"tag": "island", "density": 2.2, "where": "beach", "semantic": ["trees"]},
				{"tag": "island", "density": 0.6, "where": "land", "semantic": ["trees"]},
				{"tag": "shore", "density": 0.25, "where": "beach", "semantic": ["props"]},
				{"tag": "island", "density": 0.1, "where": "beach", "semantic": ["landmarks"], "max": 1}],
		},
	},
	{
		"id": "desert", "name": "沙漠绿洲", "en": "Desert Oasis", "generator": "nature", "size": 128, "ready": true,
		"desc": "起伏的沙丘、红岩石柱和仙人掌；中间一片绿洲湖，湖边一圈草地和椰子树。",
		"color": Color("d6a24e"),
		"params": {
			"desert": true, "oasis": 1.9, "terrain_mat": "terrain_desert", "hill_amp": 2.6, "hill_freq": 0.024,
			"lakes": [1, 1], "lake_r": [7.0, 10.0], "river_chance": 0.0, "forest_cover": 0.0, "tree_density": 0.0,
			"grass": 0.7, "flowers": 0.05, "rocks": 0.25, "pois": ["camp", "ruins", "camp"],
			"blender": [{"tag": "desert", "density": 1.6, "where": "oasis", "semantic": ["trees"]},
				{"tag": "desert", "density": 0.9, "where": "sand", "semantic": ["plants"]},
				{"tag": "desert", "density": 0.3, "where": "sand", "semantic": ["rocks"]}],
		},
	},
	{
		"id": "canyon", "name": "峡谷", "en": "Canyon", "generator": "nature", "size": 128, "ready": true,
		"desc": "红岩台地中间一条蜿蜒的河谷：三级台阶的崖壁，谷底有河，台地上零星的树和岩柱。",
		"color": Color("a3352d"),
		"params": {
			"canyon": true, "plateau": 8.0, "valley_w": 13.0, "terrain_mat": "terrain_canyon", "hill_amp": 3.0,
			"hill_freq": 0.02, "lakes": [0, 0], "forest_cover": 0.86, "tree_density": 0.25, "lone_trees": 0.02,
			"pine_ratio": 0.55, "grove_trees": false, "hedgerows": false, "grass": 0.35, "flowers": 0.04, "rocks": 1.3,
			"pois": ["camp", "ruins", "camp"],
			"blender": [{"tag": "canyon", "density": 0.35, "where": "land", "semantic": ["rocks"]},
				{"tag": "canyon", "density": 0.3, "where": "land", "semantic": ["plants"]}],
		},
	},
]


static func get_style(id: String) -> Dictionary:
	if id == "wild":
		id = "forest"  # 旧名字兼容
	for s: Dictionary in STYLES:
		if s.id == id:
			return s
	return STYLES[0]


static func ready_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in STYLES:
		if s.ready:
			out.append(s.id)
	return out
