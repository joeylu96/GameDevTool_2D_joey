#!/usr/bin/env python3
"""PixelWorld 资产工坊：本地网页 + 生成服务。在网页里配置大模型（API Key、Host、模型），
用一句话 / 一张原画生成像素角色、角色动作和 3D 摆件——大模型只写 JSON 规格，Blender 负责建模和渲染，画风和场景一致。

启动（Windows / macOS 一样，需要 Python 3.10+）：
    pip install -r tools/requirements.txt      # 用 Claude 时需要（anthropic SDK）；只用 OpenAI 兼容接口可以不装
    python tools/pw_asset_server.py            # 然后浏览器打开 http://127.0.0.1:8777
一个网址就是全部：顶部两个标签——「PixelWorld 工具箱」（Godot 网页版：场景生成器、资源库、特效、天气）和「AI 资产工坊」。
工坊生成新资产后会自动重新导出网页版（build/web），工具箱标签刷新一下就能看到。
    python tools/pw_asset_server.py --port 8778

流程：网页提交 → 调用大模型得到规格 JSON → 校验（不合格把错误发回模型改一次）→ 存到 shared/asset_specs/
      → 调 Blender 生成（tools/blender_build_sprites.py / blender_build_assets.py）→ 调 Godot 导入 → 网页显示预览。
也可以不调模型、直接粘贴规格 JSON 生成（手动 / 测试用）。

模型接口：
  - anthropic：Claude（官方 anthropic Python SDK）。Host 留空 = 官方地址；也可以填兼容 Anthropic 接口的代理地址。
  - openai：任何 OpenAI 兼容的 /chat/completions 接口（填到 /v1 为止的 Host，比如 https://api.example.com/v1）。
API Key 只保存在本机 ~/.pixelworld/workshop.json（不进仓库），网页上只显示末尾 4 位。服务只监听 127.0.0.1。
"""
import argparse
import base64
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import threading
import time
import traceback
import urllib.error
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "blender"))
from pw_specs import charspec, poses, prompts, propspec  # noqa: E402

CONFIG_PATH = Path.home() / ".pixelworld" / "workshop.json"
WORK = ROOT / ".workshop"
SPECS = ROOT / "shared" / "asset_specs"
SPRITES = ROOT / "godot" / "assets" / "sprites"
BLENDER_ASSETS = ROOT / "godot" / "assets" / "blender"
WEB = Path(__file__).resolve().parent / "workshop"
BUILD_WEB = ROOT / "build" / "web"   # Godot 网页版（导出预设 "Web"）
LIBRARY = ROOT / "godot" / "assets" / "library.json"  # 资源库的分类 / 子分类和资源位置（工具箱和工坊共用）

DEFAULTS = {
    "provider": "anthropic",     # anthropic / openai
    "host": "",                  # 留空 = 官方地址（anthropic）；openai 兼容接口必填，到 /v1 为止
    "api_key": "",
    "model": "claude-opus-5-5",
    "effort": "medium",          # Claude 的 output_config.effort：low / medium / high（留空 = 不发送）
    "fallback": True,            # Claude 官方地址：拒答时服务端自动换模型重试（server-side fallback）
    "max_tokens": 16000,
    "blender": "",               # 留空 = 自动查找
    "godot": "",
    "sync_web": True,            # 生成完自动重新导出网页版，工具箱标签里就能看到新资产
    "font_source": "",           # 完整的 NotoSansSC-Regular.otf（新资源名里有字体缺的字时自动重新裁剪）；留空 = ~/.pixelworld/ 下找
}
# 支持服务端拒答兜底（fallbacks="default"）的模型
FALLBACK_MODELS = {"claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"}

_build_lock = threading.Lock()  # Blender / Godot 一次只跑一个
JOBS = {}


# ---------------------------------------------------------------- 配置

def load_config():
    cfg = dict(DEFAULTS)
    if CONFIG_PATH.exists():
        try:
            cfg.update(json.loads(CONFIG_PATH.read_text(encoding="utf-8")))
        except ValueError:
            pass
    return cfg


def save_config(new):
    cfg = load_config()
    for k in DEFAULTS:
        if k in new:
            if k == "api_key" and (new[k] is None or str(new[k]).startswith("••")):
                continue  # 网页上显示的是遮盖过的 key，没改就不覆盖
            cfg[k] = new[k]
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")
    try:
        os.chmod(CONFIG_PATH, 0o600)
    except OSError:
        pass
    return cfg


def public_config(cfg):
    out = dict(cfg)
    k = cfg.get("api_key") or ""
    out["api_key"] = ("••••" + k[-4:]) if k else ""
    out["blender_found"] = find_blender(cfg) or ""
    out["godot_found"] = find_godot(cfg) or ""
    out["config_path"] = str(CONFIG_PATH)
    return out


def find_blender(cfg):
    cands = [cfg.get("blender") or ""]
    if platform.system() == "Darwin":
        cands.append("/Applications/Blender.app/Contents/MacOS/Blender")
    elif platform.system() == "Windows":
        for base in (os.environ.get("ProgramFiles", r"C:\Program Files"),):
            cands += [str(p) for p in sorted(Path(base, "Blender Foundation").glob("Blender 5.2*/blender.exe"))]
    cands.append(shutil.which("blender") or "")
    return next((c for c in cands if c and Path(c).exists()), None)


def find_godot(cfg):
    cands = [cfg.get("godot") or ""]
    if platform.system() == "Darwin":
        cands.append("/Applications/Godot.app/Contents/MacOS/Godot")
    cands += [shutil.which(n) or "" for n in ("godot", "godot4", "Godot")]
    return next((c for c in cands if c and Path(c).exists()), None)


# ---------------------------------------------------------------- 大模型

class LLMError(Exception):
    pass


def _official(host):
    return not host or "api.anthropic.com" in host


def call_llm(cfg, system, text, image=None, max_tokens=None):
    """调用配置好的模型，返回 (回复文本, 用量说明)"""
    if not cfg.get("api_key") and cfg.get("provider") == "openai":
        raise LLMError("还没有填 API Key")
    if cfg.get("provider") == "openai":
        return _call_openai(cfg, system, text, image, max_tokens)
    return _call_anthropic(cfg, system, text, image, max_tokens)


def _call_anthropic(cfg, system, text, image, max_tokens):
    try:
        import anthropic
    except ImportError:
        raise LLMError("没有安装 anthropic SDK：运行 pip install -r tools/requirements.txt")
    # api_key 留空时 SDK 会按 ANTHROPIC_API_KEY 环境变量 / ant auth login 的配置去找
    client = anthropic.Anthropic(api_key=cfg.get("api_key") or None, base_url=cfg.get("host") or None)
    content = []
    if image:
        content.append({"type": "image", "source": {"type": "base64", "media_type": image["media_type"], "data": image["data"]}})
    content.append({"type": "text", "text": text})
    kwargs = {
        "model": cfg.get("model") or DEFAULTS["model"],
        "max_tokens": int(max_tokens or cfg.get("max_tokens") or 16000),
        "system": system,
        "messages": [{"role": "user", "content": content}],
    }
    if cfg.get("effort"):
        kwargs["output_config"] = {"effort": cfg["effort"]}
    try:
        resp = None
        if cfg.get("fallback", True) and _official(cfg.get("host")) and kwargs["model"] in FALLBACK_MODELS:
            try:
                resp = client.beta.messages.create(betas=["server-side-fallback-2026-07-01"], fallbacks="default", **kwargs)
            except TypeError:
                resp = None  # SDK 版本太旧，不认识 fallbacks 参数：退回普通请求
        if resp is None:
            resp = client.messages.create(**kwargs)
    except anthropic.AuthenticationError:
        raise LLMError("API Key 无效（401）")
    except anthropic.PermissionDeniedError as e:
        raise LLMError("没有权限（403）：%s" % e.message)
    except anthropic.NotFoundError:
        raise LLMError("找不到模型或接口（404）：检查 Host 和模型名")
    except anthropic.RateLimitError:
        raise LLMError("请求太频繁（429），稍等再试")
    except anthropic.BadRequestError as e:
        raise LLMError("请求被拒绝（400）：%s" % e.message)
    except anthropic.APIStatusError as e:
        raise LLMError("服务端错误（%s）：%s" % (e.status_code, e.message))
    except anthropic.APIConnectionError:
        raise LLMError("连不上 %s，检查网络和 Host" % (cfg.get("host") or "api.anthropic.com"))
    if resp.stop_reason == "refusal":
        raise LLMError("模型拒绝了这个请求（refusal）。换个描述试试，比如不要要求复刻现有作品里的角色。")
    if resp.stop_reason == "max_tokens":
        raise LLMError("回复被截断（max_tokens），在设置里调大「最大输出」")
    out = "".join(b.text for b in resp.content if getattr(b, "type", "") == "text")
    u = getattr(resp, "usage", None)
    usage = "%s，输入 %s / 输出 %s tokens" % (getattr(resp, "model", kwargs["model"]), getattr(u, "input_tokens", "?"),
                                          getattr(u, "output_tokens", "?"))
    return out, usage


def _call_openai(cfg, system, text, image, max_tokens):
    host = (cfg.get("host") or "").rstrip("/")
    if not host:
        raise LLMError("OpenAI 兼容接口需要填 Host（到 /v1 为止）")
    user = [{"type": "text", "text": text}]
    if image:
        user.append({"type": "image_url", "image_url": {"url": "data:%s;base64,%s" % (image["media_type"], image["data"])}})
    body = {"model": cfg.get("model"), "max_tokens": int(max_tokens or cfg.get("max_tokens") or 16000),
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}
    req = urllib.request.Request(host + "/chat/completions", data=json.dumps(body).encode("utf-8"), method="POST",
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + cfg["api_key"]})
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            data = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:300]
        raise LLMError("接口返回 %d：%s" % (e.code, detail))
    except urllib.error.URLError as e:
        raise LLMError("连不上 %s：%s" % (host, e.reason))
    try:
        msg = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        raise LLMError("接口返回格式不对：%s" % json.dumps(data, ensure_ascii=False)[:300])
    if isinstance(msg, list):
        msg = "".join(p.get("text", "") for p in msg if isinstance(p, dict))
    u = data.get("usage") or {}
    return msg or "", "%s，输入 %s / 输出 %s tokens" % (data.get("model", cfg.get("model")), u.get("prompt_tokens", "?"),
                                                     u.get("completion_tokens", "?"))


def list_models(cfg):
    """当前接口能用的模型：[{"id", "name"}]。Claude 走官方 SDK 的 Models API，OpenAI 兼容接口走 GET {host}/models"""
    if cfg.get("provider") == "openai":
        host = (cfg.get("host") or "").rstrip("/")
        if not host:
            raise LLMError("OpenAI 兼容接口需要先填 Host（到 /v1 为止）")
        req = urllib.request.Request(host + "/models", headers={"Authorization": "Bearer " + (cfg.get("api_key") or "")})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                data = json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            raise LLMError("接口返回 %d：%s" % (e.code, e.read().decode("utf-8", "replace")[:200]))
        except urllib.error.URLError as e:
            raise LLMError("连不上 %s：%s" % (host, e.reason))
        items = data.get("data", data if isinstance(data, list) else [])
        out = [{"id": m.get("id"), "name": m.get("id")} for m in items if isinstance(m, dict) and m.get("id")]
        return sorted(out, key=lambda m: m["id"])
    try:
        import anthropic
    except ImportError:
        raise LLMError("没有安装 anthropic SDK：运行 pip install -r tools/requirements.txt")
    client = anthropic.Anthropic(api_key=cfg.get("api_key") or None, base_url=cfg.get("host") or None)
    try:
        return [{"id": m.id, "name": getattr(m, "display_name", None) or m.id} for m in client.models.list()]
    except anthropic.AuthenticationError:
        raise LLMError("API Key 无效（401）")
    except anthropic.NotFoundError:
        raise LLMError("这个 Host 不支持模型列表（404），直接手填模型名")
    except anthropic.APIStatusError as e:
        raise LLMError("服务端错误（%s）：%s" % (e.status_code, e.message))
    except anthropic.APIConnectionError:
        raise LLMError("连不上 %s，检查网络和 Host" % (cfg.get("host") or "api.anthropic.com"))


def extract_json(text):
    """从模型回复里取出 JSON 对象：优先 ```json 代码块，否则取第一个 { 到最后一个 }"""
    m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.S)
    raw = m.group(1) if m else text[text.find("{"): text.rfind("}") + 1]
    if not raw.strip():
        raise ValueError("回复里没有 JSON")
    return json.loads(raw)


# ---------------------------------------------------------------- 任务

class Job:
    def __init__(self, kind, req):
        self.id = uuid.uuid4().hex[:10]
        self.kind = kind
        self.req = req
        self.status = "排队中"
        self.state = "running"
        self.logs = []
        self.spec = None
        self.warnings = []
        self.result = {}
        self.started = time.time()

    def log(self, msg):
        line = "[%5.1fs] %s" % (time.time() - self.started, msg)
        self.logs.append(line)
        print("  [%s] %s" % (self.id, msg), flush=True)

    def to_dict(self):
        return {"id": self.id, "kind": self.kind, "status": self.status, "state": self.state, "logs": self.logs,
                "spec": self.spec, "warnings": self.warnings, "result": self.result}


VALIDATORS = {"character": charspec.validate, "action": poses.validate_action, "prop": propspec.validate}
SPEC_DIRS = {"character": SPECS / "characters", "action": SPECS / "actions", "prop": SPECS / "props"}


def _user_prompt(kind, req, colors):
    text = req.get("prompt", "").strip() or "请设计一个有特点的原创资产。"
    parts = ["用户的需求：" + text]
    if kind == "character" and req.get("image"):
        parts.append("用户附了一张原画（见图片）。按原画的发色、服装、配色和道具来设计，名字原创。")
        if colors:
            parts.append("从原画里提取的主色（占比，含背景）：" + ", ".join("%s(%.0f%%)" % (c, p * 100) for c, p in colors))
    if kind == "action":
        chars = [c["id"] + "（" + c.get("name", "") + "）" for c in _sprite_catalog().get("characters", [])
                 if not c["id"].startswith("villager_")]
        parts.append("现有角色：" + "、".join(chars))
        tgt = req.get("for") or []
        if tgt:
            parts.append("这个动作要给这些角色用：" + json.dumps(tgt, ensure_ascii=False) + "（写进 for 字段）")
    if kind == "prop":
        names = [a.get("name", "") for a in _blender_catalog().get("assets", [])]
        parts.append("资源库里已经有：" + "、".join(names) + "（不要重复）")
    return "\n".join(parts)


def run_job(job):
    cfg = load_config()
    kind = job.kind
    req = job.req
    try:
        spec_raw = req.get("spec")
        colors = []
        image = req.get("image")
        if spec_raw is None:
            if kind == "character" and image:
                job.status = "提取原画颜色"
                colors = _extract_colors(job, cfg, image)
            system = prompts.SYSTEM[kind]
            feedback = ""
            for attempt in range(2):
                job.status = "等待模型回复" + ("（修正）" if attempt else "")
                job.log("调用模型 %s（%s）" % (cfg.get("model"), cfg.get("provider")))
                text, usage = call_llm(cfg, system, _user_prompt(kind, req, colors) + feedback,
                                       image if kind == "character" else None)
                job.log("模型回复 %d 字，%s" % (len(text), usage))
                try:
                    spec_raw = extract_json(text)
                    spec, warn = VALIDATORS[kind](spec_raw)
                    break
                except ValueError as e:
                    job.log("规格不合格：%s" % e)
                    if attempt == 1:
                        raise
                    feedback = "\n\n你上次输出的规格有问题：%s\n请改正后重新输出完整的 JSON。" % e
        else:
            spec, warn = VALIDATORS[kind](spec_raw)
        if kind == "action" and req.get("for") and not spec.get("for"):
            spec["for"] = req["for"]
        if kind == "character" and isinstance(spec_raw, dict) and spec_raw.get("source"):
            spec["source"] = spec_raw["source"]
        job.spec = spec
        job.warnings = warn
        for w in warn:
            job.log("提示：" + w)
        path = SPEC_DIRS[kind] / ("%s.json" % spec["id"])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(spec, ensure_ascii=False, indent=2), encoding="utf-8")
        job.log("规格已保存：%s" % path.relative_to(ROOT).as_posix())
        with _build_lock:
            _build(job, cfg, kind, spec)
            if kind in ("prop", "character"):
                place_asset(job, ("bl_spec_" if kind == "prop" else "sprite_") + spec["id"], req.get("place"))
            ensure_font(job, cfg, spec)
            _import_godot(job, cfg)
            if cfg.get("sync_web", True):
                job.result["web_updated"] = _export_web(job, cfg)
        job.status = "完成"
        job.state = "done"
        job.log("完成，用时 %.0f 秒" % (time.time() - job.started))
    except (LLMError, ValueError, RuntimeError) as e:
        job.status = "失败：%s" % e
        job.state = "error"
        job.log("失败：%s" % e)
    except Exception as e:  # noqa: BLE001 —— 任务线程里兜底，错误显示在网页上
        job.status = "出错：%s" % e
        job.state = "error"
        job.log(traceback.format_exc())


def _run(job, cmd, timeout=1800):
    job.log("$ " + " ".join(Path(c).name if i == 0 else c for i, c in enumerate(cmd)))
    p = subprocess.Popen(cmd, cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         encoding="utf-8", errors="replace")
    t0 = time.time()
    for line in p.stdout:
        line = line.rstrip()
        if re.search(r"角色|已生成|已导出|规格|动作|预览|字符|Error|Traceback|错误|跳过|^\s+bl_", line) and "Saved:" not in line:
            job.log("  " + line.strip())
        if time.time() - t0 > timeout:
            p.kill()
            raise RuntimeError("超时")
    if p.wait() != 0:
        raise RuntimeError("命令失败（退出码 %d）" % p.returncode)


def _blender(cfg):
    b = find_blender(cfg)
    if not b:
        raise RuntimeError("找不到 Blender 5.2：在设置里填 Blender 路径")
    return b


def _build(job, cfg, kind, spec):
    b = _blender(cfg)
    if kind == "character":
        job.status = "Blender 渲染角色（约 40 秒）"
        _run(job, [b, "-b", "--factory-startup", "-P", "tools/blender_build_sprites.py", "--", "--only", spec["id"]])
        job.result = {"character": spec["id"], "preview": "/files/previews/char_%s.png" % spec["id"]}
    elif kind == "action":
        targets = [t for t in spec.get("for", []) if t != "all"]
        if "all" in spec.get("for", []) or not targets:
            targets = [c["id"] for c in _sprite_catalog().get("characters", []) if not c["id"].startswith("villager_")]
        job.status = "Blender 给 %d 个角色渲染动作" % len(targets)
        _run(job, [b, "-b", "--factory-startup", "-P", "tools/blender_build_sprites.py", "--", "--only", ",".join(targets),
                   "--anims", spec["id"]])
        job.result = {"action": spec["id"], "characters": targets}
    else:
        job.status = "Blender 搭模型、导出（%d 个变体）" % spec.get("variants", 4)
        _run(job, [b, "-b", "--factory-startup", "-P", "tools/blender_build_assets.py", "--", "--only", "spec_" + spec["id"]])
        job.result = {"prop": "bl_spec_" + spec["id"], "preview": "/files/previews/prop_spec_%s.png" % spec["id"]}


def _export_web(job, cfg):
    """重新导出 Godot 网页版（build/web），新资产才会出现在「PixelWorld 工具箱」标签里。返回是否导出成功"""
    g = find_godot(cfg)
    if not g:
        job.log("没找到 Godot，跳过网页版导出")
        return False
    BUILD_WEB.mkdir(parents=True, exist_ok=True)
    job.status = "更新网页版（约 30 秒）"
    try:
        _run(job, [g, "--headless", "--path", "godot", "--export-release", "Web", str(BUILD_WEB / "index.html")], timeout=900)
    except RuntimeError as e:
        job.log("网页版导出失败：%s（资产本身已经生成好了）" % e)
        return False
    job.log("网页版已更新：刷新「PixelWorld 工具箱」标签就能看到新资产")
    return True


# ---------------------------------------------------------------- 资源库分类

DEFAULT_CATEGORIES = [("trees", "树木"), ("plants", "灌木与草"), ("rocks", "岩石"), ("buildings", "建筑"),
                      ("landmarks", "地标"), ("street", "街道设施"), ("props", "杂物"), ("water", "水生"), ("characters", "角色")]
_lib_lock = threading.Lock()


def read_library():
    try:
        d = json.loads(LIBRARY.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        d = {}
    return normalize_library(d)


def normalize_library(d):
    """和 Godot 端 PWAssetLibrary._normalize 一样：分类有 id / name / children，内置分类一个不少，assign 是 {资源 id: [分类, 子分类]}"""
    cats = []
    seen = set()
    for c in d.get("categories", []) if isinstance(d, dict) else []:
        if not isinstance(c, dict) or not c.get("id"):
            continue
        cid = re.sub(r"[^A-Za-z0-9_]", "", str(c["id"]))[:40]
        if not cid or cid in seen:
            continue
        kids = []
        for k in c.get("children", []) or []:
            if isinstance(k, dict) and k.get("id"):
                kids.append({"id": re.sub(r"[^A-Za-z0-9_]", "", str(k["id"]))[:40], "name": str(k.get("name") or k["id"])[:20]})
        cats.append({"id": cid, "name": str(c.get("name") or cid)[:20], "builtin": bool(c.get("builtin")), "children": kids})
        seen.add(cid)
    for i, (cid, name) in enumerate(DEFAULT_CATEGORIES):
        if cid not in seen:
            cats.insert(min(i, len(cats)), {"id": cid, "name": name, "builtin": True, "children": []})
    assign = {}
    for k, v in (d.get("assign") or {}).items() if isinstance(d, dict) else []:
        if isinstance(v, list) and v:
            assign[str(k)] = [str(v[0]), str(v[1]) if len(v) > 1 else ""]
    return {"version": 1, "categories": cats, "assign": assign}


def write_library(d):
    lib = normalize_library(d)
    with _lib_lock:
        LIBRARY.write_text(json.dumps(lib, ensure_ascii=False, indent=2), encoding="utf-8")
    return lib


FONT_CHARS = ROOT / "godot" / "addons" / "pixel_world" / "ui" / "fonts" / "NotoSansSC-PW.chars.txt"


def ensure_font(job, cfg, spec):
    """Godot 界面用的是裁剪过的中文字体（常用 7500 字）。新资源的名字 / 描述里有字体缺的字时：
    有完整字体和 fonttools 就自动重新裁剪，没有就在日志里提示（不影响生成，只是 Godot 里那几个字会显示成方块）"""
    text = "".join(str(spec.get(k, "")) for k in ("name", "desc", "vary"))
    have = set(FONT_CHARS.read_text(encoding="utf-8")) if FONT_CHARS.exists() else set()
    missing = sorted({ch for ch in text if ord(ch) > 0x7F and ch not in have})
    if not missing or not have:
        return
    src = Path(cfg.get("font_source") or (Path.home() / ".pixelworld" / "NotoSansSC-Regular.otf"))
    try:
        import fontTools  # noqa: F401
        ok = src.exists()
    except ImportError:
        ok = False
    if not ok:
        job.log("提示：字体里没有「%s」，Godot 里会显示成方块。把完整的 NotoSansSC-Regular.otf 放到 %s 并 pip install fonttools，"
                "以后会自动补字" % ("".join(missing), src))
        return
    job.status = "补字体（%s）" % "".join(missing)
    _run(job, [sys.executable, "tools/subset_font.py", str(src)], timeout=300)
    job.log("字体已补上：%s" % "".join(missing))


def place_asset(job, asset_id, place):
    """把生成的资源放到资源库里指定的分类 / 子分类（工坊里选的）"""
    if not place or not place.get("cat"):
        return
    lib = read_library()
    cat = next((c for c in lib["categories"] if c["id"] == place["cat"]), None)
    if cat is None:
        job.log("资源库里没有分类 %s，放到默认位置" % place["cat"])
        return
    sub = place.get("sub") or ""
    if sub and not any(k["id"] == sub for k in cat["children"]):
        sub = ""
    lib["assign"][asset_id] = [cat["id"], sub]
    write_library(lib)
    names = [cat["name"]] + [k["name"] for k in cat["children"] if k["id"] == sub]
    job.log("放到资源库：%s" % " / ".join(names))


def asset_location(asset_id, default_cat, lib):
    v = lib["assign"].get(asset_id)
    cat_id, sub_id = (v[0], v[1]) if v else (default_cat, "")
    cat = next((c for c in lib["categories"] if c["id"] == cat_id), None)
    if cat is None:
        cat = next((c for c in lib["categories"] if c["id"] == default_cat), lib["categories"][0])
        sub_id = ""
    sub = next((k for k in cat["children"] if k["id"] == sub_id), None)
    return {"cat": cat["id"], "sub": sub["id"] if sub else "", "label": cat["name"] + (" / " + sub["name"] if sub else "")}


def missing_previews():
    """目录里有、但还没有预览图的 Blender 资产"""
    out = []
    for a in _blender_catalog().get("assets", []):
        if not (WORK / "previews" / ("prop_%s_spin.png" % a["kind"])).exists():
            out.append(a["kind"])
    return out


def run_preview_job(job, kinds):
    """补预览图（预览图不进仓库，换了机器 / 新克隆的仓库第一次启动时要补一次）"""
    cfg = load_config()
    try:
        b = _blender(cfg)
        job.status = "补 %d 张预览图（约 %d 秒）" % (len(kinds), max(5, len(kinds) * 3))
        with _build_lock:
            _run(job, [b, "-b", "--factory-startup", "-P", "tools/blender_render_previews.py", "--", "--only", ",".join(kinds)])
        job.status = "完成"
        job.state = "done"
    except Exception as e:  # noqa: BLE001
        job.status = "出错：%s" % e
        job.state = "error"


def run_export_job(job):
    cfg = load_config()
    try:
        with _build_lock:
            ok = _export_web(job, cfg)
        job.status = "完成" if ok else "失败：网页版没有导出"
        job.state = "done" if ok else "error"
        job.result = {"web_updated": ok}
    except Exception as e:  # noqa: BLE001
        job.status = "出错：%s" % e
        job.state = "error"
        job.log(traceback.format_exc())


def _import_godot(job, cfg):
    g = find_godot(cfg)
    if not g:
        job.log("没找到 Godot，跳过导入（打开 Godot 编辑器时会自动导入新资源）")
        return
    job.status = "Godot 导入新资源"
    _run(job, [g, "--headless", "--path", "godot", "--import"], timeout=600)


def _extract_colors(job, cfg, image):
    try:
        b = _blender(cfg)
    except RuntimeError:
        return []
    ext = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}.get(image["media_type"], ".png")
    tmp = WORK / "uploads" / ("%s%s" % (job.id, ext))
    tmp.parent.mkdir(parents=True, exist_ok=True)
    tmp.write_bytes(base64.b64decode(image["data"]))
    out = subprocess.run([b, "-b", "--factory-startup", "-P", "tools/extract_colors.py", "--", str(tmp), "12"],
                         cwd=str(ROOT), capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
    m = re.search(r"PW_COLORS (\{.*\})", out.stdout)
    colors = json.loads(m.group(1))["colors"] if m else []
    job.log("原画主色：" + ", ".join(c for c, _ in colors[:8]))
    return colors


# ---------------------------------------------------------------- 资产列表

def _sprite_catalog():
    p = SPRITES / "catalog.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def _blender_catalog():
    p = BLENDER_ASSETS / "catalog.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def list_assets():
    sc = _sprite_catalog()
    lib = read_library()
    chars = []
    for c in sc.get("characters", []):
        spec_file = SPECS / "characters" / ("%s.json" % c["id"])
        chars.append({"id": c["id"], "name": c.get("name"), "desc": c.get("desc"), "anims": c.get("anims", {}),
                      "where": asset_location("sprite_" + c["id"], "characters", lib),
                      "generated": spec_file.exists(), "preview": "/files/previews/char_%s.png" % c["id"]
                      if (WORK / "previews" / ("char_%s.png" % c["id"])).exists() else ""})
    props = []
    for a in _blender_catalog().get("assets", []):
        props.append({"id": a["id"], "name": a.get("name"), "desc": a.get("desc"), "category": a.get("category"),
                      "where": asset_location(a["id"], a.get("category") or "props", lib),
                      "tags": a.get("tags", []), "source": a.get("source", "generator"), "variants": len(a.get("files", [])),
                      "preview": "/files/previews/prop_%s.png" % a["kind"]
                      if (WORK / "previews" / ("prop_%s.png" % a["kind"])).exists() else "",
                      "spin": "/files/previews/prop_%s_spin.png" % a["kind"]
                      if (WORK / "previews" / ("prop_%s_spin.png" % a["kind"])).exists() else ""})
    actions = []
    for p in sorted((SPECS / "actions").glob("*.json")):
        try:
            a = json.loads(p.read_text(encoding="utf-8"))
            actions.append({"id": a.get("id"), "name": a.get("name"), "frames": a.get("frames"), "for": a.get("for", [])})
        except ValueError:
            pass
    return {"characters": chars, "props": props, "actions": actions, "frame": sc.get("frame", 128), "frame_w": sc.get("frame_w", sc.get("frame", 128)),
            "dirs": sc.get("dirs", 8)}


def read_spec(kind, sid):
    p = SPEC_DIRS[kind] / ("%s.json" % re.sub(r"[^a-z0-9_]", "", sid))
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    if kind == "character":
        for s in charspec.PRESETS:
            if s["id"] == sid:
                return s
    return None


# ---------------------------------------------------------------- HTTP

class Handler(BaseHTTPRequestHandler):
    server_version = "PixelWorldWorkshop/1.0"

    def log_message(self, fmt, *args):
        pass

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")  # Godot 网页版 / 编辑器里的 HTTPRequest 也能访问
        self.end_headers()
        self.wfile.write(data)

    def _file(self, base, rel):
        p = (base / unquote(rel)).resolve()
        if not str(p).startswith(str(base.resolve())) or not p.is_file():
            return self._send(404, {"error": "没有这个文件"})
        ctype = {".png": "image/png", ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
                 ".wasm": "application/wasm", ".pck": "application/octet-stream", ".ico": "image/x-icon",
                 ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8"}.get(p.suffix, "application/octet-stream")
        self._send(200, p.read_bytes(), ctype)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > 40 * 1024 * 1024:
            raise ValueError("请求太大")
        return json.loads(self.rfile.read(n).decode("utf-8") or "{}")

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            return self._file(WEB, "app.html")  # 合在一起的入口：工具箱 + 资产工坊
        if path in ("/workshop", "/workshop/"):
            return self._file(WEB, "index.html")
        if path == "/game" or path == "/game/":
            if not (BUILD_WEB / "index.html").exists():
                return self._send(200, ("<body style='background:#14161f;color:#e6e8ef;font:15px sans-serif;padding:40px'>"
                                        "还没有网页版：在「AI 资产工坊」标签里点「更新网页版」，或运行 "
                                        "godot --headless --path godot --export-release Web ../build/web/index.html</body>").encode("utf-8"),
                                  "text/html; charset=utf-8")
            return self._file(BUILD_WEB, "index.html")
        if path.startswith("/game/"):
            return self._file(BUILD_WEB, path[len("/game/"):])
        if path == "/api/library":
            return self._send(200, read_library())
        if path == "/api/poses":
            # 动作编辑器用：默认姿势、各参数合法范围、内置动作、已有的自定义动作
            custom = {}
            for p in sorted((SPECS / "actions").glob("*.json")):
                try:
                    act, _ = poses.validate_action(json.loads(p.read_text(encoding="utf-8")))
                    custom[act["id"]] = act
                except ValueError:
                    pass
            return self._send(200, {"neutral": poses.NEUTRAL, "ranges": poses.RANGES, "builtin": poses.ACTIONS,
                                    "custom": custom})
        if path == "/api/web":
            f = BUILD_WEB / "index.pck"
            return self._send(200, {"exists": f.exists(), "mtime": f.stat().st_mtime if f.exists() else 0})
        if path == "/api/ping":
            return self._send(200, {"ok": True, "name": "PixelWorld 资产工坊"})
        if path == "/api/config":
            return self._send(200, public_config(load_config()))
        if path == "/api/assets":
            return self._send(200, list_assets())
        if path.startswith("/api/jobs/"):
            job = JOBS.get(path.rsplit("/", 1)[-1])
            return self._send(200, job.to_dict()) if job else self._send(404, {"error": "没有这个任务"})
        if path == "/api/jobs":
            return self._send(200, [j.to_dict() for j in sorted(JOBS.values(), key=lambda j: -j.started)][:20])
        if path.startswith("/api/spec/"):
            _, _, _, kind, sid = path.split("/", 4)
            spec = read_spec(kind, sid) if kind in SPEC_DIRS else None
            return self._send(200, spec) if spec else self._send(404, {"error": "没有这个规格"})
        if path.startswith("/files/sprites/"):
            return self._file(SPRITES, path[len("/files/sprites/"):])
        if path.startswith("/files/previews/"):
            return self._file(WORK / "previews", path[len("/files/previews/"):])
        if path.startswith("/static/"):
            return self._file(WEB, path[len("/static/"):])
        self._send(404, {"error": "没有这个地址"})

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            body = self._body()
        except ValueError as e:
            return self._send(400, {"error": str(e)})
        if path == "/api/config":
            return self._send(200, public_config(save_config(body)))
        if path == "/api/models":
            # 用网页上当前填的值（不用先保存）；Key 没改（还是遮盖的 ••••）就用已保存的
            cfg = load_config()
            for k in ("provider", "host", "api_key"):
                v = body.get(k)
                if v is not None and not (k == "api_key" and (not v or str(v).startswith("••"))):
                    cfg[k] = v
            try:
                return self._send(200, {"ok": True, "models": list_models(cfg)})
            except LLMError as e:
                return self._send(200, {"ok": False, "error": str(e)})
        if path == "/api/test":
            cfg = load_config()
            try:
                text, usage = call_llm(cfg, "你是连接测试助手。", "只回复两个字：成功", max_tokens=2000)
                return self._send(200, {"ok": True, "reply": text.strip()[:60], "usage": usage})
            except LLMError as e:
                return self._send(200, {"ok": False, "error": str(e)})
        if path == "/api/library":
            # 工具箱（新增分类 / 子分类、移动资源）和工坊（新建分类）都用这个保存整份分类结构
            return self._send(200, write_library(body))
        if path == "/api/export_web":
            job = Job("web", body)
            JOBS[job.id] = job
            threading.Thread(target=run_export_job, args=(job,), daemon=True).start()
            return self._send(200, {"job": job.id})
        if path == "/api/generate":
            kind = body.get("kind")
            if kind not in VALIDATORS:
                return self._send(400, {"error": "kind 必须是 character / action / prop"})
            job = Job(kind, body)
            JOBS[job.id] = job
            threading.Thread(target=run_job, args=(job,), daemon=True).start()
            return self._send(200, {"job": job.id})
        self._send(404, {"error": "没有这个地址"})


def main():
    ap = argparse.ArgumentParser(description="PixelWorld 资产工坊")
    ap.add_argument("--port", type=int, default=8777)
    ap.add_argument("--host", default="127.0.0.1")
    args = ap.parse_args()
    WORK.mkdir(exist_ok=True)
    cfg = load_config()
    print("PixelWorld 资产工坊：http://%s:%d" % (args.host, args.port))
    print("  模型：%s / %s（%s）" % (cfg["provider"], cfg["model"], "已配置 Key" if cfg.get("api_key") else "未配置 Key"))
    print("  Blender：%s" % (find_blender(cfg) or "没找到（在网页设置里填路径）"))
    print("  Godot：%s" % (find_godot(cfg) or "没找到（生成后在 Godot 编辑器里导入）"))
    kinds = missing_previews()
    if kinds and find_blender(cfg):
        print("  缺 %d 张预览图，后台补渲染……" % len(kinds))
        job = Job("preview", {})
        JOBS[job.id] = job
        threading.Thread(target=run_preview_job, args=(job, kinds), daemon=True).start()
    try:
        srv = ThreadingHTTPServer((args.host, args.port), Handler)
    except OSError:
        print("端口 %d 被占用了：换一个，比如 python tools/pw_asset_server.py --port %d" % (args.port, args.port + 1))
        sys.exit(1)
    srv.serve_forever()


if __name__ == "__main__":
    main()
