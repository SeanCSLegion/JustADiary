#!/usr/bin/env python3
"""把 xcresult 里的截图附件导出来并按可读名字重命名。

UI 测试用 `XCTAttachment(screenshot:)` 逐帧拍下 morph（见
`JustDiaryUITests/CrossMonthMorphUITests.swift`），附件名形如
`next-morph-07-1237ms`。`xcresulttool export` 导出的文件名是 UUID，这里按
manifest 里的 suggestedHumanReadableName 改回来，配合 `tools/film_strip.py`
就能拼出胶片。

用法:
    python3 tools/xcresult_frames.py <x.xcresult> <输出目录>
"""
import json
import os
import re
import shutil
import subprocess
import sys

DEV = os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    result, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments",
                    "--path", result, "--output-path", out],
                   check=True, env={**os.environ, "DEVELOPER_DIR": DEV},
                   stdout=subprocess.DEVNULL)
    manifest = json.load(open(os.path.join(out, "manifest.json")))
    n = 0
    for test in manifest:
        for a in test.get("attachments", []):
            name = re.sub(r"_\d+_[0-9A-F-]{36}(?=\.png$)", "",
                          a["suggestedHumanReadableName"])
            src, dst = os.path.join(out, a["exportedFileName"]), os.path.join(out, name)
            if os.path.exists(src) and not os.path.exists(dst):
                shutil.move(src, dst)
                n += 1
    print(f"{n} frames -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
