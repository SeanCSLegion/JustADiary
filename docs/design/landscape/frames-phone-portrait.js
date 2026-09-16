/* ==========================================================================
   一页时光 · 设计稿 · 手机竖屏（严格照实现复刻）
   这一组不是「重新设计」，而是把项目**当前竖屏的样子**按 1:1 画成设计稿，
   作为横屏改造的对照基准。所有尺寸来自实现本身：

     header            顶部 12pt，左右 16pt，minHeight 52pt
     ‹ 年 capsule       HStack(spacing 6) + padding h14 v? + minHeight 44，玻璃胶囊
     InfoCapsule(今天)  同尺寸玻璃胶囊
     MonthBigTitle     字号 32pt bold，左右各 20pt，高 72pt
     WeekdayHeaderView 高 30pt，字号 min(max(cellW*0.26,11),14)，周末降透明度
     MonthCanvas       行高由可用高度算；行间 1pt 分隔线（outlineVariant 35%）
     DayDraw           日号 20pt、行内最多 20pt×0.5 宽的下划线；农历 11pt（选中/今天同色）
     DayContentView    分隔线 + 日期行（40pt）+ 卡片（padding 12、圆角 20、间距 16）
     TabBarClearance   底部为浮条留 120pt
   ========================================================================== */

/* 年份胶囊（点它进年历） */
function yearCapsule() {
  return `<span class="pill small" style="padding:9px 14px">${ICON.chevL}${S.year}年</span>`;
}
function todayCapsule() {
  return `<span class="pill" style="padding:9px 14px">${S.todayLabel}</span>`;
}
function portraitHeader(showBack) {
  return `<div style="display:flex;align-items:center;gap:10px;padding:12px 16px 0;min-height:52px">
      ${showBack
        ? `<span class="pill small" style="padding:9px 14px">${ICON.chevL}${S.year}年</span>`
        : `<span class="pill small" style="padding:9px 14px">${ICON.chevL}${S.year}年</span>`}
      <div style="flex:1"></div>
      ${todayCapsule()}
    </div>`;
}

/* 竖屏月格：行高按可用高度算，带行间分隔线 */
function portraitMonthGrid(opt) {
  const o = Object.assign({ cellH: 56, lunar: true, sel: 16, rows: 5, from: 0 }, opt);
  const rows = [];
  for (let r = 0; r < o.rows; r++) {
    const i = o.from + r;
    const days = SEPT_WEEKS[i];
    const cells = days.map((d) => {
      const out = (i === 0 && d > 20) || (i === SEPT_WEEKS.length - 1 && d < 7);
      if (out) return `<div class="day" style="height:${o.cellH}px"></div>`;
      const k = ["day"];
      if (d === 16) k.push("sel");
      if (d === 8) k.push("today");
      if (d > 16) k.push("future");
      const lunar = o.lunar ? `<span class="l">${LUNAR[d] || ""}</span>` : "";
      const mark = (d === 8 || d === 16 || d === 23)
        ? `<span class="underline" style="${d === 16 ? "background:#fff" : ""}"></span>` : "";
      return `<div class="${k.join(" ")}" style="height:${o.cellH}px">
        <span class="n">${d}</span>${lunar}${mark}</div>`;
    }).join("");
    rows.push(`<div class="week">${cells}</div>`);
  }
  return `<div class="portrait-month">${rows.join("")}</div>`;
}

function portraitWeekHead() {
  return `<div class="weekhead" style="padding:0;height:30px;display:flex;align-items:center">
    ${S.weekday.map((w) => `<span style="flex:1;text-align:center">${w}</span>`).join("")}
  </div>`;
}

function monthBigTitle() {
  return `<div style="height:72px;display:flex;align-items:center;padding:0 20px">
    <span style="font-size:32px;font-weight:700;letter-spacing:-.02em">${S.monthTitle}</span>
  </div>`;
}

/* 首页 · 竖屏 · 月视图（= 当前实现） */
function ptHomeMonth(dev, layout) {
  const cellH = Math.min(56, Math.floor((dev.h - 52 - 12 - 72 - 30 - 120) / 5));
  return `
    <div class="pane" style="flex:1;min-width:0;padding:0">
    ${portraitHeader(false)}
    <div class="pane-scroll" style="padding:0;gap:0">
      ${monthBigTitle()}
      ${portraitWeekHead()}
      ${portraitMonthGrid({ cellH, lunar: true, rows: 5, sel: 16 })}
      <div style="height:${Math.max(40, dev.h - 52 - 12 - 72 - 30 - cellH * 5 - 120)}px"></div>
      <div style="height:120px"></div>
    </div>
    </div>
    ${tabbar(layout, "日记")}`;
}

/* 首页 · 竖屏 · 周视图（点某天后 morph 到这一屏） */
function ptHomeWeek(dev, layout) {
  const cellH = 68;
  return `
    <div class="pane" style="flex:1;min-width:0;padding:0">
    ${portraitHeader(true)}
    <div class="pane-scroll" style="padding:0;gap:0">
      ${portraitWeekHead()}
      ${portraitMonthGrid({ cellH, lunar: true, rows: 1, from: 2, sel: 16 })}
      <div class="divider" style="margin:0;background:var(--divider)"></div>
      <div style="display:flex;align-items:center;gap:12px;padding:0 20px;height:40px">
        <span style="font-size:var(--t-row);font-weight:600">${S.today}</span>
        <div style="flex:1"></div>
        <span style="font-size:var(--t-caption);color:var(--on-surface-variant)">${S.lunarToday}</span>
      </div>
      <div class="divider" style="margin:0"></div>
      <div style="padding:18px 20px 0">
        ${dayCard(DIARY[0])}
        ${dayCard(DIARY[1])}
        <div style="height:120px"></div>
      </div>
    </div>
    </div>
    ${tabbar(layout, "日记")}`;
}

/* 首页 · 竖屏 · 年历（点年月胶囊后 morph 到这一屏） */
function ptHomeYear(dev, layout) {
  return `
    <div class="pane" style="flex:1;min-width:0;padding:0">
    ${portraitHeader(false)}
    <div class="pane-scroll" style="padding:0;gap:0">
      <div style="height:82px;display:flex;align-items:flex-end;gap:8px;padding:0 20px 10px;margin-top:14px">
        <span style="font-size:32px;font-weight:700;color:var(--primary);letter-spacing:-.02em">${S.year}年</span>
        <div style="flex:1"></div>
        <span style="font-size:var(--t-caption);color:var(--on-surface-variant);opacity:.8">丙午马年</span>
      </div>
      <div class="divider" style="margin:0 20px"></div>
      <div style="padding:14px 16px 0;display:grid;grid-template-columns:repeat(3,1fr);gap:14px 10px">
        ${Array.from({ length: 12 }, (_, i) => miniMonth(i + 1)).join("")}
      </div>
      <div style="height:120px"></div>
    </div>
    </div>
    ${tabbar(layout, "日记")}`;
}

/* 年历里的迷你月。真实实现是 MonthCanvas(cellW=w/7, cellH=h/6, 11pt) */
function miniMonth(m) {
  const first = SEPT_MINI_OFFSET[m] || 0;      /* 该月 1 号前的空格数（周一起始） */
  const days = SEPT_MINI_DAYS[m] || 31;
  const cells = [];
  for (let i = 0; i < first; i++) cells.push(null);
  for (let d = 1; d <= days; d++) cells.push(d);
  const rows = [];
  for (let r = 0; r < 6; r++) {
    const slice = cells.slice(r * 7, r * 7 + 7);
    rows.push(`<div style="display:grid;grid-template-columns:repeat(7,1fr)">${
      Array.from({ length: 7 }, (_, c) => {
        const d = slice[c];
        if (d == null) return "<span></span>";
        const isCur = m === 9;
        const isSel = isCur && d === 16;
        const isToday = isCur && d === 8;
        const after = isCur && d > 16;
        const cls = isSel ? "mnm sel" : isToday ? "mnm today" : after ? "mnm dim" : "mnm";
        return `<span class="${cls}">${d}</span>`;
      }).join("")
    }</div>`);
  }
  return `<div class="mini-month">
      <div class="mini-month-title${m === 9 ? " cur" : ""}">${m}月</div>
      ${rows.join("")}
    </div>`;
}

/* 足迹 · 竖屏（= 当前实现） */
function ptFootprint(dev, layout) {
  const years = [[2024, 4], [2025, 6], [2026, 3]];
  return `
    <div class="pane" style="padding:12px 16px 0">
      <div class="pane-head" style="padding:0 0 10px">
        <span class="ph-title">${S.footprintTitle}</span>
        <div style="flex:1"></div>
        <span style="font-size:var(--t-chip);color:var(--on-surface-variant)">已标注 14 处 · 未记录 3 篇</span>
      </div>
      <div class="pane-scroll" style="padding:0;gap:12px">
        <div class="chip-row" style="flex:none">
          <span class="chip active">全部</span><span class="chip">2026</span>
          <span class="chip">2025</span><span class="chip">2024</span><span class="chip">自定义</span>
        </div>
        <div class="card" style="flex:none;padding:14px 6px"><div class="stat-row">
          ${[["7", "省市"], ["9", "城市"], ["4", "国家"], ["14", "片段"], ["13", "天数"]]
            .map(([v, l]) => `<div class="stat"><b>${v}</b><span>${l}</span></div>`).join("")}
        </div></div>
        <div class="card" style="flex:none;height:150px;display:flex;flex-direction:column">
          <div style="font-size:var(--t-sub);font-weight:600;margin-bottom:4px">年度记录天数</div>
          <div style="flex:1;display:flex;min-height:0;padding-bottom:18px">${bars(years)}</div>
        </div>
        <div class="card" style="flex:none">
          <div style="font-size:var(--t-sub);font-weight:600;margin-bottom:2px">地点清单</div>
          ${footprintTree()}
        </div>
        <div style="height:120px"></div>
      </div>
    </div>
    ${tabbar(layout, "足迹")}`;
}

function footprintTree() {
  const nodes = [
    ["globe", "中国", 9], ["globe", "美国", 2], ["globe", "日本", 2], ["globe", "法国", 1],
  ];
  return `<div class="tree">${nodes.map(([ic, n, c]) => `<div class="row" style="min-height:42px">
    ${ICON[ic]}<span class="nm">${n}</span><span class="ct">${c}</span>
    <span class="chev">${ICON.chevR}</span>
  </div>`).join("")}</div>`;
}

/* 搜索 · 竖屏（= 当前实现） */
function ptSearch(dev, layout) {
  return `
    <div class="pane" style="padding:12px 16px 0">
      <div class="pane-head" style="padding:0 0 10px"><span class="ph-title">${S.searchTitle}</span></div>
      <div class="pane-scroll" style="padding:0;gap:12px">
        <div class="searchfield" style="flex:none">
          ${ICON.search}<span style="flex:1;color:var(--on-surface-variant)">搜索日记内容…</span>
        </div>
        <div class="card tight" style="flex:none">
          <div style="font-size:var(--t-sub);color:var(--on-surface-variant);margin-bottom:8px">时间范围</div>
          <div class="chip-row" style="flex-wrap:wrap">
            <span class="chip active">全部时间</span><span class="chip">本周</span>
            <span class="chip">本月</span><span class="chip">今年</span>
          </div>
          <div style="font-size:var(--t-sub);color:var(--on-surface-variant);margin:14px 0 8px">地点</div>
          <div class="chip-row" style="flex-wrap:wrap">
            <span class="chip active">全部地点</span><span class="chip">选择地点…</span>
          </div>
        </div>
        <div style="flex:1"></div>
        <div class="empty" style="padding-top:80px">
          ${ICON.search.replace('width="24"', 'width="34"')}
          <div style="font-size:var(--t-row);font-weight:600;color:var(--on-surface)">搜索你的日记</div>
          <div style="font-size:var(--t-sub)">输入关键词，或选择时间与地点筛选</div>
        </div>
        <div style="height:120px"></div>
      </div>
    </div>
    ${tabbar(layout, "搜索")}`;
}

/* 设置 · 竖屏（= 当前实现：卡片 + 分组标题 + 图标徽章 + 尾值/开关） */
function ptSettings(dev, layout) {
  const rows = settingsPortraitCards();
  return `
    <div class="pane" style="padding:12px 16px 0">
      <div class="pane-head" style="padding:0 0 10px"><span class="ph-title">${S.settingsTitle}</span></div>
      <div class="pane-scroll" style="padding:0;gap:12px">
        ${rows.join("")}
        <div style="height:120px"></div>
      </div>
    </div>
    ${tabbar(layout, "设置")}`;
}

function settingsPortraitCards() {
  const R = (o) => `<div class="srow" style="min-height:72px">
      <span class="badge">${ICON[o.icon]}</span>
      <span class="txt"><b>${o.title}</b>${o.sub ? `<i>${o.sub}</i>` : ""}</span>
      ${o.toggle !== undefined
        ? `<span class="toggle${o.toggle ? "" : " off"}"></span>`
        : `<span class="val">${o.value || ""}</span><span class="chev">${ICON.chevR}</span>`}
    </div>`;
  return [
    `<div class="card" style="padding:0">
      <div class="sect">通用</div>
      ${R({ icon: "globe", title: "语言", sub: "应用内显示语言", value: "跟随系统" })}
      ${R({ icon: "palette", title: "主题", sub: "切换浅色、深色或跟随系统", value: "跟随系统" })}
    </div>`,
    `<div class="card" style="padding:0">
      <div class="sect">日记规则</div>
      ${R({ icon: "sun", title: "新一天的开始时间", sub: "在此时间之前写的内容，归入前一天", value: "凌晨 4:00" })}
      ${R({ icon: "cal", title: "一周从哪一天开始", sub: "选择日历从周一开始还是周日开始", value: "周一" })}
      ${R({ icon: "clock", title: "自动插入时间", sub: "打开编辑器时自动记录开始时间", toggle: true })}
      ${R({ icon: "pin", title: "自动插入地点", sub: "需要位置信息权限", toggle: true })}
      ${R({ icon: "pin", title: "位置权限", sub: "地点仅保存在本机，不会上传", value: "精确" })}
      ${R({ icon: "pencil", title: "允许修改 / 删除历史日记", sub: "仅可修改或删除已有编辑块，历史日期不可新增内容", toggle: false })}
    </div>`,
    `<div class="card" style="padding:0">
      <div class="sect">提醒</div>
      ${R({ icon: "bell", title: "写日记提醒", sub: "当天未写日记时提醒我", toggle: true })}
      ${R({ icon: "clock", title: "提醒时间", sub: "每天提醒一次", value: "21:00" })}
    </div>`,
    `<div class="card" style="padding:0">
      <div class="sect">数据</div>
      ${R({ icon: "up", title: "导出全部日记", sub: "生成 .jdiary 备份包", value: "" })}
      ${R({ icon: "down", title: "导入备份", sub: "从其他设备恢复日记", value: "" })}
    </div>`,
    `<div class="card" style="padding:0">
      <div class="sect">关于</div>
      ${R({ icon: "info", title: "版本", value: "1.0 (1)" })}
    </div>`,
  ];
}

/* ------------------------------------------------------------------ 竖屏画框 */

FRAMES.push(
  {
    id: "ph-home-portrait", kind: "home", dev: "phoneP",
    title: "首页 · 手机竖屏 · 月视图（复刻实现）",
    tag: "当前实现",
    note: "这一张是项目<b>现在竖屏的真实样子</b>，1:1 复刻，用作横屏改造的对照基准。顶部左侧是「‹ 2026年」玻璃胶囊（点它进年历），右侧是「今天」胶囊；下面是 32pt 的「九月」大标题、30pt 的星期栏、六行月格。日期下有下划线表示有日记；今天用圆环、选中日用实心圆；未来的日期整体降到 35% 不透明度。竖屏这部分<b>不做任何改动</b>。",
    screen: ptHomeMonth,
    annots: [
      { x: 60, y: 74, t: "‹ 2026年 胶囊：点开进年历（morph）" },
      { x: 300, y: 74, t: "今天：回到今日，位置固定" },
      { x: 60, y: 152, t: "«九月» 32pt bold，左右各 20pt" },
      { x: 60, y: 462, t: "今天＝圆环，选中日＝实心圆，有日记＝下划线" },
      { x: 200, y: 700, t: "未来的日期降到 35% 不透明度" },
      { x: 412, y: 316, t: "有日记的日期：日号下一条 20pt 宽、2pt 高的线" },
    ],
    spec: [
      ["顶部边距", "12pt，左右 16pt，minHeight 52pt"],
      ["年月胶囊", "玻璃胶囊，minHeight 44pt"],
      ["月标题", "32pt bold，左右 20pt，高 72pt"],
      ["星期栏", "高 30pt，字号随格宽 11–14pt"],
      ["月格行高", "按可用高度算（本稿 56pt）"],
      ["行分隔线", "1pt，outlineVariant 35%"],
      ["日号 / 农历", "20pt / 11pt"],
      ["选中圆", "直径 = min(格宽−2, 内容高+10, 格高−2)"],
      ["底部预留", "120pt（TabBarClearance）"],
    ],
  },
  {
    id: "ph-home-year", kind: "home", dev: "phoneP",
    title: "首页 · 手机竖屏 · 年历（morph 目标）",
    tag: "当前实现",
    note: "点「‹ 2026年」之后整屏缩放 morph 到这一屏：左上 32pt 的「2026年」（品牌色）+ 右侧当年生肖，下面一条分隔线，再下面 3×4 的迷你月。迷你月里有日记的日期用下划线，当前月标题是品牌色，选中日在当前月里是实心小圆。再点某个月会缩放回月视图 —— 这套 morph 保留不动。",
    screen: ptHomeYear,
    annots: [
      { x: 60, y: 150, t: "年份 32pt bold，品牌色；右侧生肖" },
      { x: 60, y: 236, t: "迷你月标题：当前月用品牌色加粗" },
      { x: 280, y: 420, t: "选中日在当前月里是实心小圆" },
      { x: 280, y: 560, t: "点某个月 → 缩放回月视图（morph）" },
    ],
    spec: [
      ["年标题", "32pt bold，高 62pt"],
      ["生肖", "按年份推算，caption 字号"],
      ["迷你月网格", "3 列 × 4 行，间距 10pt"],
      ["迷你月字号", "10pt（cellW = 卡宽/7）"],
      ["有日记标记", "日号下 2pt 下划线"],
      ["交互", "点月份 → 缩放回该月"],
    ],
  },
  {
    id: "ph-home-week", kind: "home", dev: "phoneP",
    title: "首页 · 手机竖屏 · 周视图（morph 目标）",
    tag: "当前实现",
    note: "点某一天之后 morph 到这一屏：大标题滑出、星期栏升到顶部、被选中的那一行展开到原来整屏的位置，其余行淡出；下面是日期行（日期 + 农历）和当天日记卡。这是竖屏阅读日记的主路径，保留不动。",
    screen: ptHomeWeek,
    annots: [
      { x: 60, y: 98, t: "被选中的那一周升到顶部并展开" },
      { x: 60, y: 208, t: "日期行：日期 + 农历（40pt）" },
      { x: 60, y: 300, t: "日记卡：圆角 20、内边距 12、间距 16" },
    ],
    spec: [
      ["周条高度", "68pt"],
      ["日期行", "40pt，左右 20pt"],
      ["卡片", "padding 12，圆角 20，间距 16"],
      ["时间 / 地点", "caption 13pt，品牌色时间"],
      ["底部预留", "TabBarClearance 120pt"],
    ],
  },
  {
    id: "ph-footprint-portrait", kind: "footprint", dev: "phoneP",
    title: "足迹 · 手机竖屏（复刻实现）",
    tag: "当前实现",
    note: "顶部是「足迹」大标题 + 右侧「已标注 14 处 · 未记录 3 篇」；下面一行年份筛选胶囊（横向滚动）；再下面是统计卡（省市 / 城市 / 国家 / 片段 / 天数）、年度记录天数柱状图和地点清单卡。三层结构不变，横屏版只是把它压成一列可滚动的排法。",
    screen: ptFootprint,
    annots: [
      { x: 60, y: 120, t: "标题 + 右侧统计摘要（已标注 / 未记录）" },
      { x: 200, y: 176, t: "年份筛选胶囊（横向滚动）" },
      { x: 340, y: 218, t: "统计卡：5 项等分" },
      { x: 340, y: 340, t: "年度记录天数：柱状图" },
      { x: 340, y: 470, t: "地点清单：国家 → 省市 → 城市" },
    ],
    spec: [
      ["统计行", "5 项等分，字号 18pt 上限"],
      ["图表高度", "150pt"],
      ["清单缩进", "18pt / 级，最多 3 级"],
      ["卡片", "圆角 20，间距 12"],
    ],
  },
  {
    id: "ph-search-portrait", kind: "search", dev: "phoneP",
    title: "搜索 · 手机竖屏（复刻实现）",
    tag: "当前实现",
    note: "顶部「搜索」标题，下面是玻璃搜索框，再下面是筛选卡（「时间范围」与「地点」两组胶囊），没有条件时居中显示空状态「搜索你的日记」。横屏版把筛选压成一行、结果横向铺开，这一张是对照。",
    screen: ptSearch,
    annots: [
      { x: 60, y: 120, t: "页面标题" },
      { x: 300, y: 190, t: "玻璃搜索框，minHeight 46" },
      { x: 300, y: 268, t: "筛选卡：时间范围 + 地点" },
      { x: 300, y: 760, t: "空状态：图标 + 标题 + 说明" },
    ],
    spec: [
      ["搜索框", "玻璃胶囊，minHeight 46pt"],
      ["筛选", "两组胶囊，横向滚动"],
      ["空状态", "垂直居中偏上"],
      ["滚动收起", "contentOffset > 24 淡出顶部（已有）"],
    ],
  },
  {
    id: "ph-settings-portrait", kind: "settings", dev: "phoneP",
    title: "设置 · 手机竖屏（复刻实现）",
    tag: "当前实现",
    note: "设置页是「卡片 + 卡内分组标题」：通用、日记规则、提醒、数据、关于五张卡，每张卡里第一行是分组标题，下面是行。每行的结构是图标徽章（38pt 圆角方块）+ 标题 + 副标题 + 尾值或开关；行分隔线从标题文字处开始，不缩进到图标下面。竖屏保持单列。",
    screen: ptSettings,
    annots: [
      { x: 60, y: 100, t: "卡内分组标题（通用 / 日记规则 / …）" },
      { x: 60, y: 168, t: "图标徽章 38pt + 标题 + 副标题" },
      { x: 60, y: 292, t: "尾值 / 开关；分隔线从标题处起" },
      { x: 300, y: 500, t: "开关：品牌色，关闭时灰" },
    ],
    spec: [
      ["卡片列数", "1"],
      ["卡片间距", "12pt"],
      ["行高", "≥56pt（本稿 72pt，含两行副标题）"],
      ["图标徽章", "38pt 方形，圆角 12"],
      ["分隔线缩进", "50pt（对齐标题文字）"],
      ["尾值 / 开关", "尾值 15pt；开关品牌色"],
    ],
  }
);
