#!/usr/bin/env python3
"""资产工坊自检（不花钱、不需要真的 API Key）：

    python tools/workshop_selftest.py            # 只测模型接口这一段（几秒）
    python tools/workshop_selftest.py --full     # 再跑一次完整任务：模拟模型 → 校验 → Blender 生成 → Godot 导入

在本机起一个「模拟模型」服务，同时实现 Anthropic 的 /v1/messages 和 OpenAI 兼容的 /v1/chat/completions，
回复事先写好的规格 JSON。检查：
  1. Claude 路径：官方 anthropic SDK（base_url 指到模拟服务）发出的请求格式正确，原画图片也带上了
  2. OpenAI 兼容路径：/chat/completions 请求和解析
  3. 修正循环：模型第一次给的规格不合格时，错误信息会发回去，第二次合格就继续
  4.（--full）完整生成一个 3D 摆件，产物和预览图都在
"""
import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import pw_asset_server as ws  # noqa: E402

GOOD_PROP = {
    "id": "selftest_crate_stack", "name": "木箱堆", "category": "props", "desc": "自检用：三个叠起来的木箱。",
    "vary": "箱子大小", "tags": ["yard"], "variants": 1, "vars": {"s": {"rand": [0.5, 0.6]}},
    "parts": [
        {"shape": "box", "mat": "crate", "min": [-0.6, -0.3, 0], "max": [0.0, 0.3, "$s"]},
        {"shape": "box", "mat": "crate", "min": [0.05, -0.3, 0], "max": [0.65, 0.3, "$s"]},
        {"shape": "box", "mat": "crate", "min": [-0.3, -0.25, "$s"], "max": [0.3, 0.25, "$s*2"]},
    ],
}
GOOD_CHAR = {"id": "selftest_fisher", "name": "渔家大婶", "desc": "自检用。", "hair": "bun", "skirt": 0.5,
             "colors": {"top": "#4a6fa5", "skirt": ["#efe9dc", "#cfc6b4", "#a8a296"]}}
STATE = {"calls": [], "bad_first": True, "bad_prop_first": False}


def _reply_for(system, user_text):
    if "3D 摆件" in system:
        if STATE["bad_prop_first"]:
            STATE["bad_prop_first"] = False
            return {"id": "broken", "parts": [{"shape": "cube", "mat": "unobtainium"}]}  # 一个零件都不合法 → 校验报错
        return GOOD_PROP
    if "像素角色" in system:
        if STATE["bad_first"]:
            STATE["bad_first"] = False
            return {"name": "坏规格", "colors": "不是对象"}  # 第一次故意给错，检查修正循环（校验会报 colors 的问题但仍可用）
        return GOOD_CHAR
    return {"ok": True}


class Mock(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])).decode("utf-8"))
        if self.path.endswith("/v1/messages"):
            assert "test-key" in (self.headers.get("x-api-key") or "") + (self.headers.get("Authorization") or ""), "Anthropic 请求没带 API Key"
            system = body["system"] if isinstance(body["system"], str) else json.dumps(body["system"], ensure_ascii=False)
            content = body["messages"][0]["content"]
            has_image = any(b.get("type") == "image" for b in content)
            text = next(b["text"] for b in content if b.get("type") == "text")
            STATE["calls"].append({"api": "anthropic", "model": body["model"], "image": has_image,
                                   "effort": body.get("output_config", {}).get("effort")})
            spec = _reply_for(system, text)
            out = {"id": "msg_mock", "type": "message", "role": "assistant", "model": body["model"],
                   "content": [{"type": "text", "text": "```json\n" + json.dumps(spec, ensure_ascii=False) + "\n```"}],
                   "stop_reason": "end_turn", "stop_sequence": None,
                   "usage": {"input_tokens": 1234, "output_tokens": 321}}
        elif self.path.endswith("/chat/completions"):
            assert self.headers.get("Authorization") == "Bearer test-key", "OpenAI 请求没带 Bearer key"
            system = body["messages"][0]["content"]
            user = body["messages"][1]["content"]
            has_image = any(p.get("type") == "image_url" for p in user)
            STATE["calls"].append({"api": "openai", "model": body["model"], "image": has_image})
            spec = _reply_for(system, user[0]["text"])
            out = {"model": body["model"], "choices": [{"message": {"role": "assistant",
                   "content": "好的：\n```json\n" + json.dumps(spec, ensure_ascii=False) + "\n```"}}],
                   "usage": {"prompt_tokens": 1000, "completion_tokens": 200}}
        else:
            self.send_response(404)
            self.end_headers()
            return
        data = json.dumps(out).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--full", action="store_true")
    args = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Mock)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d" % port
    ok = True

    def check(name, cond, extra=""):
        nonlocal ok
        print(("  通过  " if cond else "  失败  ") + name + (("：" + extra) if extra else ""))
        ok = ok and cond

    print("1. Claude（anthropic SDK）")
    cfg = dict(ws.DEFAULTS, provider="anthropic", host=base, api_key="test-key", model="claude-opus-5-5")
    img = {"media_type": "image/png", "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="}
    try:
        text, usage = ws.call_llm(cfg, ws.prompts.SYSTEM["prop"], "做一堆木箱", img)
        spec, warn = ws.propspec.validate(ws.extract_json(text))
        check("请求和解析", spec["id"] == GOOD_PROP["id"], usage)
        check("图片随请求发送", STATE["calls"][-1]["image"])
        check("思考强度 output_config.effort", STATE["calls"][-1]["effort"] == "medium")
    except Exception as e:  # noqa: BLE001
        check("请求和解析", False, repr(e))

    print("2. OpenAI 兼容接口")
    cfg2 = dict(ws.DEFAULTS, provider="openai", host=base + "/v1", api_key="test-key", model="some-model")
    try:
        text, usage = ws.call_llm(cfg2, ws.prompts.SYSTEM["prop"], "做一堆木箱", img)
        spec, warn = ws.propspec.validate(ws.extract_json(text))
        check("请求和解析", spec["id"] == GOOD_PROP["id"], usage)
        check("图片随请求发送", STATE["calls"][-1]["image"])
    except Exception as e:  # noqa: BLE001
        check("请求和解析", False, repr(e))

    print("3. 校验 + 修正循环（角色）")
    STATE["bad_first"] = True
    for attempt in range(2):
        text, _ = ws.call_llm(cfg, ws.prompts.SYSTEM["character"], "渔家大婶")
        spec, warn = ws.charspec.validate(ws.extract_json(text))
        if not warn:
            break
    check("第一次的问题被发现", attempt == 1)
    check("修正后合格", spec["id"] == "selftest_fisher" and spec["hair"] == "bun")

    if args.full:
        print("4. 完整任务：模拟模型 → 校验 → Blender → Godot 导入")
        ws.CONFIG_PATH = Path(ws.WORK) / "selftest_config.json"  # 不碰用户真实的配置
        ws.save_config(dict(provider="anthropic", host=base, api_key="test-key", model="claude-opus-5-5"))
        STATE["bad_prop_first"] = True
        n0 = len(STATE["calls"])
        job = ws.Job("prop", {"prompt": "自检：一堆木箱"})
        ws.run_job(job)
        check("不合格的规格被发回模型修正", len(STATE["calls"]) - n0 == 2)
        for line in job.logs:
            print("     " + line)
        check("任务完成", job.state == "done", job.status)
        glb = ws.BLENDER_ASSETS / "spec_selftest_crate_stack_0.glb"
        check("导出了 glb", glb.exists())
        check("生成了预览图", (ws.WORK / "previews" / "prop_spec_selftest_crate_stack.png").exists())
        cat = json.loads((ws.BLENDER_ASSETS / "catalog.json").read_text(encoding="utf-8"))
        check("进了资产目录", any(a["id"] == "bl_spec_selftest_crate_stack" for a in cat["assets"]))
        # 清理：自检产物不留在仓库里
        (ws.SPECS / "props" / "selftest_crate_stack.json").unlink(missing_ok=True)
        for p in ws.BLENDER_ASSETS.glob("spec_selftest_crate_stack*"):
            p.unlink()
        cat["assets"] = [a for a in cat["assets"] if a["id"] != "bl_spec_selftest_crate_stack"]
        (ws.BLENDER_ASSETS / "catalog.json").write_text(json.dumps(cat, ensure_ascii=False, indent=2), encoding="utf-8")
        ws.CONFIG_PATH.unlink(missing_ok=True)

    srv.shutdown()
    print("全部通过" if ok else "有失败项")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
