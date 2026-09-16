#!/usr/bin/env node
/**
 * 把 docs/design/landscape/ 下的设计稿渲染成 PNG。
 *
 *   node tools/capture_design_mockups.mjs                 # 全部（手机 + iPad/Mac）
 *   node tools/capture_design_mockups.mjs ph-home         # 只渲染 id 含该子串的稿
 *   node tools/capture_design_mockups.mjs --phone         # 只手机端
 *   node tools/capture_design_mockups.mjs --wide          # 只 iPad / Mac
 *
 * 设计稿的唯一定义在 docs/design/landscape/frames-*.js，这里只负责按设备真实
 * 尺寸、2× 像素密度截出来。依赖本机 Google Chrome（无头模式）。
 */
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, statSync, writeFileSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const designDir = resolve(here, "../docs/design/landscape");
const outDir = join(designDir, "screens");
const tmpDir = join(designDir, ".capture");

const CHROME = process.env.CHROME
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const SCALE = Number(process.env.CAPTURE_SCALE || 2);

/* 在 vm 里求值设计稿脚本，取出 DEVICES / FRAMES。
   顶层 const 不会挂到 global 上，所以补一行显式导出。 */
const sandbox = { document: { addEventListener() {} }, console };
vm.createContext(sandbox);
for (const f of ["engine.js", "devices.js", "frames-phone.js",
                 "frames-phone-portrait.js", "frames-wide.js"]) {
  vm.runInContext(readFileSync(join(designDir, f), "utf8"), sandbox, { filename: f });
}
vm.runInContext("globalThis.__D = { DEVICES, FRAMES, layoutFor };", sandbox);
const { DEVICES, FRAMES } = sandbox.__D;

const args = process.argv.slice(2);
const onlyPhone = args.includes("--phone");
const onlyWide = args.includes("--wide");
const filter = args.find((a) => !a.startsWith("--"));

const frames = FRAMES.filter((f) => {
  const dev = DEVICES[f.dev];
  if (onlyPhone && dev.type !== "phone") return false;
  if (onlyWide && dev.type === "phone") return false;
  if (filter && !f.id.includes(filter)) return false;
  return true;
});
if (!frames.length) {
  console.error('没有匹配 "' + (filter || "") + '" 的稿');
  process.exit(1);
}

mkdirSync(outDir, { recursive: true });
mkdirSync(tmpDir, { recursive: true });

/** 资源版本串：改过源码就变，用来击穿 Chrome 对 file:// 资源的缓存。
    没有它时会出现「源码改了、截图没变」的假象（本工具踩过一次）。 */
function assetVersion() {
  let stamp = 0;
  for (const f of ["engine.js", "devices.js", "frames-phone.js",
                   "frames-phone-portrait.js", "frames-wide.js", "mockup.css"]) {
    try { stamp = Math.max(stamp, Math.round(statSync(join(designDir, f)).mtimeMs)); }
    catch {}
  }
  return "?v=" + stamp;
}

/** 单帧页面：设备本体 + 标题条 + 图例，方便直接贴进文档或评审 */
function pageHTML(frame) {
  const dev = DEVICES[frame.dev];
  const w = Math.round(dev.w);
  const h = Math.round(dev.h);
  const kind = frame.kind || frame.id.split("-")[0];
  const V = assetVersion();
  const island = dev.type === "phone" ? '<div class="island"></div>' : "";
  const lights = dev.type === "mac" ? '<div class="lights"><i></i><i></i><i></i></div>' : "";
  const zoneScript = (dev.type === "phone" && dev.landscape)
    ? 'document.getElementById("zone").innerHTML = '
      + '\'<div class="zone island-zone" style="width:\' + PHONE_CHROME.islandW + \'px;height:180px">\' '
      + '+ \'<span>灵动岛 / 硬件区<br>不放内容</span></div>\';'
    : "";
  return [
    '<!DOCTYPE html><html lang="zh-Hans" data-theme="' + (process.env.CAPTURE_THEME || "dark") + '"><head><meta charset="utf-8">',
    '<link rel="stylesheet" href="../mockup.css' + V + '">',
    "<style>",
    "  html,body { background:#0A0C10; margin:0; color-scheme:dark; }",
    "  .page { padding:30px 34px 34px; display:inline-block; }",
    "  .head { margin-bottom:16px; color:#E1E2E8; font-family:var(--font); }",
    "  .head h1 { font-size:19px; margin:0 0 4px; font-weight:650; letter-spacing:-.01em; }",
    '  .head .meta { font-size:12.5px; opacity:.62; font-family:ui-monospace,"SF Mono",Menlo,monospace; }',
    "  .head .tag { display:inline-block; margin-left:8px; padding:2px 8px; border-radius:999px;",
    "               font-size:11px; font-weight:600; background:rgba(37,99,235,.22); color:#8FB6FF; }",
    "  .note { max-width:" + w + "px; margin-top:18px; font-size:12.5px; line-height:1.65;",
    "          color:#C5C6D0; font-family:var(--font); opacity:.85; }",
    "  .callout-legend { max-width:" + w + "px; }",
    "</style></head><body>",
    '<div class="page">',
    '  <div class="head">',
    "    <h1>" + frame.title + '<span class="tag">' + frame.tag + "</span></h1>",
    '    <div class="meta">' + dev.name + " · " + w + " × " + h + " pt · " + frame.id + "</div>",
    "  </div>",
    '  <div class="device ' + dev.type + (dev.landscape ? " landscape" : "") + ' stage-annot"',
    '       style="width:' + w + "px;height:" + h + 'px;position:relative">',
    '    <div class="bg-layer"><span class="blob b-a"></span><span class="blob b-b"></span><span class="blob b-c"></span></div>',
    '    <div class="shell" id="mount"></div>',
    "    " + island + lights,
    '    <div id="zone"></div>',
    '    <div class="annot-layer" id="annots"></div>',
    "  </div>",
    '  <div class="note">' + frame.note + "</div>",
    '  <div class="note" id="legend" style="opacity:1"></div>',
    "</div>",
    '<script src="../engine.js' + V + '"><\/script>',
    '<script src="../devices.js' + V + '"><\/script>',
    '<script src="../frames-phone.js' + V + '"><\/script>',
    '<script src="../frames-phone-portrait.js' + V + '"><\/script>',
    '<script src="../frames-wide.js' + V + '"><\/script>',
    "<script>",
    '  const dev = DEVICES["' + frame.dev + '"];',
    '  const layout = layoutFor(dev, "' + kind + '");',
    '  const frame = FRAMES.find((f) => f.id === "' + frame.id + '");',
    '  document.getElementById("mount").innerHTML = frame.screen(dev, layout);',
    '  document.getElementById("annots").innerHTML = annots(frame.annots, frame.id);',
    '  document.getElementById("legend").innerHTML = annotLegend(frame.annots, frame.id);',
    "  " + zoneScript,
    "<\/script>",
    "</body></html>",
  ].join("\n");
}

let ok = 0;
for (const frame of frames) {
  const dev = DEVICES[frame.dev];
  const file = join(tmpDir, frame.id + ".html");
  writeFileSync(file, pageHTML(frame), "utf8");

  const out = join(outDir, frame.id + ".png");
  const winW = Math.round(dev.w) + 80;
  const winH = Math.round(dev.h) + 230;
  try {
    execFileSync(CHROME, [
      "--headless", "--disable-gpu", "--hide-scrollbars",
      "--force-device-scale-factor=" + SCALE,
      "--window-size=" + winW + "," + winH,
      "--virtual-time-budget=4000",
      "--screenshot=" + out,
      "file://" + file,
    ], { stdio: ["ignore", "ignore", "pipe"] });
    console.log("✓ " + frame.id + ".png  (" + winW + "×" + winH + "pt @" + SCALE + "x)");
    ok += 1;
  } catch (err) {
    console.error("✗ " + frame.id + ": " + err.message.split("\n")[0]);
  }
}

rmSync(tmpDir, { recursive: true, force: true });
console.log("\n" + ok + "/" + frames.length + " 张已写入 docs/design/landscape/screens/");
