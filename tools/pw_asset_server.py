#!/usr/bin/env python3
"""PixelWorld 资产工坊：本地网页 + 生成服务。在网页里配置大模型（API Key、Host、模型），
用一句话 / 一张原画生成像素角色、角色动作和 3D 摆件——大模型只写 JSON 规格，Blender 负责建模和渲染，画风和场景一致。

启动（Windows / macOS 一样，需要 Python 3.10+）：
    pip install -r tools/requirements.txt      # 用 Claude 时需要（anthropic SDK）；只用 OpenAI 兼容接口可以不装
    python tools/pw_asset_server.py            # 然后浏览器打开 http://127.0.0.1:8777
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
            _import_godot(job, cfg)
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
        if re.search(r"角色|已生成|已导出|规格|动作|Error|Traceback|错误|跳过|^\s+bl_", line) and "Saved:" not in line:
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
    chars = []
    for c in sc.get("characters", []):
        spec_file = SPECS / "characters" / ("%s.json" % c["id"])
        chars.append({"id": c["id"], "name": c.get("name"), "desc": c.get("desc"), "anims": c.get("anims", {}),
                      "generated": spec_file.exists(), "preview": "/files/previews/char_%s.png" % c["id"]
                      if (WORK / "previews" / ("char_%s.png" % c["id"])).exists() else ""})
    props = []
    for a in _blender_catalog().get("assets", []):
        props.append({"id": a["id"], "name": a.get("name"), "desc": a.get("desc"), "category": a.get("category"),
                      "tags": a.get("tags", []), "source": a.get("source", "generator"), "variants": len(a.get("files", [])),
                      "preview": "/files/previews/prop_%s.png" % a["kind"]
                      if (WORK / "previews" / ("prop_%s.png" % a["kind"])).exists() else ""})
    actions = []
    for p in sorted((SPECS / "actions").glob("*.json")):
        try:
            a = json.loads(p.read_text(encoding="utf-8"))
            actions.append({"id": a.get("id"), "name": a.get("name"), "frames": a.get("frames"), "for": a.get("for", [])})
        except ValueError:
            pass
    return {"characters": chars, "props": props, "actions": actions, "frame": sc.get("frame", 128),
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
            return self._file(WEB, "index.html")
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
        if path == "/api/test":
            cfg = load_config()
            try:
                text, usage = call_llm(cfg, "你是连接测试助手。", "只回复两个字：成功", max_tokens=2000)
                return self._send(200, {"ok": True, "reply": text.strip()[:60], "usage": usage})
            except LLMError as e:
                return self._send(200, {"ok": False, "error": str(e)})
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
    try:
        srv = ThreadingHTTPServer((args.host, args.port), Handler)
    except OSError:
        print("端口 %d 被占用了：换一个，比如 python tools/pw_asset_server.py --port %d" % (args.port, args.port + 1))
        sys.exit(1)
    srv.serve_forever()


if __name__ == "__main__":
    main()
