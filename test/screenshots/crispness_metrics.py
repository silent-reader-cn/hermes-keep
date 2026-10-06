#!/usr/bin/env python3
"""清晰度取证指标计算 —— 对 `.shots/crispness/<tag>/*.full.png` 按 `rects.json`
裁剪出目标区域，量两组指标：

  ① 文字笔画边缘过渡宽度：抗锯齿「中间灰」像素（亮度落在墨色与底色之间的
     15%–85% 带内）的**占比**，以及每行中间灰**连续游程的平均长度**。
     重采样（FittedBox 等比缩小 / 分数 DPR）会把笔画边缘摊成更多中间灰像素
     ⇒ 占比更高、游程更长。
  ② 前景 / 背景实测对比度：底色取裁剪区外圈 2px 环的众数色，墨色取全图最暗
     0.5% 像素的中位色，按 WCAG 2.1 公式 `(L亮+0.05)/(L暗+0.05)` 计算。

用法：
  python test/screenshots/crispness_metrics.py before after
产物：每个 tag 目录下 `<name>.crop.png`（1:1 裁剪）+ 标准输出的对照表。
"""

from __future__ import annotations

import json
import os
import sys
from collections import Counter

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".shots", "crispness")


def _lin(c: float) -> float:
    s = c / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def lum(rgb) -> float:
    r, g, b = rgb[0], rgb[1], rgb[2]
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)


def contrast(fg, bg) -> float:
    a, b = lum(fg), lum(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def analyze(image_path: str, rect, out_crop: str) -> dict:
    img = Image.open(image_path).convert("RGB")
    left, top, w, h = (int(round(v)) for v in rect)
    left = max(0, left)
    top = max(0, top)
    w = min(w, img.width - left)
    h = min(h, img.height - top)
    crop = img.crop((left, top, left + w, top + h))
    crop.save(out_crop)

    px = crop.load()
    pixels = [px[x, y] for y in range(crop.height) for x in range(crop.width)]

    # 底色：外圈 2px 环的众数色（避开正文，最稳的背景估计）
    ring = []
    for y in range(crop.height):
        for x in range(crop.width):
            if x < 2 or y < 2 or x >= crop.width - 2 or y >= crop.height - 2:
                ring.append(px[x, y])
    bg = Counter(ring).most_common(1)[0][0]

    lums = [lum(c) for c in pixels]
    order = sorted(range(len(pixels)), key=lambda i: lums[i])
    k = max(1, len(pixels) // 200)
    ink = pixels[order[k // 2]]

    bg_l, ink_l = lum(bg), lum(ink)
    span = max(1e-6, bg_l - ink_l)
    lo, hi = ink_l + 0.15 * span, bg_l - 0.15 * span

    mid_mask = [[lo < lums[y * crop.width + x] < hi for x in range(crop.width)] for y in range(crop.height)]
    mid_count = sum(1 for row in mid_mask for v in row if v)

    runs = []
    for y in range(crop.height):
        x = 0
        row = mid_mask[y]
        while x < crop.width:
            if row[x]:
                start = x
                while x < crop.width and row[x]:
                    x += 1
                runs.append(x - start)
            else:
                x += 1

    return {
        "size": f"{w}x{h}",
        "bg": "#%02X%02X%02X" % bg,
        "ink": "#%02X%02X%02X" % ink,
        "contrast": contrast(ink, bg),
        "ink_lum": ink_l,
        "mid_px": mid_count,
        "mid_pct": 100.0 * mid_count / len(pixels),
        "edges": len(runs),
        "edge_run_mean": (sum(runs) / len(runs)) if runs else 0.0,
        "edge_run_max": max(runs) if runs else 0,
        "ink_coverage_pct": 100.0 * sum(1 for l in lums if l < lo) / len(pixels),
    }


def main(tags):
    result = {}
    for tag in tags:
        d = os.path.abspath(os.path.join(ROOT, tag))
        rects_path = os.path.join(d, "rects.json")
        if not os.path.exists(rects_path):
            print(f"!! 缺少 {rects_path}")
            continue
        with open(rects_path, "r", encoding="utf-8") as fh:
            rects = json.load(fh)
        for name, rect in rects.items():
            full = os.path.join(d, f"{name}.full.png")
            if not os.path.exists(full):
                continue
            result.setdefault(tag, {})[name] = analyze(
                full, rect, os.path.join(d, f"{name}.crop.png")
            )

    names = sorted({n for t in result.values() for n in t})
    print("| 目标 | 指标 | " + " | ".join(tags) + " | 变化 |")
    print("|---|---|" + "---|" * (len(tags) + 1))
    for n in names:
        keys = [
            ("size", "裁剪尺寸"),
            ("contrast", "前景/背景对比度"),
            ("ink", "墨色"),
            ("bg", "底色"),
            ("mid_pct", "中间灰像素占比 %"),
            ("edge_run_mean", "边缘过渡平均游程 px"),
            ("edge_run_max", "边缘过渡最大游程 px"),
            ("edges", "边缘游程条数"),
            ("ink_coverage_pct", "墨色覆盖 %"),
        ]
        for key, label in keys:
            vals = []
            for t in tags:
                v = result.get(t, {}).get(n, {}).get(key)
                vals.append("-" if v is None else (f"{v:.3f}" if isinstance(v, float) else str(v)))
            delta = ""
            if len(vals) == 2 and all(v not in ("-",) for v in vals):
                try:
                    a, b = float(vals[0]), float(vals[1])
                    delta = f"{b - a:+.3f}"
                except ValueError:
                    delta = ""
            print(f"| {n} | {label} | " + " | ".join(vals) + f" | {delta} |")


if __name__ == "__main__":
    main(sys.argv[1:] or ["before", "after"])
