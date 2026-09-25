/* ==========================================================================
   一页时光 · 设计稿引擎（共享）
   这里放「跟设备无关」的部分：设计令牌的用法、图标、文案数据、日历/卡片/图表的
   绘制函数、版面判定规则、渲染入口。设备尺寸在 devices.js，各屏版面在
   frames-phone.js / frames-wide.js。
   ========================================================================== */

/* ------------------------------------------------------------------ 画框注册表 */

/* 各设备/版面的画框由 frames-phone.js / frames-wide.js 注册进来。
   DEVICES 在 devices.js 里（页面先加载 engine，再加载 devices + frames）。 */
const FRAMES = [];

/* ------------------------------------------------------------------ 图标 *//* ------------------------------------------------------------------ 图标 */

const ICON = {
  home:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10.2 12 3l9 7.2"/><path d="M5.5 9.5V20h13V9.5"/></svg>',
  walk:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="13" cy="4.2" r="1.9"/><path d="M12 8.5 9.5 14l2.6 1.6.9 5.4M12 8.5l3 2.2 2.6-1M9.5 14 6 16.2"/></svg>',
  search:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/></svg>',
  gear:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M12 2.8v2.4M12 18.8v2.4M4.5 7.5l2 1.2M17.5 15.3l2 1.2M4.5 16.5l2-1.2M17.5 8.7l2-1.2"/></svg>',
  clock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="8.5"/><path d="M12 7v5.4l3.4 2"/></svg>',
  pin:   '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2.6a6.6 6.6 0 0 0-6.6 6.6c0 4.6 6.6 12.2 6.6 12.2s6.6-7.6 6.6-12.2A6.6 6.6 0 0 0 12 2.6Zm0 9.1a2.6 2.6 0 1 1 0-5.2 2.6 2.6 0 0 1 0 5.2Z"/></svg>',
  cal:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="3.4" y="5" width="17.2" height="15.6" rx="3"/><path d="M3.4 9.6h17.2M8 3.4v3.2M16 3.4v3.2"/></svg>',
  chevL: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 5 8 12l6.5 7"/></svg>',
  chevR: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 5 16 12l-6.5 7"/></svg>',
  chevD: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 9.5 12 16l7-6.5"/></svg>',
  pencil:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20h4l10-10-4-4L4 16v4Z"/><path d="M14 6l4 4"/></svg>',
  share: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3.5v11"/><path d="M8.4 7 12 3.4 15.6 7"/><path d="M5 13v6.5h14V13"/></svg>',
  photo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="14" rx="3"/><circle cx="8.6" cy="10" r="1.6"/><path d="M4 17l5-4.4 4 3.4 2.6-2.2L20 17"/></svg>',
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5 10 17l9-10"/></svg>',
  undo:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9h10a5 5 0 0 1 0 10H8"/><path d="M7.5 5.5 4 9l3.5 3.5"/></svg>',
  globe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="8.6"/><path d="M3.6 12h16.8M12 3.4c4.4 5 4.4 12.2 0 17.2M12 3.4c-4.4 5-4.4 12.2 0 17.2"/></svg>',
  palette:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M12 3.4a8.6 8.6 0 0 0 0 17.2c1.3 0 2-.9 2-1.8s-.7-1.7-.7-2.6c0-1 .8-1.7 1.9-1.7h1.6a3.8 3.8 0 0 0 3.8-3.8c0-4-3.9-7.3-8.6-7.3Z"/><circle cx="8.6" cy="10" r="1.1" fill="currentColor"/><circle cx="12" cy="7.6" r="1.1" fill="currentColor"/><circle cx="15.6" cy="9.4" r="1.1" fill="currentColor"/></svg>',
  sun:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M3 17h18M6.5 17a5.5 5.5 0 0 1 11 0"/><path d="M12 4v3M4.6 7.6l2 2M19.4 7.6l-2 2"/></svg>',
  bell:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2H4.5l1.5-2Z"/><path d="M10 20.5h4"/></svg>',
  up:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20V4.6"/><path d="M6.5 10 12 4.5 17.5 10"/><path d="M4.5 20h15"/></svg>',
  down:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v15.4"/><path d="M6.5 14 12 19.5 17.5 14"/><path d="M4.5 4h15"/></svg>',
  info:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><circle cx="12" cy="12" r="8.6"/><path d="M12 11v5.4M12 7.9v.2"/></svg>',
  xmark: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  moon:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M20 14.4A8.6 8.6 0 0 1 9.6 4a8.6 8.6 0 1 0 10.4 10.4Z"/></svg>',
  textB: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7 5h10v2.6h-3.5V19h-3V7.6H7Z"/></svg>',
  align:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M4 6.5h16M7 12h10M4 17.5h16"/></svg>',
  list:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M9 6.5h11M9 12h11M9 17.5h11M4.5 6.5h.01M4.5 12h.01M4.5 17.5h.01"/></svg>',
  todo:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="3.4" y="4.6" width="16.8" height="15" rx="4"/><path d="M7.6 12.2l2.8 2.8 5.6-6"/></svg>',
  quote: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M9.4 6.6c-3 1.5-4.6 3.9-4.6 7v3.8h4.8v-5H7.2c.1-1.5.9-2.6 2.4-3.4l-.2-2.4Zm9 0c-3 1.5-4.6 3.9-4.6 7v3.8h4.8v-5h-2.4c.1-1.5.9-2.6 2.4-3.4l-.2-2.4Z"/></svg>',
  map:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M3.4 6.4 9 4.4l6 2 5.6-2v13.2L15 19.6l-6-2-5.6 2Z"/><path d="M9 4.4v13.2M15 6.4v13.2"/></svg>',
  doc:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M6 3.4h7.5L19 8.9v11.7H6Z"/><path d="M13.2 3.6v5.5h5.4"/></svg>',
};

/* ------------------------------------------------------------------ 文案数据 */

const S = {
  monthTitle: "九月",
  year: "2026",
  ym: "2026年9月",
  today: "9月16日 周三",
  lunarToday: "八月初六",
  weekday: ["一", "二", "三", "四", "五", "六", "日"],
};

/* 2026-09 的真实排布：8/31 起 5 周（周一起始） */
const SEPT_WEEKS = [
  [31, 1, 2, 3, 4, 5, 6],
  [7, 8, 9, 10, 11, 12, 13],
  [14, 15, 16, 17, 18, 19, 20],
  [21, 22, 23, 24, 25, 26, 27],
  [28, 29, 30, 1, 2, 3, 4],
];
const LUNAR = {
  31: "十九", 1: "二十", 2: "廿一", 3: "廿二", 4: "廿三", 5: "廿四", 6: "廿五",
  7: "廿六", 8: "廿七", 9: "廿八", 10: "廿九", 11: "八月", 12: "初二", 13: "初三",
  14: "初四", 15: "初五", 16: "初六", 17: "初七", 18: "初八", 19: "初九", 20: "初十",
  21: "十一", 22: "十二", 23: "十三", 24: "十四", 25: "十五", 26: "十六", 27: "十七",
  28: "十八", 29: "十九", 30: "二十",
};

const DIARY = [
  {
    time: "07:20", loc: "浙江省杭州市西湖区 · 北山街",
    title: "清晨的湖边",
    body: "六点半就醒了，天还没大亮。出门的时候湖面上有一层很薄的雾，像谁把水汽摊平了铺在上面。沿着北山街一直走，路灯是熄灭的，只有几辆早班的公交慢慢过去。",
    quote: "雾散得比想象中快，七点之后就只剩水面上一点灰白。",
  },
  {
    time: "12:40", loc: "浙江省杭州市西湖区 · 孤山路",
    title: "中午的一顿饭",
    body: "在一家很小的面馆吃了片儿川，老板说今天的面是早上新压的。窗外有人在拍荷花的残叶，我也跟着看了一会儿。",
  },
  {
    time: "21:05", loc: "",
    title: "写在睡前",
    body: "把今天的照片都导进去了。有一张是雾里的断桥，曝光有点过，但那种亮法反而更像当时的记忆。",
  },
];

const FOOT_NODES = [
  { d: 0, i: "globe", n: "中国", c: 42, open: true },
  { d: 1, i: "map", n: "浙江省", c: 31, open: true },
  { d: 2, i: "pin", n: "杭州市", c: 24 },
  { d: 2, i: "pin", n: "湖州市", c: 5 },
  { d: 2, i: "pin", n: "宁波市", c: 2 },
  { d: 1, i: "map", n: "江苏省", c: 11, open: false },
  { d: 0, i: "globe", n: "日本", c: 9, open: false },
  { d: 0, i: "globe", n: "法国", c: 6, open: false },
];

/* ------------------------------------------------------------------ 渲染工具 */

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;");

function bgLayer() {
  return `<div class="bg-layer"><span class="blob b-a"></span><span class="blob b-b"></span><span class="blob b-c"></span></div>`;
}

function island(dev) {
  if (dev.type !== "phone") return "";
  return `<div class="island"></div>`;
}

function lights(dev) {
  if (dev.type !== "mac") return "";
  return `<div class="lights"><i></i><i></i><i></i></div>`;
}

function tabbar(layout, current) {
  const tabs = [
    ["日记", ICON.home], ["足迹", ICON.walk], ["搜索", ICON.search], ["设置", ICON.gear],
  ];
  const items = tabs.map(([label, icon]) =>
    `<span class="tab${label === current ? " active" : ""}">${icon}${label}</span>`).join("");

  if (!layout.tabbar) return "";

  const pos = layout.tabbarStyle || (layout.tabbarPos === "top" ? "top" : "bottom");
  const left = layout.tabbarOffset;
  const style = left !== undefined ? `style="left:${left}px;transform:none"` : "";
  return `<div class="floating-tabs ${pos}" ${style}>${items}</div>`;
}

function sidebar(layout, current) {
  if (!layout.sidebar) return "";
  const items = [
    ["日记", ICON.home, "日记"], ["足迹", ICON.walk, "足迹"],
    ["搜索", ICON.search, "搜索"], ["设置", ICON.gear, "设置"],
  ].map(([label, icon, key]) =>
    `<div class="item${key === current ? " active" : ""}">${icon}${label}</div>`).join("");
  return `<div class="sidebar">
    <div class="side-title">一页时光</div>
    ${items}
    <div class="spacer"></div>
    <div class="side-foot">侧边栏是系统在窗口足够宽时<br>自动切换的导航形态</div>
  </div>`;
}

/* 月视图。opt: {cellH, lunar, rowOnly, sel, compact} */
function monthGrid(opt) {
  const o = Object.assign({ cellH: 60, lunar: true, rowOnly: false, sel: 16, row: 2 }, opt);
  /* 周条不是「只有一周的月历」，而是「只显示某一行」：上下的周仍要参与
     判断哪些日期属于本月（首行/末行的灰日期就是这么来的）。 */
  const weeks = o.rowOnly ? [SEPT_WEEKS[o.row]] : SEPT_WEEKS;
  const rowIndex = o.rowOnly ? o.row : -1;
  const cls = ["month-grid", o.rowOnly ? "row-only" : "", o.compact ? "compact" : "",
               o.fill ? "fill" : ""].join(" ");
  const rows = weeks.map((days, wi) => {
    const cells = days.map((d, di) => {
      const idx = rowIndex >= 0 ? rowIndex : wi;
      const out = (idx === 0 && d > 20) || (idx === SEPT_WEEKS.length - 1 && d < 7);
      const isToday = !out && d === 16;
      const isSel = !out && d === o.sel;
      const k = ["day"];
      if (out) k.push("out");
      if (isToday) k.push("today");
      if (isSel) k.push("sel");
      if (o.compact) k.push("compact");
      const lunar = o.lunar && !out ? `<span class="l">${LUNAR[d] || ""}</span>` : "";
      const dot = (!out && (d === 9 || d === 16 || d === 23)) ? `<span class="dot"></span>` : "";
      return `<div class="${k.join(" ")}" style="height:${o.cellH}px">
        <span class="n">${d}</span>${lunar}${dot}</div>`;
    }).join("");
    return `<div class="week${rowIndex >= 0 ? " shown" : ""}">${cells}</div>`;
  }).join("");
  return `<div class="${cls}"><div class="weekhead">${S.weekday.map((w) => `<span>${w}</span>`).join("")}</div>${rows}</div>`;
}

/* 日历面板头部（月标题 + 年按钮 + 今日） */
function calPaneHead(layout, opts) {
  const o = Object.assign({ today: true, yearButton: true, layout: "inline" }, opts);
  /* 横屏时标题行要避开左侧导航胶囊 + 灵动岛的纵向范围（150pt） */
  const headStyle = o.layout === "stacked"
    ? `padding:2px 2px 4px ${PHONE_CHROME.headInset}px`
    : `padding:${o.pad || "2px 2px 4px"}`;
  const titleBlock = `
    <div class="cal-head" style="${headStyle}">
      <div style="display:flex;align-items:baseline;gap:8px;min-width:0">
        <span class="cal-month">${S.monthTitle}</span>
        ${o.yearButton
          ? `<span class="cal-year">${S.year}年 ${ICON.chevD}</span>`
          : `<span class="cal-year">${S.year}年</span>`}
      </div>
      ${o.today ? `<span class="pill small">${ICON.cal}今天</span>` : ""}
    </div>`;
  /* 横屏：标题行独立一行，不与月格抢位置（左上角硬件区也一起避开） */
  if (o.layout === "stacked") return titleBlock;
  return `<div class="pane-head" style="padding:6px 2px 4px">${titleBlock}${o.trailing || ""}</div>`;
}

/* 内容面板头部：日期 + 星期 + 农历 + 操作 */
function contentHead(layout, opts) {
  const o = Object.assign({ actions: true }, opts);
  return `<div class="pane-head" style="padding:10px 4px 6px">
    <div>
      <div style="font-size:var(--t-card);font-weight:600;letter-spacing:-.01em">${S.today}</div>
      <div style="font-size:var(--t-caption);color:var(--on-surface-variant)">${S.lunarToday} · 共 3 段</div>
    </div>
    <div style="flex:1"></div>
    ${o.actions ? `<span class="icon-btn">${ICON.pencil}</span><span class="icon-btn">${ICON.share}</span>` : ""}
  </div>`;
}

function statRow() {
  const stats = [["3", "国家"], ["6", "省份"], ["11", "城市"], ["42", "片段"], ["37", "天数"]];
  return `<div class="card" style="padding:14px 6px"><div class="stat-row">
    ${stats.map(([v, l]) => `<div class="stat"><b>${v}</b><span>${l}</span></div>`).join("")}
  </div></div>`;
}

function bars(years, compact) {
  const max = Math.max(...years.map((y) => y[1]));
  return `<div style="display:flex;align-items:flex-end;gap:2px;flex:1;min-width:0">
    ${compact ? "" : `<div class="chart-y"><span>${max}</span><span>${Math.round(max / 2)}</span><span>0</span></div>`}
    <div class="bars" style="flex:1">
      ${years.map(([y, v]) => `<div class="bar" style="height:${Math.max(6, (v / max) * 100)}%"><b>${v}</b><span>${y}</span></div>`).join("")}
    </div>
  </div>`;
}

function tree() {
  return `<div class="tree">${FOOT_NODES.map((n) => `<div class="row lvl-${n.d}">
    ${ICON[n.i]}<span class="nm">${n.n}</span><span class="ct">${n.c}</span>
    ${n.open !== undefined ? `<span class="chev">${ICON.chevR}</span>` : ""}
  </div>`).join("")}</div>`;
}

function searchResult(item, selected) {
  const body = item.body.replace(/雾/g, "<mark>雾</mark>");
  return `<div class="result${selected ? " selected" : ""}">
    <div style="flex:1;min-width:0">
      <div style="display:flex;align-items:center;gap:6px;margin-bottom:6px">
        <span class="tag">${ICON.cal}${item.date}</span>
      </div>
      <div class="snip">${body}</div>
    </div>
    <div class="time">${item.time}</div>
  </div>`;
}

function settingRow(opts) {
  const o = Object.assign({}, opts);
  const trailing = o.toggle !== undefined
    ? `<span class="toggle${o.toggle ? "" : " off"}"></span>`
    : `<span class="val">${o.value || ""}</span>${ICON.chevR.replace("<svg", '<svg class="chev"')}`;
  return `<div class="srow">
    <span class="badge">${ICON[o.icon]}</span>
    <span class="txt"><b>${o.title}</b>${o.sub ? `<i>${o.sub}</i>` : ""}</span>
    ${trailing}
  </div>`;
}

function settingsCard(title, rows) {
  return `<div class="card"><div class="sect">${title}</div>${rows.join("")}</div>`;
}

/** 设置页的全部卡片（手机横屏两列、iPad / Mac 三列，共用同一份内容）。 */
function settingCards() {
const cards = [
    settingsCard("通用", [
      settingRow({ icon: "globe", title: "语言", sub: "应用内立即生效", value: "跟随系统" }),
      settingRow({ icon: "palette", title: "主题", sub: "浅色 / 深色 / 跟随系统", value: "深色" }),
    ]),
    settingsCard("规则", [
      settingRow({ icon: "sun", title: "新一天开始时间", sub: "凌晨 4:00 之前算前一天", value: "4:00" }),
      settingRow({ icon: "cal", title: "每周起始", sub: "影响日历与统计", value: "周一" }),
      settingRow({ icon: "pin", title: "自动记录位置", sub: "新建片段时记录一次", toggle: true }),
    ]),
    settingsCard("写作与提醒", [
      settingRow({ icon: "clock", title: "自动记录时间", sub: "新建片段时写入当前时刻", toggle: true }),
      settingRow({ icon: "pencil", title: "允许编辑历史", sub: "可修改过去日期的日记", toggle: false }),
      settingRow({ icon: "bell", title: "每日提醒", sub: "当天没有写日记时提醒", toggle: true }),
      settingRow({ icon: "clock", title: "提醒时间", sub: "按设备的小时制显示", value: "21:30" }),
    ]),
    settingsCard("数据", [
      settingRow({ icon: "up", title: "导出备份", sub: "含图片的完整 zip", value: "" }),
      settingRow({ icon: "down", title: "导入备份", sub: "支持旧版本备份", value: "" }),
    ]),
    settingsCard("关于", [
      settingRow({ icon: "info", title: "版本", value: "1.0 (1)" }),
    ]),
  ];
  return cards;
}

/* ------------------------------------------------------------------ 通用绘制函数 */

/* 月视图。opt: {cellH, lunar, rowOnly, sel, compact, fill, row} */
function monthGrid(opt) {
  const o = Object.assign({ cellH: 60, lunar: true, rowOnly: false, sel: 16, row: 2 }, opt);
  /* 周条不是「只有一周的月历」，而是「只显示某一行」：上下的周仍要参与
     判断哪些日期属于本月（首行/末行的灰日期就是这么来的）。 */
  const weeks = o.rowOnly ? [SEPT_WEEKS[o.row]] : SEPT_WEEKS;
  const rowIndex = o.rowOnly ? o.row : -1;
  const cls = ["month-grid", o.rowOnly ? "row-only" : "", o.compact ? "compact" : "",
               o.fill ? "fill" : ""].join(" ");
  const rows = weeks.map((days, wi) => {
    const cells = days.map((d) => {
      const idx = rowIndex >= 0 ? rowIndex : wi;
      const out = (idx === 0 && d > 20) || (idx === SEPT_WEEKS.length - 1 && d < 7);
      const isToday = !out && d === 16;
      const isSel = !out && d === o.sel;
      const k = ["day"];
      if (out) k.push("out");
      if (isToday) k.push("today");
      if (isSel) k.push("sel");
      if (o.compact) k.push("compact");
      const lunar = o.lunar && !out ? `<span class="l">${LUNAR[d] || ""}</span>` : "";
      const dot = (!out && (d === 9 || d === 16 || d === 23)) ? `<span class="dot"></span>` : "";
      return `<div class="${k.join(" ")}" style="height:${o.cellH}px">
        <span class="n">${d}</span>${lunar}${dot}</div>`;
    }).join("");
    return `<div class="week${rowIndex >= 0 ? " shown" : ""}">${cells}</div>`;
  }).join("");
  return `<div class="${cls}"><div class="weekhead">${S.weekday.map((w) => `<span>${w}</span>`).join("")}</div>${rows}</div>`;
}

/* 日历面板头部。opt: {title, sub, today, yearButton, monthTitle} */

/* 内容面板头部：日期 + 星期 + 农历 + 操作 */
function contentHead(layout, opts) {
  const o = Object.assign({ actions: true, big: false, todayChip: false, compact: false }, opts);
  return `<div class="pane-head" style="padding:8px 2px 6px">
    <div>
      <div style="font-size:${o.big ? "var(--t-page)" : "var(--t-card)"};font-weight:600;letter-spacing:-.01em">${S.today}</div>
      <div style="font-size:var(--t-caption);color:var(--on-surface-variant)">${S.lunarToday} · 共 3 段</div>
    </div>
    <div style="flex:1"></div>
    ${o.todayChip && !o.compact ? `<span class="pill">${ICON.cal}今天</span>` : ""}
    ${o.actions ? `<span class="icon-btn">${ICON.pencil}</span><span class="icon-btn">${ICON.share}</span>` : ""}
  </div>`;
}

function dayCard(item, opts) {
  const o = Object.assign({}, opts);
  return `<div class="card" style="margin-bottom:10px">
    <div class="card-meta">
      ${item.time ? `${ICON.clock}<span style="color:var(--primary);font-weight:600">${item.time}</span>` : ""}
      ${item.loc ? `${ICON.pin}<span>${esc(item.loc)}</span>` : ""}
    </div>
    ${item.title ? `<div class="card-title" style="font-size:19px">${esc(item.title)}</div>` : ""}
    <div class="card-body">${esc(item.body)}</div>
    ${item.quote ? `<div class="card-body" style="margin-top:8px"><div class="quote">${esc(item.quote)}</div></div>` : ""}
  </div>`;
}

function statRow() {
  const stats = [["3", "国家"], ["6", "省份"], ["11", "城市"], ["42", "片段"], ["37", "天数"]];
  return `<div class="card" style="padding:14px 6px"><div class="stat-row">
    ${stats.map(([v, l]) => `<div class="stat"><b>${v}</b><span>${l}</span></div>`).join("")}
  </div></div>`;
}

function bars(years, compact) {
  const max = Math.max(...years.map((y) => y[1]));
  return `<div style="display:flex;align-items:flex-end;gap:2px;flex:1;min-width:0">
    ${compact ? "" : `<div class="chart-y"><span>${max}</span><span>${Math.round(max / 2)}</span><span>0</span></div>`}
    <div class="bars" style="flex:1">
      ${years.map(([y, v]) => `<div class="bar" style="height:${Math.max(6, (v / max) * 100)}%"><b>${v}</b><span>${y}</span></div>`).join("")}
    </div>
  </div>`;
}

function tree() {
  return `<div class="tree">${FOOT_NODES.map((n) => `<div class="row lvl-${n.d}">
    ${ICON[n.i]}<span class="nm">${n.n}</span><span class="ct">${n.c}</span>
    ${n.open !== undefined ? `<span class="chev">${ICON.chevR}</span>` : ""}
  </div>`).join("")}</div>`;
}

/* 网格（用于足迹/搜索分栏的外壳） */
function gridCols(inner, cols, maxW) {
  return `<div class="cardgrid" style="grid-template-columns:repeat(${cols},minmax(0,1fr));
    ${maxW ? `max-width:${maxW}px;margin:0 auto;` : ""}width:100%">${inner}</div>`;
}


/* ------------------------------------------------------------------ 标注 */

/** 过滤出适用于某张稿的标注（支持 `for` 限定首段关键字）。 */
function annotsFor(list, frameId) {
  if (!list || !list.length) return [];
  const kind = (frameId || "").split("-")[0];
  return list.filter((a) => !a.for || a.for === kind);
}

/* 一张设计稿上的编号点。文本放在 side panel 的图例里，画面上只留编号。 */
function annots(list, frameId) {
  if (!list || !list.length) return "";
  const use = annotsFor(list, frameId);
  if (!use.length) return "";
  return `<div class="annot-layer">${use.map((a, i) =>
    `<div class="callout" style="left:${a.x}px;top:${a.y}px">${i + 1}</div>`).join("")}</div>`;
}

/** 图例（右侧面板 / 截图下方）。 */
function annotLegend(list, frameId) {
  const use = annotsFor(list, frameId);
  if (!use.length) return "";
  return `<h3>图上标注</h3><ul class="callout-legend">${use.map((a, i) =>
    `<li><span class="n">${i + 1}</span><span class="t">${a.t}</span></li>`).join("")}</ul>`;
}

/* ------------------------------------------------------------------ 版面规则 */

/* 由设备宽度推导出「该用什么版面」。这是整套设计的核心规则，也是规范文档
   里那张表的可执行版本。 */
function layoutFor(dev, kind) {
  const w = dev.w;
  const h = dev.h;

  /* 手机横屏：系统把浮条换成左侧竖排胶囊，内容左边界 88pt */
  if (dev.type === "phone" && dev.landscape) {
    return {
      w, h, kind,
      split: kind === "home" || kind === "footprint" || kind === "search",
      sidebar: false,
      rail: false,
      tabbar: true,
      tabbarPos: "bottom",
      tabbarStyle: "bottom",
      tabbarOffset: Math.round(w / 2 - 190),
      navBarH: PHONE_CHROME.navBarH,
      contentInset: PHONE_CHROME.contentInset,
      gridInset: PHONE_CHROME.gridInset,
      headInset: PHONE_CHROME.headInset,
      islandW: PHONE_CHROME.islandW,
      islandH: PHONE_CHROME.islandH,
      paneW: 336,
      colMax: 0,
      narrow: false,
      cardCols: 2,
      cardMaxW: 0,
      panePad: 18,
    };
  }

  /* iPad / Mac：三栏版面（左导航轨 + 中列表 + 右详情） */
  const sidebar = dev.type === "mac" && w >= 1100;
  const split = kind === "home" ? w >= 980
    : kind === "footprint" ? w >= 900
    : kind === "search" ? w >= 980
    : false;
  const cardCols = w >= 1000 ? 3 : w >= 680 ? 2 : 1;
  return {
    w, h, kind,
    split, sidebar,
    rail: false,
    tabbar: true,
    tabbarPos: "bottom",
    sidebarW: 236,
    paneW: sidebar ? 300 : 340,
    colMax: 0,
    narrow: w < 430,
    cardCols,
    cardMaxW: cardCols >= 3 ? 1120 : cardCols === 2 ? 760 : 0,
    panePad: 20,
    tabbarOffset: Math.round(w / 2 - 190),
  };
}

/* ------------------------------------------------------------------ 渲染 */

function deviceHTML(dev, inner, annotList, layout, frameId, showZones) {
  const cls = ["device", dev.type, dev.landscape ? "landscape" : "", "stage-annot"].join(" ");
  const style = `width:${dev.w}px;height:${dev.h}px;`;
  /* 灵动岛硬件区：设计稿里只作为「不可用区域」的可视化提示 */
  const zone = (showZones && dev.type === "phone" && dev.landscape)
    ? `<div class="zone island-zone"
             style="left:0;top:${(dev.h - PHONE_CHROME.islandLong) / 2}px;
                    width:${PHONE_CHROME.islandShort}px;height:${PHONE_CHROME.islandLong}px">
         <span>灵动岛<br>（竖转）</span></div>`
    : "";
  return `<div class="${cls}" style="${style}">
    ${bgLayer()}
    <div class="shell">${inner}</div>
    ${island(dev)}${lights(dev)}
    ${zone}
    ${annots(annotList, frameId)}
  </div>`;
}

function specTable(rows) {
  if (!rows) return "";
  return `<h3>版面参数</h3><table class="spec-table">
    <tr><th>项</th><th>值</th></tr>
    ${rows.map(([k, v]) => `<tr><td>${k}</td><td class="spec">${v}</td></tr>`).join("")}
  </table>`;
}

function render() {
  const screen = document.getElementById("sel-screen").value;
  const frame = FRAMES.find((f) => f.id === screen) || FRAMES[0];
  const dev = DEVICES[frame.dev];
  const layout = layoutFor(dev, frame.kind || frame.id.split("-")[0]);

  /* 舞台 */
  const inner = frame.screen(dev, layout);
  const stage = document.getElementById("stage-inner");
  stage.innerHTML = `<div class="frame-block">
      <div class="frame-caption">
        <h2>${frame.title}</h2>
        <span class="badge">${frame.tag}</span>
        <span class="size">${dev.w} × ${dev.h} pt · ${dev.name}</span>
      </div>
      <div style="width:${Math.round(dev.w * dev.scale)}px;height:${Math.round(dev.h * dev.scale)}px">
        <div style="transform:scale(${dev.scale});transform-origin:0 0">
          ${deviceHTML(dev, inner, frame.annots, layout, frame.id, true)}
        </div>
      </div>
      <div class="frame-note">${frame.note}</div>
    </div>`;

  /* 规格面板 */
  const panel = document.getElementById("specpanel-inner");
  panel.innerHTML = `
    <div class="kicker">版面设计</div>
    <h2>${frame.title}</h2>
    <p style="opacity:.6;font-size:12px">${dev.name} · ${dev.w} × ${dev.h} pt</p>
    <div class="spec-note">${frame.note}</div>
    ${specTable(frame.spec)}
    <h3>本稿实测</h3>
    <table class="spec-table">
      <tr><th>项</th><th>值</th></tr>
      <tr><td>主栏宽度</td><td class="spec">${layout.split ? layout.paneW + "pt" : "—（单栏）"}</td></tr>
      <tr><td>浮条位置</td><td class="spec">${layout.tabbarStyle || layout.tabbarPos}</td></tr>
      <tr><td>内容列上限</td><td class="spec">${layout.colMax ? layout.colMax + "pt" : "不限"}</td></tr>
      <tr><td>档位</td><td class="spec">${layout.split ? (dev.w >= 1000 ? "中/宽" : "中等") : "紧凑"}</td></tr>
    </table>
    ${annotLegend(frame.annots, frame.id)}
    <h3>判定规则</h3>
    <table class="spec-table">
      <tr><th>项</th><th>值</th></tr>
      <tr><td>可用宽度</td><td class="spec">${layout.w}pt</td></tr>
      <tr><td>本地分栏</td><td class="spec">${layout.split ? "是" : "否"}</td></tr>
      <tr><td>侧边栏</td><td class="spec">${layout.sidebar ? "系统侧边栏" : "底部浮条"}</td></tr>
      <tr><td>卡片列数</td><td class="spec">${layout.cardCols}</td></tr>
    </table>
    <h3>为什么这样排</h3>
    ${dev.type === "phone"
      ? `<p>手机只有一个分栏阈值：月历需要 ≥260pt 才放得下 7 列（每格 ~37pt），详情栏需要
    ≥240pt 才不至于每行只折三四个字。两者加上页边距 16×2 与栏间距 16.5，就是
    <span class="spec">548.5pt</span> —— 所有横屏 iPhone 都在它之上（18 Pro 可用 750pt、
    iPhone SE 667pt），所以横屏首页一律左右双列；只有分屏 / 折叠这类真正窄的窗口才退回
    单栏，宁可滚动，也不要挤。</p>`
      : `<p>宽屏的每一个分栏都对应一个最小宽度（首页 980pt、足迹 900pt、搜索 980pt）：
    列表栏要放得下标题与摘要，详情栏要放得下正文。宽度不到就老实退回单栏 ——
    宁可滚动，也不要挤。</p>`}
  `;
}

/* ------------------------------------------------------------------ 启动 */

/** 由页面在 scripts 标签里通过 data-frames / data-devices 指定要加载的文件。 */
function bootMockupPage() {
  const sel = document.getElementById("sel-screen");
  sel.innerHTML = FRAMES.map((f) => `<option value="${f.id}">${f.title}</option>`).join("");
  sel.value = FRAMES[0].id;

  const theme = document.getElementById("sel-theme");
  const applyTheme = () => { document.documentElement.dataset.theme = theme.value; };
  theme.addEventListener("change", applyTheme);
  applyTheme();

  sel.addEventListener("change", render);

  const annot = document.getElementById("sel-annot");
  annot.addEventListener("change", () => {
    document.querySelectorAll(".annot-layer").forEach((el) => {
      el.style.display = annot.value === "on" ? "" : "none";
    });
  });

  const spec = document.getElementById("chk-spec");
  spec.addEventListener("change", () => {
    document.querySelector("main").classList.toggle("spec-off", !spec.checked);
  });

  const legend = document.getElementById("legend");
  if (legend) legend.innerHTML = FRAMES.map((f) => f.title).join(" · ");

  render();
}

/* ------------------------------------------------------------------ 竖屏文案与数据 */

S.todayLabel = "今天";
S.footprintTitle = "足迹";
S.searchTitle = "搜索";
S.settingsTitle = "设置";

/* 2026 年 12 个迷你月的排布（周一起始）：每月 1 号前的空格数 + 天数 */
const SEPT_MINI_OFFSET = { 1: 3, 2: 6, 3: 6, 4: 2, 5: 4, 6: 0, 7: 2, 8: 5, 9: 1, 10: 3, 11: 6, 12: 1 };
const SEPT_MINI_DAYS = { 1: 31, 2: 28, 3: 31, 4: 30, 5: 31, 6: 30, 7: 31, 8: 31, 9: 30, 10: 31, 11: 30, 12: 31 };
S.miniOffset = SEPT_MINI_OFFSET;
S.miniDays = SEPT_MINI_DAYS;
