#!/usr/bin/env python3
"""Convert en/zh-Hans Localizable.strings into Localizable.xcstrings (String Catalog)."""
import json
import os
import re

ROOT = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(ROOT, "JustDiary", "Resources")
EN = os.path.join(RES, "en.lproj", "Localizable.strings")
ZH = os.path.join(RES, "zh-Hans.lproj", "Localizable.strings")

DEAD_KEYS = {
    "module_desc", "EntryAbility_desc", "EntryFormAbility_label", "EntryFormAbility_desc",
    "diary_widget_name", "diary_widget_desc", "reason_location", "index_notif_title",
    "index_notif_msg", "widget_written", "widget_not_written", "widget_start",
    "widget_continue", "widget_day_unit", "date_local",
}


def parse_strings(path):
    with open(path, encoding="utf-8") as f:
        content = f.read()
    result = {}
    pattern = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.MULTILINE)
    for m in pattern.finditer(content):
        key = m.group(1)
        value = m.group(2)
        value = value.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
        result[key] = value
    return result


en = parse_strings(EN)
zh = parse_strings(ZH)
assert en.keys() == zh.keys(), (set(en) ^ set(zh))

catalog = {"sourceLanguage": "en", "version": "1.0", "strings": {}}
for key in sorted(en):
    if key in DEAD_KEYS:
        continue
    catalog["strings"][key] = {
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en[key]}},
            "zh-Hans": {"stringUnit": {"state": "translated", "value": zh[key]}},
        }
    }

out = os.path.join(RES, "Localizable.xcstrings")
with open(out, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)
print(f"wrote {out} with {len(catalog['strings'])} keys")
