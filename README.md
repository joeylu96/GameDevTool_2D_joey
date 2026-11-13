# PixelWorld：3D 像素风场景工具链（Godot + Blender）

用来自动生成 3D 像素风的小镇和野外场景，并提供天气、昼夜系统和风格统一的 NPC。画面参考 `pixel.jpg`。
完整方案见 [docs/DESIGN.md](docs/DESIGN.md)；当前画面的关键参数和性能基线见 [docs/VISUAL_SPEC.md](docs/VISUAL_SPEC.md)。

## 环境要求（请与项目版本保持一致）

本项目锁定以下工具版本，Windows 和 macOS 上都使用同一版本：

| 工具 | 锁定版本 | 说明 |
|---|---|---|
| Godot | **4.7.2-stable**（标准版，非 .NET/Mono） | 只跟进 4.7.x 补丁版本 |
| Blender | **5.2 LTS**，当前 **5.2.4** | 只跟进 5.2.x 补丁版本，LTS 维护到 2028 年 7 月 |

**请尽量使用与上表完全一致的版本。** 版本不一致可能导致：

- 用更高的 Godot 版本打开工程会自动升级资源格式，其他成员用 4.7.2 再打开时可能报错。
- Blender 插件按 5.2 的 Python API 编写，其他版本不保证能用；导入 `.blend` 和导出 glTF 的结果也可能不同。

其他约定：

- **系统要求**：Windows 10 及以上；macOS 13 及以上，并且必须是 Apple Silicon（Blender 5.x 不支持 Intel Mac）。
- **一起升级**：补丁版本（如 Godot 4.7.3、Blender 5.2.5）发布后，所有成员一起升级，并同步更新本表。
- **大版本另议**：升级到 Godot 4.8 或 Blender 5.3 及以上需要先单独验证，确认插件和导入流程正常后再统一切换。
- **Blender 路径**：在 Godot 的「编辑器设置 → FileSystem → Import → Blender → Blender Path」中设置。这是每台电脑各自的设置，不随仓库同步。

## 目录

| 路径 | 内容 |
|---|---|
| `shared/style/` | 风格规范：调色板、像素密度、相机参数。全工具链只有这一份来源 |
| `godot/addons/pixel_world/` | Godot 4.7 插件 |
| `godot/addons/pixel_world/world/` | 场景生成（P2）：`PWWorld`、小镇 / 野外生成器、摆放规则、合批 |
| `godot/demo/` | 演示场景 |
| `godot/tests/` | 无界面回归测试和画面闪烁统计脚本 |
| `tools/sync_style.py` | 把 `style.json` 同步成 Godot 可用的常量文件 |
| `blender/` | Blender 插件（P3 阶段开始） |

## 运行 Demo

用 Godot 4.7 打开 `godot/project.godot`，按 F5 运行。

- 操作：WASD / 方向键控制小人走动（镜头跟随），Q/E 旋转镜头，滚轮缩放。可以走进湖边浅水，雨天踩进水洼会有波纹，靠近鱼群鱼会游开。
- 左上角面板：「Scene」切换小镇 / 野外，「New」换一个随机种子重新生成；切换天气、调整时间；「Walk」关闭后 WASD 和鼠标拖动改为平移镜头；「Pixel」「Tilt-shift」可开启复古像素渲染和移轴效果（默认关闭）。

也可以用命令行截图，方便验证效果：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path godot --rendering-driver opengl3 -- \
  --theme=wild --seed=42 --weather=snow --snap --hour=21 --screenshot=/tmp/shot.png
```

## 生成场景（P2）

- **编辑器里**：打开或新建一个 3D 场景，右侧停靠面板「Pixel World」里选主题（小镇 / 野外）、种子、尺寸和各类密度，点「生成」；不满意点「重新随机」；满意后「另存为 .tscn」，得到可以手工修改的静态场景。
- **代码里**：

```gdscript
var world := PWWorld.new()
world.theme = "town"        # 或 "wild"
world.seed_value = 42
world.size = 80             # 野外建议 128
add_child(world)            # generate_on_ready 默认为 true，加入场景树时自动生成
# 查询：world.ground_y(x, z)、world.water_depth(x, z)、world.can_stand(Vector2(x, z))、world.spawn_point
```

摆放规则（树、路灯、房屋、门前通道之间的间距等）和阴影规则见 [docs/VISUAL_SPEC.md](docs/VISUAL_SPEC.md)。
回归测试：`godot --headless --path godot --script res://tests/test_world_gen.gd`。

## 在自己的场景里使用

1. 把 `godot/addons/pixel_world` 复制到你的工程，并在「项目设置 → 插件」中启用。启用时会自动写入所需的全局 Shader 参数。
2. 打开一个 3D 场景，选择「项目 → 工具 → Pixel World: 添加昼夜/天气/相机」。
3. 模型材质使用 `shaders/pixel_world.gdshader`，就能自动响应积雪、潮湿、夜间发光和风。
4. 在代码中控制：

```gdscript
$WeatherSystem.set_weather("storm", 4.0)   # 可选：clear cloudy rain storm snow blizzard fog
$TimeOfDay.hour = 19.5
$TimeOfDay.hour_changed.connect(func(h): print(h))
```

## Web 导出

1. 在 Godot 中安装 4.7.2 导出模板：「编辑器 → 管理导出模板」。
2. 「项目 → 导出 → Web」，输出到 `build/web/`。
3. 用任意静态服务器预览，例如 `python3 -m http.server -d build/web`。导出已关闭多线程，不需要配置 COOP/COEP 响应头。
