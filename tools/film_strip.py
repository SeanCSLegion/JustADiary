#!/usr/bin/env python3
"""把 morph 逐帧附件拼成「胶片」：每帧裁出日历区、按顺序横向/纵向排列并标注帧名。

用法:
    python3 tools/film_strip.py <frames_dir> <out.png> [--top 0.62] [--cols 6] [--label]

配套 `tools/xcresult_frames.py`（先从 .xcresult 导出并改名）。
Note: 依赖 Pillow（`python3 -m pip install pillow`）；只用标准库的 python3 会 import 失败。
"""
import argparse
import os
import re
import sys

from PIL import Image, ImageDraw

NAME_RE = re.compile(r"^(?P<case>[A-Za-z0-9]+)-(?P<kind>[a-z]+)-(?P<idx>\d+)-(?P<ms>\d+)ms", re.I)


def collect(frames_dir):
    items = []
    for fn in os.listdir(frames_dir):
        if not fn.lower().endswith((".png", ".jpg", ".jpeg")):
            continue
        m = NAME_RE.match(fn)
        if not m:
            continue
        items.append((m.group("case"), m.group("kind"), int(m.group("idx")),
                      int(m.group("ms")), os.path.join(frames_dir, fn)))
    items.sort(key=lambda t: (t[0], t[1], t[2]))
    return items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("frames_dir")
    ap.add_argument("out")
    ap.add_argument("--top", type=float, default=0.62,
                    help="每帧保留上面多少比例（日历区在上面）")
    ap.add_argument("--cols", type=int, default=1)
    ap.add_argument("--scale", type=float, default=0.45)
    ap.add_argument("--filter", default=None, help="只看某个 case（next/prev/same）")
    ap.add_argument("--kind", default=None, help="只看某种（before/morph/after）")
    ap.add_argument("--label", action="store_true")
    args = ap.parse_args()

    items = collect(args.frames_dir)
    if args.filter:
        items = [t for t in items if t[0] == args.filter]
    if args.kind:
        items = [t for t in items if t[1] == args.kind]
    if not items:
        print("no frames matched", file=sys.stderr)
        return 1

    tiles = []
    for case, kind, idx, ms, path in items:
        im = Image.open(path).convert("RGB")
        w, h = im.size
        im = im.crop((0, 0, w, int(h * args.top)))
        if args.scale != 1.0:
            im = im.resize((int(im.width * args.scale), int(im.height * args.scale)),
                           Image.LANCZOS)
        tiles.append((f"{case}-{kind}-{idx:02d} {ms}ms" if args.label else None, im))

    cols = max(1, args.cols)
    rows = (len(tiles) + cols - 1) // cols
    tw = max(t[1].width for t in tiles)
    th = max(t[1].height for t in tiles)
    pad = 4
    label_h = 18 if args.label else 0
    sheet = Image.new("RGB", (cols * (tw + pad) + pad, rows * (th + pad + label_h) + pad),
                      (24, 24, 28))
    draw = ImageDraw.Draw(sheet)
    for i, (label, im) in enumerate(tiles):
        r, c = divmod(i, cols)
        x = pad + c * (tw + pad)
        y = pad + r * (th + pad + label_h)
        sheet.paste(im, (x, y))
        if label:
            draw.text((x + 2, y + th + 3), label, fill=(220, 220, 220))
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    sheet.save(args.out)
    print(f"{len(tiles)} frames -> {args.out}  ({sheet.width}x{sheet.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
