/* ==========================================================================
   一页时光 · 设计稿 · 手机端（iPhone 竖屏 / 横屏）
   本文件只描述手机**横屏**版面（竖屏复刻在 frames-phone-portrait.js）。
   2026-10-01：iPad / Mac 的三栏宽屏稿（frames-wide.js / wide.html / screens/wide-*.png）
   已删除 —— 不再制作宽屏端。

   横屏的三条硬事实（来自真机探针，不是猜测）：
   1. 系统浮条在横屏**仍在屏幕底部居中**、高 64pt（`app.tabBars` frame 实测
      `(0, 338, 874, 64)`，紧贴底边），**没有**「左侧竖排胶囊」这回事；左侧那 62pt 是
      **安全区**（`safeArea.leading`）—— 内容左边界 = 62，页面只再加自己的 16pt 页边距，
      不要在 62 之上再避让一次。本文件画的也是底部浮条（`layoutFor()` 的
      `tabbarStyle: "bottom"`）。
   2. 灵动岛在横屏竖转贴左边缘，占用区约 37（宽）× 132（高）、垂直居中
      （y ≈ 135–267），整块落在 x 0–37 内 —— 比安全区窄，所以左边界由安全区决定。
   3. 横屏不提供年份切换（保留竖屏原有的年历 morph 交互），只上下滑切月。
   ========================================================================== */

/* ------------------------------------------------------------------ 屏幕级绘制 */

/* 首页 —— 竖屏（与现状一致：单栏 + 年历/周历 morph 保留不动） */
function homePortrait(dev, layout) {
  const areaH = dev.h - 50 - 30 - 92;
  const cellH = Math.max(34, Math.min(56, Math.floor(areaH / 5)));
  return `
    <div class="pane" style="padding:0 16px">
      ${calPaneHead(layout, { today: true })}
      <div class="pane-scroll" style="padding:0 0 4px;gap:0">
        <div style="flex:none">
          ${monthGrid({ cellH, lunar: !layout.narrow, compact: layout.narrow, sel: 16 })}
        </div>
        <div style="flex:none;margin-top:16px;position:relative">
          <div class="block-divider">9月16日 周三 · 八月初六</div>
          ${dayCard(DIARY[0])}
        </div>
      </div>
    </div>
    ${tabbar(layout, "日记")}`;
}

/* 首页 —— 横屏：左月历（上下滑翻月）＋ 右选中日。
   两栏宽度与高度都取自 `layoutFor()`，与实际实现同一组数：主栏 345（容器 750 × 46%）、
   详情栏 356.5、日历区 330（= 屏高 402 − 顶部 8 − 横屏浮条 64），
   标题槽 34 + 星期栏 26，剩下固定按 **6 行** 分（行高不跟当月是 5 行还是 6 行变）。 */
function homeLandscape(dev, layout) {
  const pagePad = 16;                               /* AdaptiveLayout.pagePadding */
  const calendarW = layout.paneW;                   /* 345 */
  const dayW = layout.detailW;                      /* 356.5 */
  const paneH = dev.h - 8 - 64;                     /* splitPaneHeight：8 + 横屏浮条 64 */
  const titleH = 34;                                /* CalendarLayout.compactMonthTitleH */
  const weekH = 26;                                 /* CalendarLayout.compactWeekdayHeaderH */
  const cellH = Math.max(38, Math.floor((paneH - titleH - weekH) / 6));
  return `<div class="shell-row" style="padding:0 ${pagePad + layout.trailingInset}px 0 ${layout.contentInset + pagePad}px;gap:16.5px;align-items:flex-start">
      <div class="pane" style="width:${calendarW}px;flex:none">
        <div style="height:${titleH}px;display:flex;align-items:center">
          <span style="font-size:24px;font-weight:700">${S.monthTitle}</span>
        </div>
        <div class="pane-scroll" style="padding:0">
          ${monthGrid({ cellH, lunar: true, sel: 16, fill: false })}
        </div>
      </div>
      <div class="pane" style="width:${dayW}px;flex:none">
        <div class="pane-head" style="padding:0 0 8px;min-height:${titleH + 8}px">
          <span style="font-size:var(--t-row);font-weight:600">${S.today}</span>
          <div style="flex:1"></div>
          <span class="pill small">${S.year}年</span>
        </div>
        <div class="pane-scroll" style="padding:0">
          <div class="empty">${ICON.pencil}
            <div>这一天没有留下日记。</div>
            <span class="pill brand" style="margin-top:6px">写日记</span>
          </div>
        </div>
      </div>
    </div>
    ${tabbar(layout, "日记")}`;
}

/* 首页 —— 横屏 · 高度不足：左栏降级为周条 */
function footprintLandscape(dev, layout) {
  const years = [[2024, 4], [2025, 6], [2026, 3]];
  const stats = [["7", "省市"], ["9", "城市"], ["4", "国家"], ["14", "片段"], ["13", "天数"]];
  return `
    <div class="pane" style="padding:0 16px">
      <div class="pane-head" style="padding:2px 0 6px">
        <span class="ph-title">足迹</span>
        <div style="flex:1"></div>
        <span style="font-size:var(--t-caption);color:var(--on-surface-variant)">已标注 14 处 · 未记录 3 篇</span>
      </div>
      <div class="pane-scroll" style="padding:0;gap:10px">
        <div class="chip-row" style="flex:none">
          <span class="chip active">全部</span><span class="chip">2026</span>
          <span class="chip">2025</span><span class="chip">2024</span><span class="chip">自定义</span>
        </div>
        <div class="card" style="flex:none;padding:12px 6px"><div class="stat-row">
          ${stats.map(([v, l]) => `<div class="stat"><b>${v}</b><span>${l}</span></div>`).join("")}
        </div></div>
        <div style="display:flex;gap:12px;flex:none;height:190px">
          <div class="card" style="flex:1;min-width:0;display:flex;flex-direction:column">
            <div style="font-size:var(--t-sub);font-weight:600;margin-bottom:4px">年度记录天数</div>
            <div style="flex:1;display:flex;min-height:0;padding-bottom:18px">${bars(years)}</div>
          </div>
          <div class="card" style="width:280px;flex:none;display:flex;flex-direction:column">
            <div style="font-size:var(--t-sub);font-weight:600;margin-bottom:2px">地点清单</div>
            <div style="flex:1;min-height:0;overflow:hidden">${footprintTree()}</div>
          </div>
        </div>
        <div style="height:64px"></div>
      </div>
    </div>
    ${tabbar(layout, "足迹")}`;
}

/* 搜索 —— 横屏：单栏纵向列表 + 当前关键词栏（与竖屏一致，只是更宽） */
function searchLandscape(dev, layout) {
  const results = [
    { date: "9月16日 周三", time: "07:20", body: DIARY[0].body },
    { date: "9月12日 周六", time: "18:02", body: "傍晚又去湖边走了半圈，雾比早上薄，水面能看见对岸的灯。" },
    { date: "9月8日 周二", time: "06:55", body: "起雾了，能见度不到五十米，骑车的时候只敢慢慢走。" },
    { date: "8月30日 周日", time: "20:11", body: "台风过境前的一天，云压得很低，远处的山被雾裹住了一半。" },
    { date: "8月21日 周五", time: "09:30", body: "山里早上有雾，缆车上去的时候什么都看不见，到了山顶反而放晴。" },
  ];
  return `
    <div class="pane" style="flex:1;min-width:0;padding:0 18px 0 ${layout.gridInset}px">
      <div class="pane-head" style="padding:2px 0 6px">
        <span class="ph-title">搜索</span>
        <div style="flex:1"></div>
        <span class="tag">${ICON.cal}12 条日记</span>
      </div>
      <div class="pane-scroll" style="padding:0;gap:10px">
        <div style="display:flex;gap:10px;flex:none;align-items:center">
          <div class="searchfield" style="flex:1;min-width:0">
            ${ICON.search}<span style="flex:1;color:var(--on-surface)">雾</span>${ICON.xmark}
          </div>
          <span class="chip active">全部时间</span>
          <span class="chip">中国 · 浙江省</span>
        </div>
        <div class="card tight" style="flex:none;display:flex;align-items:center;gap:8px;padding:8px 12px">
          <div class="chip-row" style="flex:1;flex-wrap:nowrap;overflow:hidden;gap:6px">
            <span class="kw">雾</span>
            <span class="kw">湖边</span>
            <span class="chip active">本周</span>
            <span class="chip">中国 · 浙江省</span>
          </div>
          <span style="font-size:var(--t-caption);color:var(--primary);flex:none">清除全部条件</span>
        </div>
        <div style="display:flex;flex-direction:column;gap:10px;flex:none">
          ${results.map((r, i) => `<div class="result" style="${i === 0 ? "box-shadow:0 0 0 2px var(--primary),var(--card-shadow)" : ""}">
            <div style="flex:1;min-width:0">
              <div style="margin-bottom:6px"><span class="tag">${ICON.cal}${r.date}</span></div>
              <div class="snip">${r.body.replace(/雾/g, "<mark>雾</mark>").replace(/湖边/g, "<mark>湖边</mark>").replace(/清晨/g, "<mark>清晨</mark>")}</div>
            </div>
            <div class="time">${r.time}</div>
          </div>`).join("")}
        </div>
        <div style="height:64px"></div>
      </div>
    </div>
    ${tabbar(layout, "搜索")}`;
}

/* 设置 —— 横屏：与竖屏同一条**单列**卡片流（2026-10-01：删掉原来画的两列候选版，
   实现里 SettingsView 就是一个 VStack，不随宽度分列） */
/* 设置 —— 横屏：与竖屏同一条**单列**卡片流（2026-10-01：删掉原来画的两列候选版，
   实现里 SettingsView 就是一个 VStack，不随宽度分列） */
function settingsLandscape(dev, layout) {
  const padX = 16;                                  /* AdaptiveLayout.pagePadding */
  return `
    <div class="pane" style="flex:1;min-width:0;padding:0 ${padX + layout.trailingInset}px 0 ${padX + layout.contentInset}px">
      <div class="pane-head" style="padding:2px 2px 4px"><span class="ph-title">设置</span></div>
      <div class="pane-scroll" style="padding:0">
        <div class="cardgrid" style="grid-template-columns:minmax(0,1fr);align-items:start">
          ${settingCards().join("")}
        </div>
        <div style="height:64px"></div>
      </div>
    </div>
    ${tabbar(layout, "设置")}`;
}

/* 读日记 —— 横屏：限宽阅读栏 + 底部操作。
   正文列与编辑态同为 `contentColumn(660)`（2026-10-01：原来画的 620 是编辑列还是 620
   时代的旧值，实现现在两侧都是 660）。 */
function readLandscape(dev, layout) {
  const padX = 16;                                  /* AdaptiveLayout.pagePadding */
  const colW = Math.min(660, dev.w - layout.contentInset - layout.trailingInset - padX * 2);
  return `
    <div class="pane" style="flex:1;min-width:0;padding:0 ${padX + layout.trailingInset}px 0 ${padX + layout.contentInset}px">
      <div class="pane-head" style="padding:2px 2px 4px 0">
        <span class="icon-btn" style="width:34px;height:34px">${ICON.chevL}</span>
        <div style="flex:1"></div>
        <span class="tag">${ICON.cal}今天</span>
        <span class="icon-btn" style="width:34px;height:34px">${ICON.search}</span>
        <span class="icon-btn" style="width:34px;height:34px">${ICON.pencil}</span>
        <span class="icon-btn" style="width:34px;height:34px">${ICON.share}</span>
      </div>
      <div class="pane-scroll" style="padding:0;align-items:center">
        <div style="width:${colW}px;flex:none">
          <div style="display:flex;align-items:baseline;gap:10px;padding:2px 2px 10px">
            <span style="font-size:var(--t-page);font-weight:650">${S.today}</span>
            <span style="font-size:var(--t-caption);color:var(--on-surface-variant)">${S.lunarToday} · 3 段 · 07:20 – 21:05</span>
          </div>
          ${DIARY.slice(0, 2).map((d) => `<div class="card" style="margin-bottom:10px;padding:12px">
            <div class="card-meta">${ICON.clock}<span style="color:var(--primary);font-weight:600">${d.time}</span>
              ${d.loc ? `${ICON.pin}<span>${esc(d.loc)}</span>` : ""}</div>
            <div style="font-size:17px;line-height:1.68">${esc(d.body)}</div>
          </div>`).join("")}
          <div style="height:64px"></div>
        </div>
      </div>
    </div>
    ${tabbar(layout, "日记")}`;
}

/* 年月切换（竖屏浮层）—— 横屏不提供，这里只画竖屏那张 */
function yearMonthOverlay(dev, layout) {
  const years = [2024, 2025, 2026, 2027, 2028];
  return `
    ${homePortrait(dev, layout)}
    <div style="position:absolute;inset:0;z-index:30;background:rgba(0,0,0,.28);
                display:flex;align-items:center;justify-content:center">
      <div class="card" style="width:300px;padding:16px;box-shadow:0 24px 60px rgba(0,0,0,.45)">
        <div style="text-align:center;font-size:var(--t-sub);color:var(--on-surface-variant);
                    letter-spacing:.06em;text-transform:uppercase;margin-bottom:10px">切换年月</div>
        <div style="display:flex;gap:10px">
          <div class="wheel" style="flex:none;background:color-mix(in srgb,var(--on-surface) 6%,transparent);
                     border-radius:12px;padding:6px 4px">
            ${years.map((y) => `<div class="w-item${y === 2026 ? " active" : " near"}">${y}</div>`).join("")}
          </div>
          <div class="month-picker" style="flex:1">
            ${["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
              .map((m, i) => `<div class="m${i === 8 ? " active" : ""}">${m}</div>`).join("")}
          </div>
        </div>
        <div style="display:flex;gap:8px;margin-top:14px;justify-content:flex-end">
          <span class="pill">取消</span><span class="pill brand">跳转</span>
        </div>
      </div>
    </div>`;
}

/* ------------------------------------------------------------------ 手机画框 */

FRAMES.push(

  {
    id: "ph-home-landscape", kind: "home", dev: "phoneL",
    title: "首页 · 手机横屏（本次重点）",
    tag: "左右分栏",
    note: "横屏 402pt 高塞不下「标题 + 六周格 + 日期行 + 日记卡」，所以拆成左右两栏。<b>左侧 62pt 是安全区</b>（safe.leading，实测横屏 T0 L62 B20 R62）：系统浮条在横屏<b>仍在屏幕底部居中</b>（实测高 64pt，本稿画的就是底部浮条），左侧这条 62pt 与它无关，可用内容宽度 = 874 − 62 − 62 = 750pt，内容左边界 = 62。左栏是<b>连续月历流</b>（<b>相邻月的日期不画、留白</b>；本稿画的是淡色，与实现不同，见文末「待修」）、<b>上下滑翻月</b>；标题区只占一行（月标题），年份入口与「今天」都在右栏标题行 —— 横屏高度紧张，标题每多占 12pt 就会把日期格子挤到最小行高以下。",
    screen: homeLandscape,
    annots: [
      { x: 130, y: 92, t: "左栏是连续月历流；相邻月的日期不画（本稿画成淡色）" },
      { x: 520, y: 92, t: "上下滑翻月" },
      { x: 700, y: 116, t: "右栏标题行：日期 + 年份入口 + 今天" },
      { x: 430, y: 300, t: "两栏：月历 345pt / 右栏 356.5pt（容器宽 750）" },
      { x: 40, y: 330, t: "左侧 62pt 是安全区（系统浮条仍在底部居中）" },
    ],
    spec: [
      ["系统占位", "左 62pt（safe.leading）/ 右 62pt（safe.trailing）；浮条在底部居中 64pt"],
      ["可用内容宽", "750pt"],
      ["左栏宽", "345pt（容器宽 750 的 46%）；右栏 356.5pt"],
      ["标题区", "34pt（只一行：月标题；年份与「今天」在右栏标题行）"],
      ["月格", "345/7 ≈ 49pt 宽 × 行高 45pt（六行固定）"],
      ["翻月", "上下滑；连续月份流（与竖屏同一套），相邻月的日期不画（`MonthBlockCanvas` 只画本月，`CalendarGrids.swift:499`）"],
      ["年份切换", "横屏不提供（点右栏年份胶囊进年历）"],
    ],
  },
  {
    id: "ph-footprint-landscape", kind: "footprint", dev: "phoneL",
    title: "足迹 · 手机横屏",
    tag: "单列 · 图表与清单并排",
    note: "横屏的<b>真实内容宽度是 750pt</b>（874 − 左 62 安全区 − 右 62），达不到足迹的分栏阈值 900，所以不做左右分栏。但 402pt 的高度足够让「年度趋势图」和「地点清单」<b>并排成两块</b>：图表占满剩余宽度、清单宽 = 内容宽 × 40%（夹在 240–320，本机 750 × 0.4 = 300pt），都比各自独占一整屏更省空间。整页仍是一列纵向滚动。",
    screen: footprintLandscape,
    annots: [
      { x: 200, y: 176, t: "筛选 chips 与统计各占一行" },
      { x: 330, y: 300, t: "趋势图与地点清单并排，块高 = max(140, min(190, 屏高 402 − 262)) = 140pt" },
      { x: 700, y: 300, t: "清单宽 = 内容宽 × 40%（夹 240–320，本机 300pt），缩进 18pt/级" },
      { x: 500, y: 424, t: "整页一列纵向滚动（浮条已留 64pt）" },
    ],
    spec: [
      ["内容宽度", "750pt（874 − 左右各 62 安全区）"],
      ["分栏阈值", "900pt → 横屏不达标，单列"],
      ["并排块", "趋势图 flex:1 ｜ 清单 = 内容宽 × 40%（夹 240–320）→ 300pt"],
      ["并排高度", "140pt（= max(140, min(190, 屏高 402 − 262))）"],
      ["滚动", "整页一列纵向滚动"],
    ],
  },
  {
    id: "ph-search-landscape", kind: "search", dev: "phoneL",
    title: "搜索 · 手机横屏",
    tag: "单栏 + 条件栏",
    note: "横屏只把「条件」压成一行（搜索框 + 时间 + 地点），<b>结果保持与竖屏一致的单栏纵向列表</b>——横屏每行更长，摘要能多显示半行，扫读反而更快。搜索框下面是<b>唯一的条件栏</b>：关键词 / 时间 / 地点三类<b>同一条</b>横滑胶囊，每个都能单独点掉（`SearchView.filterSummary`，竖屏与横屏共用，代码注释写明「关键词不再另起一行」）。",
    screen: searchLandscape,
    annots: [
      { x: 96, y: 8, t: "标题 + 结果数" },
      { x: 300, y: 60, t: "搜索框与筛选压成一行" },
      { x: 300, y: 132, t: "条件栏：关键词 / 时间 / 地点三类同栏" },
      { x: 470, y: 230, t: "结果单栏纵向，与竖屏一致" },
    ],
    spec: [
      ["搜索框", "flex:1，minHeight 46pt"],
      ["筛选", "与搜索框同一行，横向滚动"],
      ["条件栏", "关键词 / 时间 / 地点三类同栏（SearchView.filterSummary），逐个可点掉"],
      ["结果", "单栏纵向列表，与竖屏一致"],
      ["底部", "浮条 64pt"],
    ],
  },
  {
    id: "ph-settings-landscape", kind: "settings", dev: "phoneL",
    title: "设置 · 手机横屏",
    tag: "单列卡片",
    note: "设置页<b>竖屏与横屏共用单列卡片</b>（<b>SettingsView</b> 就是一个 VStack(spacing: 12)，不随宽度分列；见 docs/adaptive-layout-plan.md §3.4 —— 设置项之间没有主从关系，不做「左右两页」）。卡片按内容自然高度往下接排，整页纵向滚动。<b>2026-10-01</b>：这张稿原来画的是「两列卡片」候选版，那张形态从来没有实现，已按实现改回单列。",
    screen: settingsLandscape,
    annots: [
      { x: 96, y: 8, t: "页面标题" },
      { x: 470, y: 96, t: "单列卡片，卡间距 12pt" },
      { x: 470, y: 300, t: "行高 56pt，分隔线缩进对齐标题" },
    ],
    spec: [
      ["列数", "单列（竖屏与横屏共用）"],
      ["卡片间距", "12pt"],
      ["行高", "minHeight 56pt"],
      ["分隔线缩进", "62pt（= 12 + 徽章 38 + 间距 12，即 RowDivider.textInset）"],
    ],
  },
  {
    id: "ph-read-landscape", kind: "read", dev: "phoneL",
    title: "日记阅读 · 手机横屏",
    tag: "限宽阅读栏",
    note: "阅读页在横屏仍然是<b>单栏限宽</b>（≤660pt）并居中：横屏的宽度应该换成更好的每行字数，而不是把正文拆成两栏。工具按钮收到顶栏一行，返回键在页面最左（安全区 62pt + 页边距 16pt 之后，x ≈ 78）、操作在右。底部留出浮条/指示条的高度。",
    screen: readLandscape,
    annots: [
      { x: 96, y: 8, t: "顶栏：返回在左，操作在右" },
      { x: 470, y: 96, t: "正文列 ≤660pt 并居中（阅读与编辑同宽）" },
      { x: 470, y: 300, t: "底部留出浮条高度" },
    ],
    spec: [
      ["正文列宽", "≤660pt（阅读与编辑同为 contentColumn(660)）"],
      ["正文字号", "设计 17pt，动态字体解析"],
      ["卡片间距", "10pt"],
      ["顶栏", "返回 + 今天 + 页内搜索 / 编辑 / 分享"],
    ],
  },

);
