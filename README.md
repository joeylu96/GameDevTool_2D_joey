# PixelWorld：3D 像素风场景工具链（Godot + Blender）

用来自动生成 3D 像素风的小镇和野外场景，并提供天气、昼夜系统和风格统一的 NPC。画面参考 `pixel.jpg`。
完整方案见 [docs/DESIGN.md](docs/DESIGN.md)。

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
| `godot/demo/` | 演示场景 |
| `tools/sync_style.py` | 把 `style.json` 同步成 Godot 可用的常量文件 |
| `blender/` | Blender 插件（P3 阶段开始） |

## 运行 Demo

用 Godot 4.7 打开 `godot/project.godot`，按 F5 运行。

- 操作：WASD 平移，Q/E 旋转，滚轮缩放，鼠标拖动平移。
- 左上角面板：切换天气、调整时间、开关像素渲染和移轴效果。

也可以用命令行截图，方便验证效果：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path godot --rendering-driver opengl3 -- \
  --weather=snow --snap --hour=21 --screenshot=/tmp/shot.png
```

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
