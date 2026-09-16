#!/usr/bin/env python3
"""Seed a simulator with sample diary data for development and screenshots.

The sample set is deliberately varied: several countries and provinces, several
years, blocks with and without a location, and a mix of content part types
(heading, paragraph, quote, list, todo) so every screen has something to show.

Usage:
    python3 tools/seed_sample_diary.py                 # auto-detect the booted sim
    python3 tools/seed_sample_diary.py "iPhone 18 Pro" # pick a device by name

Note: writing into a simulator container requires read/write access to
~/Library/Developer/CoreSimulator.
"""
import json
import os
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime

BUNDLE_ID = "com.cov.justdiary"

# (dayKey, time, country, code, region1, region2, region3, lat, lng, locText, [parts])
def p(text):      return {"type": "p", "text": text}
def h1(text):     return {"type": "h1", "text": text}
def h2(text):     return {"type": "h2", "text": text}
def quote(text):  return {"type": "quote", "text": text}
def ul(items):    return {"type": "ul", "items": items}
def todo(items, done): return {"type": "todo", "items": items, "done": done}


def run(text, bold=False, italic=False, underline=False, strike=False):
    """One styled span, mirroring `TextRun`.

    A `size` is written only for a custom size (imported material). Text the app
    authors always renders at its block's design size — Apple's ladder, i.e.
    title 28 / heading 22 / body 17 / quote 15 — so storing one would be
    redundant and, worse, ambiguous.
    """
    r = {"text": text}
    if bold:      r["bold"] = True
    if italic:    r["italic"] = True
    if underline: r["underline"] = True
    if strike:    r["strike"] = True
    return r


def rich(part_type, *runs, align=None):
    """A paragraph built from styled runs, optionally centered."""
    part = {"type": part_type, "runs": list(runs)}
    if align: part["align"] = align
    return part


def part_text(part):
    """Plain text of a part, for `summary` / `search_text`."""
    if part.get("runs"):
        return "".join(r.get("text", "") for r in part["runs"])
    if part.get("text") is not None:
        return part["text"]
    if part.get("items"):
        return " ".join(part["items"])
    return ""


ENTRIES = [
    ("2024-05-12", "09:10", "中国", "CN", "广东省", "深圳市", "南山区", 22.54, 113.95,
     "南山区 · 深圳市 · 广东省 · 中国",
     [h1("搬来深圳第一周"),
      p("早上六点被楼下的早茶香味叫醒。这里的节奏比想象中快，但楼下的肠粉摊很温柔。"),
      ul(["找到住处", "办好门禁卡", "认识了隔壁的猫"])]),
    ("2024-05-12", "20:30", "中国", "CN", "广东省", "深圳市", "南山区", 22.54, 113.95,
     "南山区 · 深圳市 · 广东省 · 中国",
     [p("晚上沿着深圳湾走了很久，对岸的灯一层一层亮起来。"),
      quote("陌生的城市也可以慢慢变成自己的。")]),
    ("2024-06-02", "14:00", "中国", "CN", "广东省", "广州市", "天河区", 23.13, 113.32,
     "天河区 · 广州市 · 广东省 · 中国",
     [h2("广州一日"),
      p("早茶吃了三个小时，虾饺和凤爪都没有让人失望。"),
      todo(["带一盒老婆饼回去", "拍骑楼"], [True, False])]),
    ("2024-10-01", "10:00", "中国", "CN", "北京市", "北京市", "海淀区", 39.98, 116.31,
     "海淀区 · 北京市 · 中国",
     [p("国庆第一天去了颐和园，人很多，但昆明湖的风很干净。")]),
    ("2024-10-03", "16:00", "中国", "CN", "北京市", "北京市", "朝阳区", 39.92, 116.44,
     "朝阳区 · 北京市 · 中国",
     [h2("胡同里的下午"),
      p("在五道营胡同的一家旧书店坐了一下午，老板养了一只很胖的橘猫。")]),
    ("2025-03-15", "11:00", "日本", "JP", "東京都", "新宿区", "新宿", 35.69, 139.70,
     "新宿 · 新宿区 · 東京都 · 日本",
     [h1("东京第一天"),
      p("从成田到新宿用了两个小时。御苑的樱花开得比预报早了一周。"),
      ul(["新宿御苑", "思い出横丁", "都厅展望台"])]),
    ("2025-03-16", "18:30", "日本", "JP", "東京都", "渋谷区", "渋谷", 35.66, 139.70,
     "渋谷 · 渋谷区 · 東京都 · 日本",
     [p("在涩谷十字路口站了十分钟，只是为了看人怎么同时往八个方向走。")]),
    ("2025-06-08", "09:00", "中国", "CN", "浙江省", "杭州市", "西湖区", 30.26, 120.13,
     "西湖区 · 杭州市 · 浙江省 · 中国",
     [h2("梅雨季的西湖"),
      p("雨下了一整夜。清晨的苏堤几乎没有人，湖面像一块没擦干的玻璃。"),
      quote("水光潋滟晴方好，山色空蒙雨亦奇。")]),
    ("2025-06-09", "15:00", "中国", "CN", "浙江省", "杭州市", "滨江区", 30.21, 120.21,
     "滨江区 · 杭州市 · 浙江省 · 中国",
     [p("下午在滨江的咖啡馆改了一下午的方案，窗外是钱塘江。")]),
    ("2025-09-22", "13:00", "美国", "US", "加利福尼亚州", "旧金山", "", 37.77, -122.42,
     "旧金山 · 加利福尼亚州 · 美国",
     [h1("到旧金山"),
      p("飞机穿过云层的时候刚好看到金门大桥。空气比想象中冷很多。"),
      ul(["租车", "倒时差", "去码头看海狮"])]),
    ("2025-09-25", "17:00", "美国", "US", "加利福尼亚州", "旧金山", "", 37.78, -122.41,
     "旧金山 · 加利福尼亚州 · 美国",
     [p("傍晚在 Twin Peaks 看了整个城市的灯亮起来。风大得站不稳。")]),
    ("2026-01-05", "12:00", "法国", "FR", "法兰西岛", "巴黎", "", 48.86, 2.35,
     "巴黎 · 法兰西岛 · 法国",
     [h2("巴黎的冬天"),
      p("塞纳河边的旧书摊大多关着，只有一家开着，老板在烤火。"),
      todo(["去橘园看睡莲", "买一张地铁周票"], [True, True])]),
    ("2026-04-02", "08:30", "中国", "CN", "广东省", "深圳市", "南山区", 22.54, 113.95,
     "南山区 · 深圳市 · 广东省 · 中国",
     [p("回深圳的第二天，又开始在楼下买肠粉。老板娘还记得我。")]),
    ("2026-05-18", "10:30", "中国", "CN", "上海市", "上海市", "浦东新区", 31.23, 121.51,
     "浦东新区 · 上海市 · 中国",
     [h1("上海出差"),
      p("从浦东机场出来，磁悬浮只用了八分钟。晚上在外滩走了一圈。"),
      quote("城市越大，人越容易在人群里安静下来。")]),
    # No location information at all — exercises the 未记录 count.
    ("2026-06-01", "07:00", "", "", "", "", "", 0.0, 0.0, "",
     [p("没出门的一天。把之前旅行的照片整理了一遍。")]),
    ("2026-06-11", "23:00", "", "", "", "", "", 0.0, 0.0, "",
     [h2("深夜"),
      p("写到这里已经很晚了。明天还要早起。")]),
    # Exercises the editor's paragraph styles and inline formats: one paragraph
    # per style, plus bold / italic / underline / strike and a centered line.
    ("2026-09-08", "21:40", "", "", "", "", "", 0.0, 0.0, "",
     [h1("字体样式自检"),
      p("这一段是正文，用来和下面的标题、引用对比字号。"),
      h2("小标题"),
      quote("引用块比正文小一级，并且有自己的底色。"),
      rich("p", run("这一段带"), run("粗体", bold=True), run("、"),
           run("斜体", italic=True), run("、"), run("下划线", underline=True),
           run("和"), run("删除线", strike=True), run("。")),
      rich("p", run("这一行是居中的正文。"), align="center"),
      todo(["验证标题层级", "验证引用底色", "验证行距"], [True, True, False])]),
]


def _is_cjk(ch):
    """Mirror of FtsSegment.isCJK in the app."""
    v = ord(ch)
    return (0x4E00 <= v <= 0x9FFF) or (0x3400 <= v <= 0x4DBF) or (0x3000 <= v <= 0x303F)


def segment(text):
    """Mirror of FtsSegment.segment: FTS5's unicode61 tokenizer treats a run of
    CJK characters as one token, so the app inserts a space between adjacent CJK
    characters before indexing. The sample rows must be indexed the same way or
    search finds nothing."""
    out = []
    prev = None
    for ch in text:
        if prev is not None and _is_cjk(prev) and _is_cjk(ch):
            out.append(" ")
        out.append(ch)
        prev = ch
    return "".join(out)


def resolve_db(device):
    container = subprocess.run(
        ["xcrun", "simctl", "get_app_container", device or "booted", BUNDLE_ID, "data"],
        capture_output=True, text=True, check=True).stdout.strip()
    if not container:
        sys.exit("could not resolve the app container; is the app installed?")
    return os.path.join(container, "Documents", "just_diary.db")


def main() -> None:
    db_path = resolve_db(sys.argv[1] if len(sys.argv) > 1 else None)
    print(f"seeding {db_path}")
    # Fold the WAL back into the main file first so the app sees a clean state.
    db = sqlite3.connect(db_path)
    cur = db.cursor()
    cur.execute("DELETE FROM edit_block")
    cur.execute("DELETE FROM diary")

    by_day = {}
    for row in ENTRIES:
        by_day.setdefault(row[0], []).append(row)

    diary_id = 1
    for day in sorted(by_day):
        rows = by_day[day]
        first_text = next((part_text(part) for part in rows[0][10]
                           if part["type"] in ("h1", "h2", "p") and part_text(part)), "")
        summary = first_text[:40] or "无地点记录"
        cur.execute("INSERT INTO diary(id, day_key, summary, search_text, created_utc, updated_utc)"
                    " VALUES(?,?,?,?,?,?)", (diary_id, day, summary, summary, 0, 0))
        for row in rows:
            (d, t, country, code, r1, r2, r3, lat, lng, loc, parts) = row
            hh, mm = map(int, t.split(":"))
            ms = int(datetime.strptime(d, "%Y-%m-%d").replace(hour=hh, minute=mm).timestamp() * 1000)
            text = " ".join(part_text(part) for part in parts)
            cur.execute(
                "INSERT INTO edit_block(diary_id, start_time_utc, loc_text, latitude, longitude,"
                " content_json, search_text, loc_precision, loc_quality, country, country_code,"
                " region1, region2, region3, created_utc, updated_utc)"
                " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (diary_id, ms, loc, lat, lng, json.dumps(parts, ensure_ascii=False), text,
                 "exact" if loc else "none", "precise" if loc else "none",
                 country, code, r1, r2, r3, 0, 0))
        diary_id += 1

    # The app only rebuilds the FTS index when its stored version changes, so
    # rows inserted behind its back have to be indexed here or search finds
    # nothing.
    cur.execute("DELETE FROM diary_fts")
    cur.execute("SELECT id, summary FROM diary")
    for did, summary in cur.fetchall():
        cur.execute("SELECT search_text FROM edit_block WHERE diary_id = ?", (did,))
        texts = [summary] + [r[0] for r in cur.fetchall() if r[0]]
        cur.execute("INSERT INTO diary_fts(diary_id, text) VALUES (?, ?)",
                    (did, segment(" ".join(texts))))

    db.commit()
    cur.execute("SELECT count(*) FROM diary")
    days = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM edit_block")
    blocks = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM diary_fts")
    indexed = cur.fetchone()[0]
    db.close()
    print(f"seeded {days} diaries / {blocks} blocks / {indexed} search-index rows")


if __name__ == "__main__":
    main()
