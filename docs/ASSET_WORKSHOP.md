# AI 资产工坊

用一句话或一张原画，让大模型生成新的**像素角色**、**角色动作**和 **3D 摆件**。

核心思路：**大模型不画图、不建模，只写 JSON「规格」**；Blender 按规格搭模型、贴像素贴图、渲染 / 导出。
所以不管用哪个模型，产物的画风都和手写的资产完全一致（32 texel/米、共享调色板、三档明暗 + 描边的精灵）。

```
网页（描述 / 原画 / 规格 JSON）
  → 大模型写规格（Claude 官方 SDK，或任何 OpenAI 兼容接口）
  → 校验（blender/pw_specs/；不合格把错误发回模型改一次）
  → 存到 shared/asset_specs/{characters,actions,props}/<id>.json
  → Blender 无界面生成（tools/blender_build_sprites.py / blender_build_assets.py）
  → Godot 导入（--headless --import）
  → 网页预览；Godot 主界面「AI 资产工坊 → 刷新资源库」后进资源库，按标签自动出现在对应风格的场景里
```

## 启动

需要 Python 3.10+、Blender 5.2、（可选）Godot 4.7。Windows / macOS 一样：

```bash
pip install -r tools/requirements.txt     # 用 Claude 时需要 anthropic SDK；只用 OpenAI 兼容接口可以不装
python tools/pw_asset_server.py           # 浏览器打开 http://127.0.0.1:8777
```

**一个网址就是全部**：页面顶部两个标签——
- 「PixelWorld 工具箱」：Godot 网页版（场景生成器、资源库、AI 资产工坊说明页、特效库、天气光照），由同一个服务从 `build/web` 提供；
- 「AI 资产工坊」：模型设置、生成、任务日志、资产浏览。

工坊生成完新资产会自动重新导出网页版（约 10~30 秒），工具箱标签上出现「有新资产」，点回去就自动刷新。
第一次用时如果还没有 `build/web`，在工坊里点「更新网页版」。预览图（`.workshop/previews/`，不进仓库）缺的话，服务启动时会自动补渲染。

## 放到资源库的哪里

资源库的分类结构在 `godot/assets/library.json`，工具箱和工坊共用：

- **工具箱 → 资源库**：左边是分类树（分类 → 子分类），下面「＋分类」「＋子分类」「删除」（内置分类不能删）；
  选中某个资源，右下角「移动到」可以把它放到任意分类 / 子分类。网页版通过工坊服务保存，编辑器里直接写文件。
- **工坊 → 生成新资产**：「放到资源库」选分类和子分类（下拉框里也能直接「新建分类 / 子分类」）；
  不选就按类型自动放（角色进「角色」，摆件按模型给的类型进「树木 / 杂物 / 街道设施……」）。
- 资产卡片上会显示它现在在资源库的哪个位置。

## 模型设置（网页左上）

| 项 | 说明 |
|---|---|
| 接口类型 | **Anthropic Claude**：官方 `anthropic` Python SDK。**OpenAI 兼容接口**：任何实现了 `/chat/completions` 的服务 |
| Host | Claude 留空 = 官方地址（也可以填兼容 Anthropic 接口的代理）；OpenAI 兼容接口填到 `/v1` 为止 |
| API Key | 只保存在本机 `~/.pixelworld/workshop.json`（权限 600），不进仓库；网页上只显示末尾 4 位。Claude 的 Key 留空时，SDK 会用 `ANTHROPIC_API_KEY` 环境变量或 `ant auth login` 的登录 |
| 模型 | Claude 默认 `claude-opus-5-5`；OpenAI 兼容接口填服务方的模型名。点「获取列表」会用上面填的 Host 和 Key 向服务方查可用模型（Claude 用 Models API，OpenAI 兼容接口用 `GET /models`），在下拉框里选 |
| 思考强度 | Claude 的 `output_config.effort`：低 / 中 / 高（默认中）；老模型不支持时选「不发送」 |
| 拒答自动换模型 | 只对 Claude 官方地址生效：模型拒答（`stop_reason: refusal`）时服务端自动换一个模型重试（server-side fallback，`fallbacks: "default"`） |
| Blender / Godot 路径 | 一般自动找到（macOS 的 /Applications、Windows 的 Program Files、PATH）；找不到时手填 |

「测试连接」会发一个很短的请求，显示模型回复和 token 用量。

## 三种资产的规格

完整说明和可选值都在 `blender/pw_specs/`（大模型的系统提示 `prompts.py` 也是从这里生成的）。

### 像素角色（`charspec.py`）

```json
{
  "id": "fisherwoman", "name": "渔家大婶", "desc": "港口卖鱼的大婶……",
  "hair": "bun", "hat": null, "skirt": 0.5, "sleeves": "short",
  "scarf": true, "vest": false, "cape": false, "beard": false, "sleeve_band": false,
  "weapon": "bag", "height": 0.96, "build": 1.12,
  "colors": {"hair": ["#6b4a36", "#4e3426", "#33221a"], "top": "#efe9dc", "skirt": ["#6f92c6", "#4a6fa5", "#34507a"]},
  "extra_anims": []
}
```

- 发型：short / spiky / long / ponytail / bun / bald；帽子：wide / helmet / hood / cap
- 武器道具：sword / greatsword / spear / staff / cane / bag / axe
- 颜色：每个部位三色色阶 [亮, 中, 暗]，或只给一个基色（自动做「亮部偏暖、暗部偏冷」的色阶）
- 渲染出 7 个内置动作：待机、走路、跑步、攻击、受击、施法、挥手（每个 8 方向）

### 角色动作（`poses.py`）

所有角色共用一套骨架参数，动作就是几个关键帧（时间 0..1 + 要改的姿势参数），自动平滑插值：

```json
{
  "id": "victory", "name": "胜利欢呼", "frames": 6, "fps": 8, "loop": false, "for": ["swordsman", "mercenary"],
  "keys": [
    {"t": 0.0, "bob": -0.06, "arm_r": [0.4, 1.2, 0.3], "weapon": "hand"},
    {"t": 0.35, "bob": 0.12, "arm_r": [2.9, 0.15, 0.25], "head": [-0.3, 0.0]},
    {"t": 1.0, "bob": 0.0, "arm_r": [2.9, 0.15, 0.25]}
  ]
}
```

姿势参数：bob、breath、lean（前倾）、twist（扭腰）、head、arm_l / arm_r（前摆、肘弯、外张）、leg_l / leg_r（大腿、膝弯）、
cape（披风飘动）、weapon（"hand" = 武器拿在右手）、weapon_angle、hand_glow（施法光）。每个参数有合法范围，超出会被夹回去。

### 3D 摆件（`propspec.py`）

由零件拼成：`box` / `frustum`（竖直棱台、锥、圆柱）/ `tube`（任意方向的管子）/ `blob`（团块）/ `gable_roof`（双坡屋顶）/ `repeat`（环形复制）。

```json
{
  "id": "rowboat", "name": "倒扣的渔船", "category": "props", "tags": ["shore", "island", "town"], "variants": 4,
  "vars": {"len": {"rand": [2.6, 3.2]}, "w": {"rand": [1.0, 1.2]}, "hull": ["wall_teal", "wall_red", "wall_wood"]},
  "parts": [
    {"shape": "tube", "mat": "$hull", "from": ["-$len/2", 0, 0.02], "to": ["$len/2-0.45", 0, 0.02], "r": ["$w/2*0.92", "$w/2"], "sides": 10},
    {"shape": "box", "mat": "trunk", "min": ["-$len/2", -0.05, "$w/2-0.01"], "max": ["$len/2-0.2", 0.05, "$w/2+0.06"]}
  ]
}
```

- 单位是米，原点在地面中心，Z 向上，正面朝 -Y
- 材质只能从像素贴图库里选（`MATERIALS`，约 40 种：木板墙、瓦片、石头、树叶、帆布、金属、玻璃、雪、沙……），
  Godot 里自动响应积雪、潮湿、夜间发光（玻璃 / 灯泡）、随风摆动（树叶）
- 随机：数值写 `{"rand": [a, b]}`；共享变量 `vars` + `"$名字"` / `"$len/2-0.4"` 表达式（互相连接的零件必须用同一个变量）；
  材质变量 `"vars": {"hull": [...]}` + `"mat": "$hull"` 让几个零件同色
- 标签决定它会出现在哪：

| 标签 | 去处 |
|---|---|
| plaza / roadside / yard | 小镇路边、广场、房前屋后（自动摆进小镇） |
| camp | 营地 |
| winter / desert / island / canyon | 雪原 / 沙漠绿洲 / 海岛 / 峡谷风格（气候标签：只在对应风格出现） |
| forest / plains / town / shore | 对应风格、水边 |

## 接口（给其他工具调用）

服务只监听 127.0.0.1，允许跨域（Godot 网页版 / 编辑器里的 HTTPRequest 也能访问）。

| 方法 | 地址 | 说明 |
|---|---|---|
| GET | `/api/ping` | 服务在不在 |
| GET / POST | `/api/config` | 读 / 存模型设置（读到的 Key 是遮盖过的） |
| POST | `/api/test` | 测试连接 |
| POST | `/api/models` | 模型列表（body 里可以带当前填的 provider / host / api_key，不用先保存） |
| GET / POST | `/api/library` | 资源库分类结构（分类、子分类、资源位置） |
| POST | `/api/generate` | `{"kind": "character" \| "action" \| "prop", "prompt": "...", "image": {"media_type", "data"(base64)}, "for": [...], "place": {"cat", "sub"}}`；或者 `{"kind", "spec": {...}}` 不调模型直接生成。返回 `{"job": id}` |
| GET | `/api/jobs/<id>` | 任务状态、日志、规格、警告、结果 |
| GET | `/api/assets` | 现有角色、摆件、自定义动作 |
| GET | `/api/spec/<kind>/<id>` | 某个资产的规格 |

## 测试

```bash
python tools/workshop_selftest.py          # 模拟模型：Claude SDK 路径、OpenAI 兼容路径、图片传递、修正循环（几秒，不花钱）
python tools/workshop_selftest.py --full   # 再加一次完整生成（Blender + Godot 导入），产物自动清理
```

本仓库里由当前会话的 Claude（claude-opus-5-5）充当模型、经工坊生成的测试资产：
角色「佣兵队长」（按 ~/Downloads/原画.jpg 取色和特征，原创名字）、「渔家大婶」，动作「扛剑」「胜利欢呼」，
摆件「雪人」「篝火」「布告栏」「椰子树」「仙人掌」「帐篷」「红岩石柱」「倒扣的渔船」。
规格都在 `shared/asset_specs/`，规格里的 `source` 字段记录了来源。

## 接其他模型

- 有 OpenAI 兼容接口的模型（大多数国内外服务、本地 vLLM / Ollama 等）：接口类型选「OpenAI 兼容接口」，填 Host、Key、模型名即可。
- 原画生成角色需要模型支持图片输入；不支持时只用文字描述。
- 模型写不出合格的规格时：任务日志里有校验错误，可以把模型的输出复制到「直接用规格 JSON」里手改后生成。

## 注意

- Godot 界面用的中文字体是裁剪版（只含用到的字）。新生成的资源名里如果有新字，Godot 里会显示成方块，
  重新裁剪一次字体即可：`python tools/subset_font.py <完整的 NotoSansSC-Regular.otf>`（会扫描 shared/ 和资产目录里的名字）。
- 工坊服务改了代码要重启（Blender 每次都是新进程，会读到最新代码；服务本身启动时加载一次校验代码）。
- 生成角色约 40 秒（7 个动作 × 8 方向），给角色加一个动作约 6 秒 / 个角色，摆件约 10 秒（4 个变体）。
