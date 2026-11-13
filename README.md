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
| `godot/addons/pixel_world/world/` | 场景生成：`PWWorld`、风格表 `PWStyles`、小镇 / 自然（森林、平原）生成器、草、摆放规则、合批 |
| `godot/addons/pixel_world/ui/` | 主界面 `PWHub`（资源库 / 场景生成器 / 特效库 / 天气光照）、3D 预览、界面主题、中文字体 |
| `godot/assets/blender/` | Blender 生成的资产（.glb + `catalog.json`），由 `tools/blender_build_assets.py` 产出 |
| `godot/demo/` | 演示场景 |
| `godot/tests/` | 无界面回归测试和画面闪烁统计脚本 |
| `blender/pixel_world_blender/` | Blender 5.2 插件（P3）：参数化资产生成器、像素贴图、glTF 导出 |
| `tools/sync_style.py` | 把 `style.json` 同步成 Godot 可用的常量文件 |
| `tools/blender_build_assets.py` | 命令行批量生成 Blender 资产 |
| `tools/subset_font.py` | 裁剪中文界面字体（思源黑体，OFL 许可） |

## 运行 Demo

用 Godot 4.7 打开 `godot/project.godot`，按 F5 运行。启动后先看到**主界面**：

- **场景生成器**：选风格（海边小镇、森林、平原；雪原、海岛、沙漠绿洲、峡谷即将推出），设种子 / 尺寸 / 密度，「预览」后「进入场景」。
- **资源库**：按分类浏览所有资源，3D 预览可拖动旋转、滚轮缩放，「换一批」看同一资源放进场景时的不同变化；「Blender 资产」分类是 P3 生成的模型。
- **特效库**：天气、积水涟漪、积雪、夜间灯光、水面，在演示小场景里实时查看。
- **天气光照**：拖动时间看一天的光线，查看昼夜关键帧。

进入场景后：WASD / 方向键走动（镜头跟随），Q/E 旋转镜头，滚轮缩放；左上角面板可回到主界面、换一个场景、切换天气和时间、开关像素风和移轴。
在 Godot 编辑器里，插件会在顶部多一个「Pixel World」主屏幕（与 2D / 3D / 脚本 并列），内容相同，按钮是「生成到当前场景」。

也可以用命令行截图，方便验证效果：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path godot --rendering-driver opengl3 -- \
  --theme=forest --seed=42 --weather=snow --snap --hour=21 --screenshot=/tmp/shot.png
```

## 生成场景

- **编辑器里**：打开或新建一个 3D 场景，在「Pixel World」主屏幕的场景生成器里点「生成到当前场景」；或用右侧停靠面板「Pixel World」快速生成，满意后「另存为 .tscn」，得到可以手工修改的静态场景。
- **代码里**：

```gdscript
var world := PWWorld.new()
world.theme = "town"        # 或 "forest"、"plains"（见 PWStyles）
world.seed_value = 42
world.size = 80             # 森林 / 平原建议 128
add_child(world)            # generate_on_ready 默认为 true，加入场景树时自动生成
# 查询：world.ground_y(x, z)、world.water_depth(x, z)、world.can_stand(Vector2(x, z))、world.spawn_point
```

摆放规则、草的规则、水系规则和阴影规则见 [docs/VISUAL_SPEC.md](docs/VISUAL_SPEC.md)。

## Blender 资产（P3）

需要 Blender 5.2 LTS。两种用法：

- **命令行批量生成**（推荐，Windows / macOS 一样）：在仓库根目录运行
  `blender -b -P tools/blender_build_assets.py`（可加 `-- --variants 6 --only cottage,well`），
  输出到 `godot/assets/blender/`；然后打开 Godot 编辑器（或 `godot --headless --path godot --import`）导入。
- **在 Blender 里交互使用**：把 `blender/pixel_world_blender` 文件夹安装为插件（编辑 → 偏好设置 → 插件 → 从磁盘安装，选这个文件夹打包的 zip，或直接复制到 Blender 的 addons 目录），
  3D 视图侧边栏（N）出现「Pixel World」标签页：选资产和种子「生成」，或「导出全部到 Godot」。

目前的生成器：农舍、松树、石井、集市摊位（`blender/pixel_world_blender/generators/`）。它们读取同一份 `shared/style/style.json`，
像素密度 32 texel/米、只用调色板颜色；导入 Godot 后材质自动换成统一的 `pixel_world` 材质，所以积雪、潮湿、夜间窗户发光和代码生成的资产完全一样。
小镇会把石井和集市摊位摆在路边（同样经过摆放规则检查）。
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
