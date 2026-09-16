/* ==========================================================================
   一页时光 · 设计稿 · iPad / Mac（三栏版面）
   这一套与手机端<b>分开设计</b>：手机的目标是「横竖屏都排得下」，宽屏的目标是
   「用宽度换信息密度」。因此这里统一采用三栏：

       左：导航轨（系统 sidebarAdaptable 的形态）
       中：主列表（月历 / 统计+图表 / 筛选 / 设置卡片）
       右：详情（选中日的日记 / 地点清单 / 结果预览）

   第三栏只在窗口 ≥1180pt 时出现；不到就回到两栏，再不到就回到单栏。
   本文件当前只做「先行版」，用于验证三栏骨架；细节按你的要求后续再打磨。
   ========================================================================== */

/* 三栏骨架：左导航轨 + 中 + 右 */
function threePane(dev, layout, mid, right, opts) {
  const o = Object.assign({ midW: 420, right: true }, opts);
  return `<div class="shell-row">
      <div class="pane" style="width:${o.midW}px;flex:none;padding:0 16px;border-right:1px solid var(--divider)">
        <div class="pane-scroll" style="padding:0;gap:12px">${mid}</div>
      </div>
      <div class="pane" style="padding:0">
        <div class="pane-scroll" style="padding:0 20px">${right}</div>
      </div>
    </div>
    ${tabbar(layout, o.current || "日记")}`;
}

/* 导航轨（系统 sidebarAdaptable 在宽窗口的形态） */
function navRail(layout, current) {
  const items = [
    ["日记", ICON.home], ["足迹", ICON.walk], ["搜索", ICON.search], ["设置", ICON.gear],
  ].map(([label, icon]) =>
    `<div class="item${label === current ? " active" : ""}">${icon}${label}</div>`).join("");
  return `<div class="sidebar">
    <div class="side-title">一页时光</div>
    ${items}
    <div class="spacer"></div>
    <div class="side-foot">侧边栏由系统在窗口<br>足够宽时自动切换</div>
  </div>`;
}

/* iPad / Mac 首页：中＝月历，右＝选中日 */
function wideHome(dev, layout) {
  const rail = navRail(layout, "日记");
  const midW = dev.w >= 1300 ? 460 : 400;
  const cellH = Math.max(56, Math.min(120, Math.floor((dev.h - 130) / 6)));
  const mid = `
    ${calPaneHead(layout, { today: false, pad: "2px 2px 6px" })}
    ${monthGrid({ cellH, lunar: true, sel: 16 })}
    <div class="card tight" style="margin-top:12px">
      <div style="font-size:var(--t-sub);font-weight:600;color:var(--on-surface-variant);margin-bottom:6px">9月其余记录</div>
      ${tree().replace(/globe|map/g, "pin")}
    </div>`;
  const right = `
    ${contentHead(layout, { big: true, todayChip: true })}
    ${DIARY.map((d) => dayCard(d)).join("")}
    <div style="height:120px"></div>`;
  return `${rail}${threePane(dev, layout, mid, right, { midW, current: "日记" })}`;
}

/* iPad / Mac 足迹：中＝统计 + 图表，右＝地点清单 */
function wideFootprint(dev, layout) {
  const rail = navRail(layout, "足迹");
  const years = [[2023, 4], [2024, 11], [2025, 19], [2026, 37]];
  const midW = dev.w >= 1300 ? 480 : 420;
  const mid = `
    <div class="pane-head" style="padding:2px 2px 0"><span class="ph-title">足迹</span></div>
    ${statRow()}
    <div class="card" style="display:flex;flex-direction:column;flex:1;min-height:240px">
      <div style="font-size:var(--t-sub);font-weight:600;color:var(--on-surface-variant);margin-bottom:8px">年度记录天数</div>
      <div style="flex:1;display:flex;min-height:170px;padding-bottom:22px">${bars(years)}</div>
    </div>`;
  const right = `
    <div class="pane-head" style="padding:2px 2px 6px">
      <span class="ph-title" style="font-size:var(--t-card)">地点清单</span>
      <div style="flex:1"></div>
      <span class="chip active">全部</span><span class="chip">2026</span>
    </div>
    <div class="card">${tree()}</div>
    <div style="height:120px"></div>`;
  return `${rail}${threePane(dev, layout, mid, right, { midW, current: "足迹" })}`;
}

/* iPad / Mac 搜索：中＝条件，右＝结果 + 预览 */
function wideSearch(dev, layout) {
  const rail = navRail(layout, "搜索");
  const results = [
    { date: "9月16日 周三", time: "07:20", body: DIARY[0].body },
    { date: "9月12日 周六", time: "18:02", body: "傍晚又去湖边走了半圈，雾比早上薄，水面能看见对岸的灯。" },
    { date: "9月8日 周二", time: "06:55", body: "起雾了，能见度不到五十米，骑车的时候只敢慢慢走。" },
    { date: "8月30日 周日", time: "20:11", body: "台风过境前的一天，云压得很低，远处的山被雾裹住了一半。" },
  ];
  const midW = dev.w >= 1300 ? 380 : 340;
  const showPreview = dev.w >= 1180;
  const mid = `
    <div class="pane-head" style="padding:2px 2px 0"><span class="ph-title">搜索</span></div>
    <div class="searchfield">${ICON.search}<span style="flex:1;color:var(--on-surface)">雾</span>${ICON.xmark}</div>
    <div class="card tight">
      <div style="font-size:var(--t-caption);color:var(--on-surface-variant);margin-bottom:6px">时间</div>
      <div class="chip-row" style="flex-wrap:wrap">
        <span class="chip">全部</span><span class="chip">本周</span><span class="chip">本月</span>
        <span class="chip">本年</span><span class="chip active">9月1日 – 9月16日</span>
      </div>
      <div style="font-size:var(--t-caption);color:var(--on-surface-variant);margin:10px 0 6px">地点</div>
      <div class="chip-row" style="flex-wrap:wrap">
        <span class="chip">全部</span><span class="chip active">中国 · 浙江省</span><span class="chip">无地点</span>
      </div>
    </div>`;
  const list = results.map((r, i) => `<div class="result" style="${i === 0 ? "box-shadow:0 0 0 2px var(--primary),var(--card-shadow)" : ""}">
      <div style="flex:1;min-width:0">
        <div style="margin-bottom:6px"><span class="tag">${ICON.cal}${r.date}</span></div>
        <div class="snip">${r.body.replace(/雾/g, "<mark>雾</mark>")}</div>
      </div>
      <div class="time">${r.time}</div>
    </div>`).join("");
  const right = `
    <div style="display:flex;gap:14px;height:100%;min-height:0">
      <div style="flex:1;min-width:280px;display:flex;flex-direction:column;gap:10px;min-height:0">${list}</div>
      ${showPreview ? `<div style="flex:1;min-width:280px">
        <div class="card tight">
          <div class="card-meta">${ICON.cal}<span style="color:var(--primary);font-weight:600">9月16日 周三</span>${ICON.clock}<span>07:20</span></div>
          <div class="card-title">清晨的湖边</div>
          <div class="card-body">${esc(DIARY[0].body)}</div>
          <div class="card-body" style="margin-top:10px;color:var(--primary);font-size:var(--t-sub)">在日记页中打开 ›</div>
        </div>
      </div>` : ""}
    </div>
    <div style="height:120px"></div>`;
  return `${rail}${threePane(dev, layout, mid, right, { midW, current: "搜索" })}`;
}

/* iPad / Mac 设置：中＝通用/规则，右＝提醒/数据/关于 */
function wideSettings(dev, layout) {
  const rail = navRail(layout, "设置");
  const cards = settingCards();
  const midW = dev.w >= 1300 ? 420 : 380;
  const mid = `
    <div class="pane-head" style="padding:2px 2px 0"><span class="ph-title">设置</span></div>
    ${cards.slice(0, 2).join("")}`;
  const right = `
    <div style="display:grid;gap:12px;grid-template-columns:repeat(${dev.w >= 1180 ? 2 : 1},minmax(0,1fr));
                max-width:${dev.w >= 1180 ? 760 : 520}px">
      ${cards.slice(2).join("")}
    </div>
    <div style="height:120px"></div>`;
  return `${rail}${threePane(dev, layout, mid, right, { midW, current: "设置" })}`;
}

/* Duo 内屏：仍是 iPhone → 紧凑档，单栏（与手机竖屏同一套） */
function duoInner(dev, layout) {
  const cellH = Math.max(34, Math.min(72, Math.floor((dev.h - 172) / 5)));
  return `
    <div class="pane" style="padding:0 16px">
      ${calPaneHead(layout, { today: true })}
      <div class="pane-scroll" style="padding:0 0 4px;gap:0">
        <div style="flex:none">${monthGrid({ cellH, lunar: true, sel: 16 })}</div>
        <div style="flex:none;margin-top:14px">
          <div class="block-divider">9月16日 周三 · 八月初六</div>
          ${dayCard(DIARY[0])}
        </div>
      </div>
    </div>
    ${tabbar(layout, "日记")}`;
}

/* ------------------------------------------------------------------ 宽屏画框 */

FRAMES.push(
  {
    id: "wide-home", kind: "home", dev: "mac",
    title: "首页 · Mac 窗口 / iPad（三栏）",
    tag: "三栏骨架",
    note: "宽屏统一用三栏：左导航轨（系统 sidebarAdaptable 的形态）、中月历、右选中日的日记。中间的月历保持「点日期即换右栏」的轻交互，不抢右栏的阅读空间。这一版是骨架验证；细节按你的要求之后单独打磨。",
    screen: wideHome,
    annots: [
      { x: 250, y: 240, t: "左：系统导航轨（≥1100pt 自动出现）" },
      { x: 620, y: 120, t: "中：月历，点日期换右栏" },
      { x: 1000, y: 120, t: "右：选中日的日记，限宽阅读" },
    ],
    spec: [
      ["导航轨", "236pt（系统）"],
      ["中栏", "400–460pt"],
      ["右栏", "剩余宽度，正文列 ≤660pt"],
      ["分栏阈值", "≥980pt 两栏；≥1180pt 出第三栏"],
    ],
  },
  {
    id: "wide-footprint", kind: "footprint", dev: "mac",
    title: "足迹 · Mac 窗口 / iPad（三栏）",
    tag: "三栏骨架",
    note: "中栏放统计与趋势图（图表能长到 240pt 高），右栏放地点清单。两者独立滚动：看趋势和查地点是两件事。",
    screen: wideFootprint,
    annots: [
      { x: 620, y: 120, t: "中：统计 + 趋势图" },
      { x: 1000, y: 120, t: "右：地点清单，独立滚动" },
    ],
    spec: [
      ["中栏", "420–480pt"],
      ["图表高度", "≥240pt"],
      ["右栏", "地点清单，缩进 18pt/级"],
    ],
  },
  {
    id: "wide-search", kind: "search", dev: "mac",
    title: "搜索 · Mac 窗口 / iPad（三栏）",
    tag: "三栏骨架",
    note: "中栏是条件（搜索框 + 筛选），右栏是结果并在 ≥1180pt 时并排一条预览 —— 搜索的价值在于快速确认再跳转，有预览就不用来回进出日记页。",
    screen: wideSearch,
    annots: [
      { x: 560, y: 160, t: "中：条件与筛选" },
      { x: 1000, y: 120, t: "右：结果 + 预览（≥1180pt 才并排）" },
    ],
    spec: [
      ["中栏", "340–380pt"],
      ["结果列表", "≥280pt"],
      ["预览", "窗口 ≥1180pt 时出现"],
      ["选中态", "结果行 2pt 描边 + 预览同步"],
    ],
  },
  {
    id: "wide-settings", kind: "settings", dev: "mac",
    title: "设置 · Mac 窗口 / iPad（三栏）",
    tag: "三栏骨架",
    note: "中栏放「通用 / 规则」，右栏放其余卡片并按宽度 1–2 列排。设置没有主从关系，所以按卡片自我完整地流动，不做左右详情。",
    screen: wideSettings,
    annots: [
      { x: 620, y: 120, t: "中：通用 / 规则" },
      { x: 1000, y: 120, t: "右：其余卡片，按宽度 1–2 列" },
    ],
    spec: [
      ["中栏", "380–420pt"],
      ["右栏", "≥1180pt 时 2 列"],
      ["卡片间距", "12pt"],
    ],
  },
  {
    id: "wide-duo-inner", kind: "home", dev: "duo",
    title: "iPhone Duo · 内屏展开（先行验证）",
    tag: "紧凑档 · 不是三栏",
    note: "Duo 内屏展开约 664 × 750pt，比 iPad 竖屏（1032pt）窄得多，所以它落在「紧凑」档：和手机竖屏一样是单栏，只是月格更高。重点在于 —— Duo 不需要任何专用布局，它只是同一个尺寸阶梯上的一个刻度。",
    screen: duoInner,
    annots: [
      { x: 30, y: 118, t: "664pt 落在紧凑档：与手机竖屏同一套单栏版面" },
      { x: 380, y: 250, t: "左右安全区分别读取，不假设对称" },
      { x: 380, y: 470, t: "折痕「避免区」接入点，等 27.1 reservedRegion" },
    ],
    spec: [
      ["内屏参考", "≈664 × 750pt"],
      ["档位", "紧凑（<700pt）→ 单栏"],
      ["尺寸类", "regular × regular（仍是 iPhone）"],
      ["判定依据", "宽度，不用 idiom/orientation"],
      ["折痕", "预留 reservedRegion 接入点（27.1+）"],
    ],
  }
);
