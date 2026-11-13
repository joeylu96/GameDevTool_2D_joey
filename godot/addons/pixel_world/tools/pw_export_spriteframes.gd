extends SceneTree
## 把像素角色的精灵表导出成 Godot 的 SpriteFrames（给纯 2D 项目用，AnimatedSprite2D / AnimatedSprite3D 直接用）：
##   godot --headless --path godot --script res://addons/pixel_world/tools/pw_export_spriteframes.gd
## 每个角色生成 res://assets/sprites/<角色>/frames.tres，动画名是「动作_方向」：
##   idle_0 … idle_7、walk_0 …、attack_0 …（方向 0 = 正面，逆时针每 45° 一个；2D 横版游戏一般用 2 和 6）
## 循环动作（待机 / 走路 / 跑步 / 挥手）设为循环，攻击 / 受击 / 施法只播一次。帧用 AtlasTexture 引用原精灵表，不复制图片。

const DIR := "res://assets/sprites/"


func _init() -> void:
	var cat: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "catalog.json"))
	if not (cat is Dictionary):
		push_error("没有 %scatalog.json，先运行 tools/blender_build_sprites.py" % DIR)
		quit(1)
		return
	var f: int = cat.frame
	var dirs: int = cat.dirs
	var n := 0
	for c: Dictionary in cat.characters:
		if not c.has("anims"):
			continue
		var sf := SpriteFrames.new()
		sf.remove_animation("default")
		for anim: String in c.anims:
			var info: Dictionary = c.anims[anim]
			var tex: Texture2D = load(DIR + info.file)
			if tex == null:
				continue
			for d in dirs:
				var name := "%s_%d" % [anim, d]
				sf.add_animation(name)
				sf.set_animation_speed(name, float(info.fps))
				sf.set_animation_loop(name, bool(info.get("loop", true)))
				for k in int(info.count):
					var at := AtlasTexture.new()
					at.atlas = tex
					at.region = Rect2(k * f, d * f, f, f)
					sf.add_frame(name, at)
		var path := DIR + "%s/frames.tres" % c.id
		var err := ResourceSaver.save(sf, path)
		print("%s  %s  %d 个动画" % ["ok" if err == OK else "失败", path, sf.get_animation_names().size()])
		n += 1
	print("导出了 %d 个角色的 SpriteFrames" % n)
	quit(0)
