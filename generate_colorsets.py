#!/usr/bin/env python3
"""Generate Asset Catalog colorsets for the theme tokens."""
import json
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(ROOT, "JustDiary", "Resources", "Assets.xcassets")

TOKENS = {
    "bg": (0xFAF9FD, 0x101318),
    "onSurface": (0x191C20, 0xE1E2E8),
    "onSurfaceVariant": (0x44474F, 0xC5C6D0),
    "outlineVariant": (0xC5C6D0, 0x44474F),
    "glassDim": (0x73FFFFFF, 0x80262B36),
    "glassBorder": (0x8CFFFFFF, 0x33FFFFFF),
    "flowLight": (0xCCFFFFFF, 0x59FFFFFF),
    "blobA": (0x80AAC7FF, 0x8000468F),
    "blobB": (0x99BAD8FF, 0x8C264678),
    "blobC": (0x6EBBE9FF, 0x6E264678),
    "shadowColor": (0x14000000, 0x26000000),
    "quoteBg": (0xE4EAF9, 0x2B3344),
    "primaryContainer": (0xD0DBEF, 0x16233B),
}


def components(hexv):
    r = (hexv >> 16) & 0xFF
    g = (hexv >> 8) & 0xFF
    b = hexv & 0xFF
    raw_a = (hexv >> 24) & 0xFF
    a = 1.0 if raw_a == 0 else raw_a / 255.0
    return {"red": f"0x{r:02X}", "green": f"0x{g:02X}", "blue": f"0x{b:02X}", "alpha": f"{a:.3f}"}


def color_entry(hexv, dark=False):
    entry = {"color": {"color-space": "srgb", "components": components(hexv)}, "idiom": "universal"}
    if dark:
        entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
    return entry


for name, (light, dark) in TOKENS.items():
    d = os.path.join(ASSETS, f"{name}.colorset")
    os.makedirs(d, exist_ok=True)
    contents = {
        "colors": [color_entry(light), color_entry(dark, dark=True)],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(d, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, ensure_ascii=False, indent=2)
print(f"generated {len(TOKENS)} colorsets")
