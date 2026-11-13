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
	{"id": "snowfield", "name": "雪原", "en": "Snowfield", "ready": false, "color": Color("c9d3e3"),
		"desc": "终年积雪的针叶林与冰湖（规划中）。"},
	{"id": "island", "name": "海岛", "en": "Island", "ready": false, "color": Color("6f9c94"),
		"desc": "被海包围的小岛、沙滩与渔村（规划中）。"},
	{"id": "desert", "name": "沙漠绿洲", "en": "Desert Oasis", "ready": false, "color": Color("d6a24e"),
		"desc": "沙丘、岩柱和一片绿洲（规划中）。"},
	{"id": "canyon", "name": "峡谷", "en": "Canyon", "ready": false, "color": Color("a3352d"),
		"desc": "红岩峡谷与溪流（规划中）。"},
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
