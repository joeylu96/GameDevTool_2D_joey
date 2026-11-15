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
| `godot/addons/pixel_world/world/` | 场景生成：`PWWorld`、风格表 `PWStyles`（7 种风格）、小镇 / 自然生成器、草、摆放规则、合批 |
| `godot/addons/pixel_world/ui/` | 主界面 `PWHub`（场景生成器 / 资源库 / AI 资产工坊 / 特效库 / 天气光照）、3D 预览、界面主题、中文字体 |
| `godot/assets/blender/` | Blender 生成的资产（.glb + `catalog.json`），由 `tools/blender_build_assets.py` 产出 |
| `godot/assets/sprites/` | HD-2D 像素角色：每个角色一个文件夹，每个动作一张精灵表（8 方向），`frames.tres` 是给 2D 项目用的 SpriteFrames |
| `godot/addons/pixel_world/actors/` | 角色 `PWCharacter`、像素精灵显示 `PWSpriteVisual`、NPC `PWNPC`、寻路网格 `PWNavGrid`、鱼群 |
| `godot/addons/pixel_world/vfx/` | 动作特效 `PWVFX`（攻击、受击、法术、增益、移动） |
| `godot/demo/` | 演示场景 |
| `godot/tests/` | 无界面回归测试和画面闪烁统计脚本 |
| `blender/pixel_world_blender/` | Blender 5.2 插件：参数化资产生成器、按规格拼装摆件、像素贴图、glTF 导出（P3）；像素角色渲染 `sprites.py`（P4） |
| `blender/pw_specs/` | 资产规格（纯 Python）：角色 / 动作 / 摆件的格式、校验、给大模型的系统提示 |
| `shared/asset_specs/` | 规格文件：AI 资产工坊（或手写）生成的角色、动作、摆件都存在这里，可以手改后重新生成 |
| `tools/sync_style.py` | 把 `style.json` 同步成 Godot 可用的常量文件 |
| `tools/blender_build_assets.py` | 命令行批量生成 Blender 资产 |
| `tools/blender_build_sprites.py` | 命令行生成像素角色精灵表 |
| `tools/pw_asset_server.py` + `tools/workshop/` | **AI 资产工坊**：本地网页 + 生成服务（见 [docs/ASSET_WORKSHOP.md](docs/ASSET_WORKSHOP.md)） |
| `tools/workshop_selftest.py` | 资产工坊自检（模拟模型，不花钱） |
| `tools/extract_colors.py` | 从原画提取主色（Blender 无界面运行） |
| `tools/subset_font.py` | 裁剪中文界面字体（思源黑体，OFL 许可） |

## 运行 Demo

用 Godot 4.7 打开 `godot/project.godot`，按 F5 运行。启动后先看到**主界面**：

- **场景生成器**：选风格（海边小镇、森林、平原、雪原、海岛、沙漠绿洲、峡谷），设种子 / 尺寸 / 密度，「预览」后「进入场景」。
- **资源库**：按分类 / 子分类浏览所有资源（可以新增分类、子分类，选中资源用「移动到」换位置），「换一批」看同一资源放进场景时的不同变化。树木、灌木会随机撒几个（每个都不一样），路灯、篱笆等排出全部款式，角色只放一个；「角色」分类里有像素精灵角色，「Blender 资产」分类是 P3 生成的模型。
- **特效库**：分「天气 / 环境 / 动作」三类；动作特效（斩击、火球、爆炸、落雷、治疗、魔法阵、护盾、尘土等）由演示角色施放，可「播放」或「循环播放」。
- **3D 预览的操作**：预览不会自己转。底部按钮：左转、右转、抬高、压低、放大、缩小、重置；鼠标放在预览上时也可以用键盘：←→ 旋转、↑↓ 俯仰、WASD 平移、+/- 缩放、R 重置；左键拖动旋转、右键拖动平移、滚轮缩放。
- **天气光照**：拖动时间看一天的光线，查看昼夜关键帧。

进入场景后：玩家是像素精灵角色（旅人剑士），WASD / 方向键走动（镜头跟随），Shift 跑步，J 攻击、K 施法、H 受击（带特效），Q/E 旋转镜头，滚轮缩放；
NPC 白天在家附近沿路闲逛（寻路绕开房子和树）、玩家走近会挥手打招呼、天黑回家。左上角面板可回到主界面、换一个场景、切换天气和时间、开关像素风和移轴。
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
world.theme = "town"        # 或 forest / plains / snowfield / island / desert / canyon（见 PWStyles）
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

代码生成器：农舍（双坡 / 四坡顶，竖木板 / 横木板 / 石墙 / 灰泥墙）、松树、阔叶树、石井、集市摊位、铸铁路灯、手推车、路牌、灯塔（`blender/pixel_world_blender/generators/`）。
场景和资源库里的模型全部用 Blender 版（35 种：树、灌木、石头、草、水草、鱼、房屋、农舍、灯塔、风车、路灯、篱笆、长椅、木箱、木桶、草垛等），
Godot 代码版只在没有 Blender 资产时兜底。
规格生成的摆件：`shared/asset_specs/props/*.json`（雪人、篝火、布告栏、椰子树、仙人掌、帐篷、红岩石柱、渔船……），由 `generators/spec_parts.py` 按零件拼装，
可以手写，也可以用 AI 资产工坊让大模型写。它们读取同一份 `shared/style/style.json`，
像素密度 32 texel/米、只用调色板颜色；导入 Godot 后材质自动换成统一的 `pixel_world` 材质，所以积雪、潮湿、夜间窗户发光和代码生成的资产完全一样。
资产按**标签**进场景：带 plaza / roadside / yard 的摆在小镇路边，winter / desert / island / canyon 只出现在对应风格（雪人不会出现在夏天的小镇）。
回归测试：`godot --headless --path godot --script res://tests/test_world_gen.gd`。

## 像素角色（P4，HD-2D）

参考《八方旅人》的 HD-2D 做法（3D 场景里站 2D 像素角色），但分辨率更高：每帧 128 像素、角色约 96 像素高。
角色在 Blender 里用参数搭成 Q 版低模，按帧摆姿势，从 8 个方向渲染，再自动转成「三档明暗 + 1 像素描边」的像素画：

```bash
blender -b --factory-startup -P tools/blender_build_sprites.py               # 全部角色（预设 + 规格文件 + 6 个随机路人），约 6 分钟
blender -b --factory-startup -P tools/blender_build_sprites.py -- --only maiden
blender -b --factory-startup -P tools/blender_build_sprites.py -- --only maiden --anims attack   # 只重做一个动作
```

每个角色 7 个内置动作：待机、走路、跑步、攻击、受击、施法、挥手（每个 8 方向），可以用关键帧规格加自定义动作。
随机路人由种子组合发型、帽子、衣服和颜色，每个都不一样。纯 2D 项目可以导出 SpriteFrames：
`godot --headless --path godot --script res://addons/pixel_world/tools/pw_export_spriteframes.gd`。

在 Godot 里使用：

```gdscript
var hero := PWCharacter.new()
hero.sprite_id = "swordsman"      # 角色 id 见 godot/assets/sprites/catalog.json；为空则用低模身体
add_child(hero)
hero.walk(Vector3(1, 0, 0), delta) # 每帧调用，自动切换待机 / 走路、按镜头方向选 8 方向的帧
hero.attack()                      # 也有 cast() / hurt() / wave()，返回动作时长

var npc := PWNPC.new()             # NPC：白天在 home 附近闲逛，天黑回家（进门隐藏），早上再出门
npc.sprite_id = "maiden"
npc.home = world.homes[0]          # PWWorld.homes：小镇每栋房子门口 / 野外营地
npc.hour = func() -> float: return tod.hour
```

新增角色：在 `shared/asset_specs/characters/` 放一份规格 JSON（发型、帽子、衣服、道具和各部位的三色色阶，格式见 `blender/pw_specs/charspec.py`），
或者用 AI 资产工坊让大模型写（可以上传原画）。规格见 [docs/VISUAL_SPEC.md](docs/VISUAL_SPEC.md)。

## AI 资产工坊（大模型 → Blender → Godot）

在网页里配置大模型（API Key、Host、模型），用一句话或一张原画生成新的像素角色、角色动作和 3D 摆件。
大模型只写 JSON 规格，Blender 负责建模和渲染，所以不管接哪个模型，画风都和现有资产一致。

```bash
pip install -r tools/requirements.txt      # 用 Claude 时需要（anthropic SDK）
python tools/pw_asset_server.py            # 打开 http://127.0.0.1:8777：顶部「PixelWorld 工具箱 / AI 资产工坊」两个标签
python tools/workshop_selftest.py          # 自检（模拟模型，不花钱）
```

- 支持 **Anthropic Claude**（官方 SDK，默认 `claude-opus-5-5`，官方地址开启拒答自动换模型重试）和任何 **OpenAI 兼容接口**。
- Key 只保存在本机 `~/.pixelworld/workshop.json`，不进仓库。
- 也可以不调模型、直接粘贴规格 JSON 生成；规格都存在 `shared/asset_specs/`，可以手改后重新生成。
- 工具箱（Godot 网页版）和工坊在同一个网址里；工坊生成完会自动重新导出网页版，切回工具箱标签就能看到新资产。
- 模型设置里「获取列表」可以查服务方的可用模型再选。
- 3D 摆件详情可以拖动 360° 旋转；「角色动作」里有可视化动作编辑器（火柴人实时预览、滑块调姿势、关键帧）。
- 生成时可以选「放到资源库」的分类 / 子分类；资源库里也可以自己新增分类、子分类，把资源移来移去（`godot/assets/library.json`）。

详细说明（规格格式、标签、接口、接其他模型）见 [docs/ASSET_WORKSHOP.md](docs/ASSET_WORKSHOP.md)。

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
