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
		"desc": "现代海边小镇：沥青路和白色车道线，白墙大玻璃窗的现代住宅、街角咖啡店，LED 路灯、长椅、垃圾桶、公交站，路边停着小汽车；码头和灯塔，南边是湖。",
		"color": Color("c4473a"),
		"params": {
			"houses": ["bl_modern_house", "bl_modern_house", "bl_modern_house", "bl_town_house"],
			"specials": ["bl_modern_shop", "bl_modern_shop"], "lamp": "bl_modern_street_lamp", "road": "asphalt", "road_wobble": 0.03,
			"style_tag": "modern", "cars": 0.35, "fence_styles": [3, 0], "bench": "bl_modern_bench",
			"prop_counts": {"bl_well": 0, "bl_handcart": 0, "bl_signpost": 0, "bl_market_stall": 0, "bl_spec_notice_board": 1,
				"bl_modern_bench": 2, "bl_trash_bin": 4, "bl_bus_stop": 1},
		},
	},
	{
		"id": "medieval", "name": "中世纪小镇", "en": "Medieval Town", "generator": "town", "size": 96, "ready": true,
		"desc": "中世纪海边小镇（参考 res/中世纪海边小镇.jpg）：米色石砌的楼房和红瓦屋顶，一座座红色锥顶的圆塔；米色石板的街道、广场和滨海大道，木码头旁停着帆船；背海的三面是城墙和城门。",
		"color": Color("8a6a4a"),
		"params": {"medieval": true, "lake": true, "pier": false, "harbor": true, "promenade": true, "road": "flagstone",
			"trees": 0.25, "houses": ["bl_medieval_house"],
			"specials": ["bl_med_round_tower", "bl_chapel", "bl_tavern", "bl_med_round_tower", "bl_smithy"], "lamp": "bl_lantern_post", "style_tag": "medieval", "road_wobble": 0.18,
			"fence_styles": [1, 2, 3]},
	},
	{
		"id": "cn_village", "name": "中国乡村", "en": "Chinese Village (1980s-90s)", "generator": "town", "size": 96, "ready": true,
		"desc": "八九十年代的中国乡村：黄土路边一户户红砖瓦房，砖砌院墙和门楼围成农家院，门上贴着红对联；电线杆、大喇叭、小卖部，院里压水井、水缸、晾衣杆、鸡舍猪圈，门口停着二八自行车和手扶拖拉机；村边是菜地、麦地和池塘。",
		"color": Color("b0563c"),
		"params": {"houses": ["bl_cn_brick_house", "bl_cn_brick_house", "bl_cn_brick_house", "bl_cn_timber_house"], "specials": ["bl_cn_shop"],
			"big_trees": true, "lamp": "bl_cn_utility_pole", "lamp_pool": false,
			"road": "dirt", "road_wobble": 0.45, "curbs": false, "pier": false, "style_tag": "cn_village", "yard": "courtyard",
			"yard_depth": [5.0, 6.5], "fields": 22, "trees": 0.45, "benches": false, "yard_chance": 0.95,
			"lamp_spacing": 2.2, "lamp_sides": [1], "pine_ratio": 0.0, "pine_belt": 0.1,
			"prop_counts": {"bl_well": 0, "bl_market_stall": 0, "bl_bench": 0, "bl_spec_notice_board": 0, "bl_signpost": 0,
				"bl_cn_bicycle": 3, "bl_cn_water_vat": 3, "bl_cn_clothes_line": 3, "bl_cn_chicken_coop": 2, "bl_cn_pigpen": 2,
				"bl_cn_hand_pump": 2, "bl_cn_walking_tractor": 2, "bl_cn_threshing_ground": 1, "bl_cn_loudspeaker_pole": 1,
				"bl_cn_stone_mill": 1, "bl_haystack": 3, "bl_cn_tractor": 2,
				"bl_cn_bamboo_table_set": 0, "bl_cn_drying_tray": 1, "bl_cn_pickle_jars": 0, "bl_cn_firewood_stack": 2,
				"bl_cn_basin_stool": 0}},
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
			"tree_scale": [0.6, 1.4],
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
			"forest_cover": 0.5, "tree_density": 0.9, "pine_ratio": 0.82, "grove_trees": false, "hedgerows": false,
			"tree_scale": [0.55, 1.45], "clearings": -0.25, "lone_trees": 0.05,
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
			"desert": true, "rock_tint": Color(1.25, 0.9, 0.72), "oasis": 1.9, "terrain_mat": "terrain_desert", "hill_amp": 2.6, "hill_freq": 0.024,
			"lakes": [1, 1], "lake_r": [7.0, 10.0], "river_chance": 0.0, "forest_cover": 0.0, "tree_density": 0.0,
			"grass": 0.7, "flowers": 0.05, "rocks": 0.25, "pois": ["camp", "ruins", "camp"],
			"blender": [{"tag": "desert", "density": 1.6, "where": "oasis", "semantic": ["trees"]},
				{"tag": "desert", "density": 0.9, "where": "sand", "semantic": ["plants"]},
				{"tag": "desert", "density": 0.3, "where": "sand", "semantic": ["rocks"]}],
		},
	},
	{
		"id": "canyon", "name": "峡谷", "en": "Canyon", "generator": "nature", "size": 128, "ready": true,
		"desc": "红岩台地间一条蜿蜒的河谷和分叉的支沟：厚薄不一的岩层台阶、被水冲出的冲沟，谷底有河，台地上零星的树和岩柱。",
		"color": Color("a3352d"),
		"params": {
			"canyon": true, "rock_tint": Color(1.3, 0.86, 0.7), "plateau": 14.0, "valley_w": 14.0, "terrain_mat": "terrain_canyon", "hill_amp": 2.2,
			"hill_freq": 0.02, "lakes": [0, 0], "forest_cover": 0.86, "tree_density": 0.25, "lone_trees": 0.02,
			"pine_ratio": 0.55, "grove_trees": false, "hedgerows": false, "grass": 0.12, "flowers": 0.02, "rocks": 1.3,
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
