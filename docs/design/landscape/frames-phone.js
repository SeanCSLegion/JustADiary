/* ==========================================================================
   一页时光 · 设计稿 · 手机端（iPhone 竖屏 / 横屏）
   本文件只描述手机版面。iPad / Mac 的三栏版面在 frames-wide.js。

   横屏的三条硬事实（来自真机探针，不是猜测）：
   1. 系统在横屏把底部浮条换成<b>左侧竖排胶囊</b>：x 12–76、高约 250pt、纵向居中。
      app 无法移动它，只能避让 —— 所以横屏的内容左边界从 88pt 开始。
   2. 灵动岛在横屏位于左上角边缘，约 135 × 44pt，其纵向范围约到 y=180。
      左上角 150 × 180 这个区域是系统硬件区，任何内容都不能放。
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

/* 首页 —— 横屏：左月历（上下滑翻月）＋ 右选中日 */
function homeLandscape(dev, layout) {
  const inset = layout.contentInset;               /* 62：左侧系统占位 */
  const pagePad = 16;
  const paneW = dev.w - inset;
  const shapeW = paneW - pagePad * 2;
  const calendarW = Math.min(shapeW - 280, Math.min(420, Math.max(360, Math.round(shapeW * 0.52))));
  const dayW = shapeW - calendarW - pagePad * 2;
  const navH = 22;                                  /* home indicator 留白 */
  const areaH = dev.h - 50 - navH;
  const titleH = 32;                                /* 横屏标题只占一行 */
  const weekH = 26;
  const weeks = 5;
  const cellH = Math.max(44, Math.floor((areaH - titleH - weekH) / weeks));
  return `<div class="shell-row" style="padding:0 ${pagePad}px 0 ${inset + pagePad}px;gap:${pagePad * 2}px;align-items:flex-start">
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
function homeLandscapeWeek(dev, layout) {
  const inset = layout.contentInset;
  const pagePad = 16;
  const paneW = dev.w - inset;
  const shapeW = paneW - pagePad * 2;
  const calendarW = Math.min(shapeW - 280, Math.min(420, Math.max(360, Math.round(shapeW * 0.52))));
  const dayW = shapeW - calendarW - pagePad * 2;
  return `<div class="shell-row" style="padding:0 ${pagePad}px 0 ${inset + pagePad}px;gap:${pagePad * 2}px;align-items:flex-start">
      <div class="pane" style="width:${calendarW}px;flex:none">
        <div style="height:32px;display:flex;align-items:center">
          <span style="font-size:24px;font-weight:700">${S.monthTitle}</span>
        </div>
        <div class="pane-scroll" style="padding:0">
          <div style="flex:none">
            ${monthGrid({ cellH: 56, lunar: true, rowOnly: true, row: 2, sel: 16 })}
          </div>
          <div style="display:flex;justify-content:space-between;align-items:center;margin-top:12px;
                      font-size:var(--t-caption);color:var(--on-surface-variant)">
            <span class="pill small">${ICON.chevL}上周</span>
            <span>9月14日 – 9月20日</span>
            <span class="pill small">下周${ICON.chevR}</span>
          </div>
        </div>
      </div>
      <div class="pane" style="width:${dayW}px;flex:none">
        <div class="pane-head" style="padding:0 0 8px;min-height:40px">
          <span style="font-size:var(--t-row);font-weight:600">${S.today}</span>
          <div style="flex:1"></div>
          <span class="pill small">${S.year}年</span>
        </div>
        <div class="pane-scroll" style="padding:0">
          ${dayCard(DIARY[0])}
        </div>
      </div>
    </div>
    ${tabbar(layout, "日记")}`;
}

/* 足迹 —— 横屏：真实内容宽度 750pt < 900 的分栏阈值，所以是单列纵向滚动 */
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
          <span style="font-size:var(--t-caption);color:var(--on-surface-variant);flex:none">关键词</span>
          <div class="chip-row" style="flex:1;flex-wrap:wrap;gap:6px">
            <span class="kw">雾</span>
            <span class="kw">湖边</span>
            <span class="kw">清晨</span>
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

/* 设置 —— 横屏：两列卡片 */
function settingsLandscape(dev, layout) {
  return `
    <div class="pane" style="${panePad(layout, 16, 18)}">
      <div class="pane-head" style="padding:2px 2px 4px"><span class="ph-title">设置</span></div>
      <div class="pane-scroll" style="padding:0">
        <div class="cardgrid" style="grid-template-columns:repeat(2,minmax(0,1fr));align-items:start">
          ${settingCards().join("")}
        </div>
        <div style="height:64px"></div>
      </div>
    </div>
    ${tabbar(layout, "设置")}`;
}

/* 读日记 —— 横屏：限宽阅读栏 + 底部操作 */
function readLandscape(dev, layout) {
  const colW = Math.min(620, dev.w - 140);
  return `
    <div class="pane" style="${panePad(layout, 16, 18)}">
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
    note: "横屏 402pt 高塞不下「标题 + 六周格 + 日期行 + 日记卡」，所以拆成左右两栏。<b>左侧 62pt 让给系统</b>：系统导航在横屏变成贴左边缘的竖排胶囊，灵动岛也在同侧（实测 safe.leading = 62），可用内容宽度 = 874 − 62 − 62 = 750pt。左栏只显示<b>当前月</b>、<b>上下滑翻月</b>；标题区只占一行（月标题），年份入口与「今天」都在右栏标题行 —— 横屏高度紧张，标题每多占 12pt 就会把日期格子挤到最小行高以下，整块降级成周条。",
    screen: homeLandscape,
    annots: [
      { x: 130, y: 92, t: "左栏只画当前月（不显示相邻月日期）" },
      { x: 520, y: 92, t: "上下滑翻月" },
      { x: 700, y: 116, t: "右栏标题行：日期 + 年份入口 + 今天" },
      { x: 430, y: 300, t: "两栏对半：月历约 390pt / 右栏约 330pt" },
      { x: 40, y: 330, t: "系统导航在横屏是左侧竖排胶囊（占 62pt）" },
    ],
    spec: [
      ["系统占位", "左 62pt（safe.leading）/ 右 62pt"],
      ["可用内容宽", "750pt"],
      ["左栏宽", "390pt（约 52%）"],
      ["标题区", "32pt（只一行：月标题；年份在右栏标题行）"],
      ["月格", "390/7 = 56 × 条高（≥44pt 才不降级）"],
      ["翻月", "上下滑；只画本月"],
      ["年份切换", "横屏不提供（点右栏年份胶囊进年历）"],
    ],
  },
  {
    id: "ph-home-landscape-week", kind: "home", dev: "phoneL",
    title: "首页 · 手机横屏 · 高度不足时的降级",
    tag: "周条 + 内容",
    note: "当可用高度放不下六周格（分屏、键盘弹起、Duo 折一半），左栏自动从「月」降级为「周条」：一行 7 天、横向翻周，右栏仍是选中日。这样内容永远不会被压扁，日期也永远可点。降级只影响密度，不改变左右分栏结构。",
    screen: homeLandscapeWeek,
    annots: [
      { x: 96, y: 96, t: "降级为周条：一行 7 天" },
      { x: 96, y: 176, t: "上周 / 下周横向翻，纵向留给内容" },
      { x: 470, y: 96, t: "右栏高度不变，卡片不被压缩" },
    ],
    spec: [
      ["触发条件", "可用高度 < 标题 + 六周格（约 < 6×52）"],
      ["周条高度", "52pt"],
      ["翻页", "横向左右滑"],
      ["左栏其余", "补「本月还有」摘要，避免留白"],
    ],
  },
  {
    id: "ph-footprint-landscape", kind: "footprint", dev: "phoneL",
    title: "足迹 · 手机横屏",
    tag: "单列 · 图表与清单并排",
    note: "横屏的<b>真实内容宽度是 750pt</b>（874 − 左 62 系统浮条 − 右 62），达不到足迹的分栏阈值 900，所以不做左右分栏。但 402pt 的高度足够让「年度趋势图」和「地点清单」<b>并排成两块</b>：图表占满剩余宽度、清单固定 300pt，都比各自独占一整屏更省空间。整页仍是一列纵向滚动。",
    screen: footprintLandscape,
    annots: [
      { x: 200, y: 176, t: "筛选 chips 与统计各占一行" },
      { x: 330, y: 300, t: "趋势图与地点清单并排，高度同为 190pt" },
      { x: 700, y: 300, t: "清单固定 300pt 宽，缩进 18pt/级" },
      { x: 500, y: 424, t: "整页一列纵向滚动（浮条已留 64pt）" },
    ],
    spec: [
      ["内容宽度", "750pt（874 − 左右各 62 系统占位）"],
      ["分栏阈值", "900pt → 横屏不达标，单列"],
      ["并排块", "趋势图 flex:1 ｜ 清单 300pt"],
      ["并排高度", "190pt"],
      ["滚动", "整页一列纵向滚动"],
    ],
  },
  {
    id: "ph-search-landscape", kind: "search", dev: "phoneL",
    title: "搜索 · 手机横屏",
    tag: "单栏 + 关键词栏",
    note: "横屏只把「条件」压成一行（搜索框 + 时间 + 地点），<b>结果保持与竖屏一致的单栏纵向列表</b>——横屏每行更长，摘要能多显示半行，扫读反而更快。搜索框下面新增<b>当前关键词栏</b>：每个生效中的关键词是一个可单独点掉的胶囊，多关键词时能一眼看清「现在到底在搜什么」，右侧还有「清除全部条件」。",
    screen: searchLandscape,
    annots: [
      { x: 96, y: 8, t: "标题 + 结果数" },
      { x: 300, y: 60, t: "搜索框与筛选压成一行" },
      { x: 300, y: 132, t: "当前关键词栏：多个关键词各自成胶囊" },
      { x: 470, y: 230, t: "结果单栏纵向，与竖屏一致" },
    ],
    spec: [
      ["搜索框", "flex:1，minHeight 46pt"],
      ["筛选", "与搜索框同一行，横向滚动"],
      ["关键词栏", "当前生效的关键词逐个成胶囊，可单独点掉"],
      ["结果", "单栏纵向列表，与竖屏一致"],
      ["底部", "浮条 64pt"],
    ],
  },
  {
    id: "ph-settings-landscape", kind: "settings", dev: "phoneL",
    title: "设置 · 手机横屏（两列卡片）",
    tag: "2 列 · 不等高",
    note: "横屏宽度够放两列设置卡片，一屏能看更多。<b>卡片按内容自然高度，不拉齐</b>——「通用」只有两行就矮一点，「日记规则」六行就高一点，右列卡片各自接排，下方留白没关系。<b>卡片各自对齐列顶，行不跨卡对齐</b>，这也是实现的自然结果。",
    screen: settingsLandscape,
    annots: [
      { x: 96, y: 8, t: "页面标题" },
      { x: 470, y: 96, t: "两列卡片，列间距 12pt" },
      { x: 470, y: 300, t: "行高 56pt，分隔线缩进对齐标题" },
    ],
    spec: [
      ["列数", "宽度 ≥680pt → 2 列"],
      ["卡片间距", "12pt"],
      ["行高", "minHeight 56pt"],
      ["分隔线缩进", "50pt（对齐标题文字）"],
    ],
  },
  {
    id: "ph-read-landscape", kind: "read", dev: "phoneL",
    title: "日记阅读 · 手机横屏",
    tag: "限宽阅读栏",
    note: "阅读页在横屏仍然是<b>单栏限宽</b>（620pt）并居中：横屏的宽度应该换成更好的每行字数，而不是把正文拆成两栏。工具按钮收到顶栏一行，返回键在最左（在 92pt 系统区之后）、操作在右。底部留出浮条/指示条的高度。",
    screen: readLandscape,
    annots: [
      { x: 96, y: 8, t: "顶栏：返回在左，操作在右" },
      { x: 470, y: 96, t: "正文列 ≤620pt 并居中" },
      { x: 470, y: 300, t: "底部留出浮条高度" },
    ],
    spec: [
      ["正文列宽", "≤620pt"],
      ["正文字号", "设计 17pt，动态字体解析"],
      ["卡片间距", "10pt"],
      ["顶栏", "返回 + 今天 + 页内搜索 / 编辑 / 分享"],
    ],
  },

);
