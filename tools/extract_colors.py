"""从原画里提取主要颜色（Blender 无界面运行，因为要用 Blender 读 jpg / png）：

    blender -b --factory-startup -P tools/extract_colors.py -- <图片路径> [颜色数=10]

输出一行 JSON：{"colors": [["#rrggbb", 占比], ...]}。资产工坊把它连同原画一起交给大模型，模型按部位挑色。
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "blender"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402

from pw_specs import refimage  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
img = bpy.data.images.load(argv[0])
w, h = img.size
buf = np.empty(w * h * 4, dtype=np.float32)
img.pixels.foreach_get(buf)
px = buf.reshape(-1, 4)[:, :3]
# Blender 读进来是线性颜色，转回 sRGB 再统计（和人眼 / 网页里看到的颜色一致）
px = np.where(px <= 0.0031308, px * 12.92, 1.055 * np.power(np.clip(px, 0, 1), 1 / 2.4) - 0.055)
k = int(argv[1]) if len(argv) > 1 else 10
print("PW_COLORS " + json.dumps({"colors": refimage.dominant_colors(px, k)}))
