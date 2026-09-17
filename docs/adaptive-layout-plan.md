# 横屏 / iPad / Mac 自适应布局方案（含 iPhone Duo 预留）

日期：2026-09-16 · 环境：Xcode 27.0 / iOS 27.0 SDK · 目标：iPhone + iPad + Mac（Designed for iPad）
设计稿：`docs/design/landscape/index.html`（可交互）· `docs/design/landscape/screens/*.png`（16 张定稿图）

本文回答一件事：**同一套代码，怎么在手机竖屏、手机横屏、iPad 竖屏/横屏、Mac 窗口、
以及展开后的 iPhone Duo 上都排得好看**。

> **当前状态（2026-09-17）**：手机端**已实现**（首页横屏分栏、日历密度降级、横屏上下
> 滑动翻月、足迹/搜索/设置/阅读页的横屏版面、关键词栏），并有 `AdaptiveLayoutTests`、
> `LandscapeLayoutUITests` 与 `MorphPerfUITests` 守住。iPad / Mac 的三栏版面仍是
> 「骨架先行版」（`docs/design/landscape/wide.html`），按你的要求后续单独打磨。
>
> 三个已确认的前提：
> 1. **竖屏交互完全不动** —— 年历 / 月历 / 周历三态与之间的 morph 动画原样保留
>    （只修动画收尾的跳变，不改交互）。
> 2. **横屏不提供年份切换** —— 整块头部与年份胶囊都不出现，只上下滑切月；横屏不引入
>    第二套交互，以免和竖屏的年历 morph 打架。
> 3. **横屏左侧安全区 62pt 已经由几何原点承担** —— 实测 `safeAreaInsets`：
>    竖屏 `T62 L0 B34 R0`、横屏 `T0 L62 B20 R62`，几何原点已在安全区内，页面只加自己的
>    16pt 边距；**不要再减一次**，否则就是重复避让。
>
> 2026-09-17 修掉的三处：竖屏「年→月」morph 收尾上跳 40pt（`MonthPane` 标题槽被
> 改成 32pt 而 morph 按 72pt 算）、「月→年」morph 收尾日期字号跳变（年历页写死 11pt）、
> 横屏重复避让安全区 + 翻月收尾跳变（详见 §3.1.1 / §3.1.2）。

---

## 一、结论摘要

1. **只有一条判定规则**：版面按「当前可用宽度」分档，不看设备型号、不看
   `UIDevice.idiom`、不看 `UIDevice.orientation`、不读 `UIScreen.main`
   （这条直接来自 Apple 的 Duo 适配指南：Duo 展开后**仍然是 iPhone**，但宽高都是
   regular；按型号分支的代码在它上面必然错）。
2. **导航交给系统**：`TabView` 加 `.sidebarAdaptable`。紧凑宽度是底部浮条，横屏/宽窗口
   是侧边栏，Mac 上是原生侧边栏。**不自己写第二套导航**，也不为 iPad 单独做一套布局。
3. **宽屏不是「把东西拉大」，是「把原来叠在一起的拆开」**：日历 ↔ 选中日、图表 ↔ 清单、
   筛选 ↔ 结果、卡片列数。每一处分栏都对应一个最小宽度，宽度不够就老实退回单栏滚动。
4. **正文永远单栏**：阅读页限制在 ≤660pt（约 60–75 字符）并居中。用户提的
   「日记页卡片左右双列交叉排列」在阅读场景会破坏阅读顺序，不采用（理由见 §6）。
5. **砍掉两级整屏层级**：「年历」整屏视图与「月↔周整屏 morph」在横屏里是净负担。
   年、月选择统一收敛到左上角入口 + 滚轴弹层（宽屏 popover / 窄屏 sheet），
   交互层级从三级降到二级；月历的密度按可用高度自动决定（月格 ↔ 周条）。

---

## 二、自适应系统

### 2.1 三档宽度（唯一的判定规则）

| 档 | 可用宽度 | 导航形态 | 页面内含分栏 | 卡片列数 |
|---|---|---|---|---|
| **紧凑** | < 700pt | 底部浮条 | 无（单栏滚动） | 1 |
| **中等** | 700 – 999pt | 底部浮条 / 顶部浮条（横屏） | 有：主栏 + 详情栏 | 1–2 |
| **宽** | ≥ 1000pt | 系统侧边栏（≥1100pt 时） | 有：可到 3 区 | 2–3 |

分档的阈值不是拍脑袋：**月历 7 列至少需要 280pt（40pt/格）才有可用性，阅读栏至少需要
320pt 才不至于每行折 3 次**，两者相加就是首页的分栏阈值 ≈ 700pt。其余屏的分栏阈值
同理（足迹 900、搜索 800、设置列数 680/1000）。

落到具体设备：

| 设备 / 形态 | 参考尺寸 (pt) | 档 | 首页 |
|---|---|---|---|
| iPhone 18 Pro 竖屏 | 402 × 874 | 紧凑 | 月历 + 下方日记（现状保留） |
| iPhone 18 Pro 横屏 | 874 × 402 | 中等 | **左右分栏**（左月历 340 / 右日记） |
| iPad Pro 13 竖屏 | 1032 × 1376 | 宽 | 分栏 340 / 692 |
| iPad Pro 13 横屏 | 1376 × 1032 | 宽 | 分栏 400 / 976（右栏卡片两列） |
| iPad mini 竖屏 | 744 × 1133 | 中等 | 分栏 300 / 444 |
| iPad 分屏（1/3） | ~320 × 1032 | 紧凑 | 单栏 |
| Mac 窗口 | 1432 × 900 | 宽 | 侧边栏 + 分栏 400 / 796 |
| **iPhone Duo 内屏** | **≈664 × 750** | **紧凑** | **单栏（与手机竖屏同一套）** |

> 关键点：**Duo 不需要任何专用代码**。664pt 落在「紧凑」档，走的就是手机竖屏那条路径
> （单栏、月格更高）。iPad mini / iPad 分屏 / 横屏手机已经覆盖了它两侧的所有档位，
> 所以这套方案不是在赌一个还没上市的设备。

### 2.2 导航：交给系统（`.sidebarAdaptable`），app 只负责避让

**先看真机实测**（iPhone 18 Pro / iOS 27，UI 测试读 accessibility frame）：

| 形态 | 系统导航的实际位置 |
|---|---|
| 竖屏 | 底部浮条，`y = 338…402`（表观为一枚胶囊，按钮 36pt 高） |
| **横屏** | **左侧竖排胶囊：x 12–76、纵向居中**，四个条目竖排 |
| 横屏灵动岛 | **竖转**贴左边缘：37 宽 × 132 高、垂直居中（= 竖屏尺寸转 90°） |
| **横屏浮条** | **贴左边缘的竖排胶囊**：占用 `x 12–76`、纵向居中；`safeArea.leading = 62` |
| iPad / Mac 宽窗口 | 侧边栏（`sidebarAdaptable` 自动切换） |

> **这个结论被反复推翻过两次，最后以「方向无关」的方式钉死**：
> 把浮条中心与屏幕中心的距离分别按横竖两个方向算一遍 —— 浮条中心 `(32, 360)`、
> 屏幕中心 `(437, 201)`，两者相距很远，所以它**只能**是贴在某一侧的竖排条；再看
> `x 12–76` 贴着 0 边，就确定是**左边缘**。
>
> 中间我用截图旋转看图，得出了两个相反的结论，都是错的。**教训**：设备旋转会让
> `Frame` 仍以竖屏坐标系报告，判断「在哪一侧」必须用这种**方向无关**的度量，
> 不要靠肉眼看截图。最终用应用内日志读 `safeAreaInsets` 复核：横屏 `leading = 62`。

> **2026-09-17 复核（iPhone 18 Pro / iOS 27 模拟器）**：`safeArea.leading = 62` 这一条不变，
> 但**浮条本身在横屏是底部居中**的：`app.tabBars` 的 frame 实测 `(0, 338, 874, 402)`，
> 屏幕截图里也能看到那枚胶囊在底部中央。所以首页横屏除了右移 `leading` 之外，
> **还要在底部为浮条留出空间**（否则两栏的最后一行会被压住），见 §3.1.1。
> 结论仍然成立的部分是：app 不该自己再画第二条导航，只负责避让。

所以：`TabView` 加 `.tabViewStyle(.sidebarAdaptable)` 之后，横屏的导航形态**不用我们管**
（系统自动变竖排胶囊），我们要做的是让每个页面在「少 124pt 宽、但有 402pt 高」的空间里
重新排版 —— 内容本身已经落在安全区里，**不需要再手动右移**。

横向的顶部/底部浮条（前一版设计稿里的做法）是错的：系统不会那样排，猜出来的位置在真机上
会和内容打架。

**为什么不用 `NavigationSplitView` 当外壳**：那是「列表 → 详情」的容器，会把 4 个 tab
降级成侧边栏里的一层列表，还会和页内已有的主从结构（日历→日记、结果→预览）套成两层
嵌套导航。页内分栏用普通 `HStack` 就够，不需要第二个导航容器。

### 2.2.1 「导航胶囊放右边 / 缩小居中放底部」这个问题的结论

你提的两种方案都认真验过，结论是：**两条都不需要做 —— 左侧那条是系统自己放的，
我们只能避让，改不了也不该改**。

| 想法 | 结论 |
|---|---|
| 挪到**右边**，避开左边的灵动岛 | 做不到。浮条由系统托管（`TabView`），横屏时它固定在**左边缘竖排居中**；app 无法改它的边 |
| 旋转后和灵动岛重叠 | **确实同侧**：浮条 `x 12–76`、灵动岛 `x 0–37`，都在左侧。好在岛竖直居中（`y ≈ 135–267`）、浮条也竖直居中，两者在纵向范围上会**部分重叠**——但那个重叠区本来就是系统自己的东西（岛是硬件开孔，浮条是系统控件），不需要我们处理 |
| 自己缩小居中放屏幕底部 | 不建议。`TabView` + `.sidebarAdaptable` 横屏不给底部形态；自己在底部再画一条「导航胶囊」会出现**两条导航**，还会丢掉系统白送的三件事（iPad 宽窗口自动侧边栏、滚动自动最小化、VoiceOver tab 语义） |

**我们能做、也该做的只有一件事**：让内容避开左侧 `safeArea.leading`（横屏 62pt）。
而几何原点已经在安全区内，所以**四屏只需要加自己的 16pt 页边距**
（`.adaptivePagePadding()`，见 §5.4 第 8 条）；`AdaptiveLayout.contentInset` 只用于
「可用内容宽度」这类计算，**不要**再叠进页边距，也不要 `MonthPane` / 分栏内各减一遍
（见 §3.1.1）。

### 2.3 页内分栏的三条约束

1. **分栏用 `HStack` + 固定宽度的主栏**，详情栏 `frame(maxWidth:.infinity)`。
   主栏不需要拖动分隔条 —— 它的宽度由内容决定（月历 7 列、筛选表单），不是用户偏好。
2. **详情栏里的文字列必须限宽**（阅读 660 / 编辑 620 / 卡片流 480 每列）。
   否则 1376pt 的窗口会把正文拉成一行 120 个字，这是宽屏最常见也最难看的错误。
3. **分栏之后，顶部工具只属于详情栏**，不跨栏悬浮。跨栏的工具栏在大屏上和两栏都没有
   归属关系。

---

## 三、逐屏版面

设计图见 `docs/design/landscape/screens/`，下列文件名即对应图片。

### 3.1 首页 `ph-home-*.png`

| 形态 | 版面 |
|---|---|
| 竖屏（402pt） | **保持现状**：`‹ 年月` 胶囊 +「今天」→ 72pt 标题槽（32pt 月标题）→ 30pt 星期栏 → 六行月格（有日记＝下划线、今天＝圆环、选中＝实心圆、未来 35%）；点日期 morph 到周视图、点年月胶囊 morph 到年历。设计稿里这三屏（`ph-home-portrait` / `ph-home-week` / `ph-home-year`）是**按实现 1:1 复刻**的对照基准 |
| 横屏（874 × 402） | 系统占位已含在安全区里 → **可用 750 × 382**；页面只再加 16pt 边距；**左栏月历 345pt + 右栏日记 ≈356pt**；左栏上下翻月 |
| 横屏・高度不足 | 左栏降级为**周条**（一行 7 天，横向翻周），右栏高度不变 |
| 横屏・年份 | **不提供年份切换**：整块头部隐藏、右栏标题行也**没有年份胶囊**；上下滑跨月时自然跨年 |
| 横屏・回到今日 | 「今天」放在**右栏标题行**（左栏整行留给月标题与日期格子） |
| iPad / Mac | 三栏：导航轨 + 中栏 + 右栏（先行版，后续打磨） |

**日历密度按高度自适应**，这是替代原来「月↔周整屏 morph」的关键：

```
可用高度 ≥ 6×60 + 标题        → 月格（显示农历；横屏一般到不了）
可用高度 ≥ 6×44 + 标题        → 月格（隐藏农历行）
否则                          → 周条（1 行，横向翻周）
```

横屏手机 402pt 高，扣掉顶部 8pt、底部给系统浮条让出的 64pt，日历区约 330pt；
标题槽 34 + 星期栏 26 = 60，剩 270 给 5–6 行 → 每格 45–54pt（日号 15–18pt），是能读的下限；
如果连这个都放不下（键盘弹起、Duo 折成一半、分屏），自动变周条。

**年月切换（仅竖屏）**：竖屏**保持现在的整屏年历 + 缩放 morph**，不加新入口、不改形状。
- 横屏**不提供**年份切换（只上下滑切月），也没有任何可以点进年历的按钮。
- 曾经画过一版「年月滚轴浮层」作为备选，**已删除** —— 竖屏既然保留年历 morph，就不该再有第二套
  切年月的交互。
- 无障碍：补回 `a11y_prev_year` / `a11y_next_year` 可调节动作（对应
  `docs/design-system.md` §7 记的缺口）。

**morph 终点即真实排版**：`MonthPane` 的标题槽 / 星期栏高度（竖屏 `bigTitleH(72)` +
`weekdayHeaderH(30)`，横屏 34 + 26）**必须**与 morph 里的槽位用同一组常量，
否则动画收尾、真实图层接上时会整体跳一下。竖屏这条曾因为横屏引入紧凑标题行时
把默认值也改成了 32 而复发（morph 按 72 算，收尾上跳 40pt），现由
`MonthPane.portraitGridOriginY` / `CalendarLayout.fullMonthGridRect` 共用同源常量。
年历迷你月的日期字号也必须由 `CalendarLayout.miniMetrics` 统一提供 —— 年历页与
morph 起点各算一遍时，收尾会出现字号跳变。

**回到今日**：竖屏在右上角（现状不变）；横屏在右栏标题行右侧，位置固定。

### 3.1.1 手机横屏的系统占位（实测，2026-09-17）

```
x:  0 ───── 62 ─ 78 ─────────── 423 ─ 439 ─────────────── 795.5 ─ 812 ─ 874
    │ 安全区 │16│   左栏月历 345   │ 16 │    右栏日记 ≈356        │16│安全区
y:  0 ───────────────────────────────────────────────────────────────
    │ 8pt 顶部留白                                                      │
    │  月标题 34 → 星期栏 26 → 5/6 行日期（每格 45–54）                   │
    │                                                                   │
    │        ┌─────────────────────────┐ ← 系统浮条：y 338–402，居中    │
    │        │  日记  足迹  搜索  设置   │    会盖住两栏的最后一行        │
    ────────────────────────────────────────────────────────────────── 402
```

- 实测 `safeAreaInsets`：竖屏 `T62 L0 B34 R0`、横屏 `T0 L62 B20 R62`；
  横屏**可用内容宽度就是 750pt**（874 − 62 − 62），几何原点已经在安全区内。
- 所以页面**只需要加自己的 16pt 边距**，日历紧贴 `leading = 62 + 16 = 78` 起。
  **不要**再减一次 `safeArea.leading`：第一版在 `HomeView` 与 `MonthPane` 里
  各避让了一次（还外加一层 78pt padding），日历被推到 x ≈ 222，左半屏白白空着 ——
  这就是「横屏没有充分利用屏幕、左右避让过多」的根因。
- 顶部没有安全区（`T0`），标题行由页面自己留 8pt；底部 `bottomInset(20) + 44`
  是给那枚悬在底部的系统浮条让位（浮条上沿实测 y = 338，`tabBars` frame 为
  `(0, 338, 874, 64)`）。
- 导航形态交给系统（`TabView(.sidebarAdaptable)`），app 不自己画第二条导航；
  这些数值都从 `safeAreaInsets` 派生，Duo 折痕、左右不对称安全区、未来 27.1 的
  `reservedRegion` 都能直接接上。

### 3.1.2 横屏翻月的手势与动画

- 左栏**上下滑**翻月（与竖屏同方向，不引入第二套手势方向），只画当前月。
- `DragPagePager` 的翻页收尾必须把 `current` 与 `offset = 0` 放进**同一个无动画事务**：
  先换 `current` 再补 `offset`，会先用旧偏移渲染一帧新页（页面向上一跳）再滑回来，
  观感就是「翻月不连贯、末尾跳变」。拖动过程的偏移也要夹在一页之内，
  否则会露出当前页之外的空白再回弹。
- 翻月后选中日跟着进入新月份的同一天（月末按当月天数夹住），右栏才和左栏对得上。
- 右栏标题行与内容区都限高到日历区高度（`paneH`），两栏底部对齐、都不压到浮条。

### 3.2 足迹 `ph-footprint-landscape.png`

- 手机竖屏：统计行 → 趋势图 → 地点清单，单栏滚动（保持实现）。
- **手机横屏：统计行 → 「年度趋势图 | 地点清单」并排两栏**（图表 flex、清单固定
  `contentWidth × 0.4`，夹在 240–320pt）。两块高度取
  `max(140, min(190, screenH − 262))`：标题 + 筛选 + 统计约占 200pt、底部浮条 64pt，
  再高首屏就会把图表的横轴压到浮条底下。清单在这块高度里内部滚动。
- iPad / Mac：三栏（导航轨 + 统计图表 + 清单）。

> 这里改过两次，原因值得记下来：横屏的**真实可用宽度是 750pt**（874 − 62 − 62），
> 达不到足迹的分栏阈值 **900pt**，所以**做不了**左右分栏 —— 我之前说「两列不行」
> 是因为没算对可用宽度，而后来改成两栏又是因为拿 874 当成了可用宽度。
> 正确的做法就是这里写的：不分栏，但把两个块**并排**放进同一列里。

### 3.3 搜索 `ph-search-landscape.png`

- 手机横屏（可用 750pt < 800 分栏阈值）：**条件压成一行** —— 搜索框一行，下面
  「时间范围 | 地点」两组筛选并排成一行（省下约 60pt 竖高留给结果）；
  **结果保持与竖屏一致的单栏纵向列表** —— 横屏每行更长、摘要多显示半行，扫读更快。
  之前那版「结果横向铺成 4 列」已改掉。
- **新增关键词栏**：搜索框下方一行「关键词」，每个生效中的关键词是一个可单独点掉的胶囊
  （多个关键词时一眼看清在搜什么），右侧是「清除全部条件」。这一栏在竖屏也应该有，
  属于实现缺口（见 §5.3）。
- iPad / Mac：三栏（条件 / 结果 / 预览）。

> 多关键词的处理沿用实现里已有的 `activeFilterItems`（`SearchFilterItem`：keyword /
> time / location 三类），不需要新模型 —— 只是把「关键词」这一类单独画成一行展示。

### 3.4 设置 `ph-settings-landscape.png`

卡片式，列数只随宽度变：**1 列（<680）→ 2 列（≥680）→ 3 列（≥1000）**。
卡片顺序不变，每张卡自我完整（通用 / 规则 / 提醒 / 数据 / 关于）。
设置没有主从关系，所以不做「左列表右详情」。

### 3.5 日记页 `ph-read-landscape.png`（宽屏见 `wide-*.png`）

- **阅读**：正文单栏限宽 **660pt** 居中；窗口 ≥1000pt 时左侧出现「本日片段」索引
  （时间 + 首行），两侧留白。大标题 28 / 小标题 22 / 正文 17 / 引用 15 不变。
  图片与地图可以与正文并排 —— 那是「并排的介质」，不是「并排的文字」。
- **编辑**：正文列宽 **≤620pt**；键盘弹起时把格式栏改成**竖向贴右侧**（宽屏），
  窄屏退回键盘上方的横向玻璃条。位置规则沿用 `docs/design-system.md` §5：
  键盘弹起时贴键盘上方 8pt，收起时贴 Home Indicator 上方。

---

## 四、iPhone Duo：现在就要做的三件事

Apple 的适配指南（[Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/)、
[Raise the bar](https://developer.apple.com/videos/play/tech-talks/111462/)）里与本项目直接相关的四条：

1. **用尺寸类，不要用 idiom**。Duo 展开是 regular × regular，但仍是 iPhone；
   内屏也不遵守 `supportedInterfaceOrientations`。
2. **左右安全区不对称**。竖排的控制条可能出现在任意一侧，要分别处理 inset 与
   layout margin，背景延伸到条下面、交互内容留在里面。
3. **工具栏移到侧边由容器负责**。用 `TabView` / 导航容器的 bar，不要自己画悬浮条 ——
   自己画的不会被系统接管，横过来就还在底部。
4. **让系统处理折痕**。sheet / alert / menu 已经自动避开；自定义布局等 27.1 的
   `reservedRegion`（`GeometryProxy` / `UIView`）再接。

**本项目的动作**：

| 现在做 | 说明 |
|---|---|
| 删掉 `Screen.size` / `Screen.height` 作为布局依据的用法 | 保留 `Screen.safeAreaBottom`（底部安全区，编辑器要用），但要改成从当前场景读、并允许为 0 |
| 所有分栏判定改用 `horizontalSizeClass` + 实测宽度 | 见 §5 的 `AdaptiveLayout` |
| 左右 padding 分别取 `safeAreaInsets.leading/trailing` | 不假设对称 |
| 给折痕预留一个「避免区」 | 定义一个 `FoldAvoidance` 环境值，27.0 先恒为 `nil`；27.1 到位后只改这一处 |
| 不在 `fullScreenCover` 里假设全屏尺寸 | 编辑器已经这么做了（屏幕高度用于键盘判定），要改成用几何尺寸 |

**不要在 27.0 上提前用**：`ArrangementView` / `UIArrangementViewController` /
`onHingeChange` / `reservedRegion` 都是 iOS 27.1 的 API（已在 Xcode 27.0 SDK 中确认不存在）。
等 SDK 上线再接，本方案的 `AdaptiveLayout` 是它的超集，接的时候不用改版面。

---

## 五、改到现有代码上：改动清单

### 5.1 新增：`Views/Components/AdaptiveLayout.swift`

一个环境值 + 一个容器视图，把 §2 的规则变成代码（**只这一处判定宽度**）：

```swift
enum LayoutTier { case compact, medium, wide }

struct AdaptiveLayout {           // EnvironmentValue
    var size: CGSize
    var tier: LayoutTier          // <700 / 700..<1000 / ≥1000
    var safeLeading: CGFloat      // 左右分别给（横屏时 leading 往往非 0）
    var safeTrailing: CGFloat
    var safeTop: CGFloat
    var safeBottom: CGFloat

    /// 手机横屏：系统把导航换成左侧竖排胶囊，内容要让出的左边界
    var contentInset: CGFloat     // = safeLeading（胶囊右边）+ 12
    var gridInset: CGFloat        // 月格/列表左边界，比 contentInset 再多一点余量
    var headInset: CGFloat        // 页面标题行左边界（整行避开系统硬件竖带）

    var splitsMasterDetail: Bool { size.width >= 700 }   // 首页（手机横屏）
    var splitsDashboard: Bool    { size.width >= 900 }
    var splitsSearch: Bool       { size.width >= 800 }
    var cardColumns: Int         { size.width >= 1000 ? 3 : size.width >= 680 ? 2 : 1 }
    var masterWidth: CGFloat     { min(340, (size.width - gridInset - 18) * 0.46) }
    /// 正文列宽上限：宽屏必须限宽，否则一行 100+ 字。
    /// 返回的是正文列本身，页面内边距（左右各 16）加在它外面。
    func contentColumn(_ max: CGFloat = 660) -> CGFloat {
        min(max, size.width - 2 * pagePadding)
    }
}
```

**实现时不要把这些写成常量**：`contentInset / gridInset / headInset` 要从
`safeAreaInsets` 派生（横屏时 `leading` 就是导航胶囊那一条），这样 Duo 的折痕、
左右不对称的安全区、未来的 `reservedRegion` 都能接上。设计稿里的 100 / 152 是
iPhone 18 Pro 横屏实测出来的结果，不是应写死的值。

`RootView` 用一层 `GeometryReader` 读尺寸（不用 `UIScreen`），下发给整棵树：

```swift
GeometryReader { geo in
    TabView(selection: activeTab) { … }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.adaptiveLayout, AdaptiveLayout(size: geo.size, …))
}
```

### 5.2 现在这套代码为什么会在横屏重叠（三个具体原因）

改之前先确认病因，避免改完还留着一个：

1. **`HomeView.calendarArea(size:)` 用高度反推格高**：
   `h = max(320, size.height - 64)`，横屏手机 402pt 高 → `h = 338`；
   `CalendarLayout.monthCellH` 再算 `(338 − 72 − 30) / 6 ≈ 39pt`，而 `dayFont` 写死 20pt、
   `lunarFont` 11pt —— **39pt 里要塞 20 + 11 + 圆点**，必然重叠。
   这不是某一处写错，是「格子高度由可用高度算、字号却写死」的结构问题。
2. **`Screen.size` 的兜底是 390 × 844**：任何在场景就绪前取尺寸的代码都会拿到手机竖屏的
   数字；`UIRequiresFullScreen` 时代这没事，现在 iPad 多窗口 / Duo 下就是错的。
3. **没有分栏概念**：所有页面都假设「屏幕宽度 = 内容宽度」，宽屏只会把内容拉长；
   而 `TabBarClearance` 只在底部留白，横屏浮条在顶部时内容会钻到它下面。

对应的三条改动就是 §2 的全部：**格子尺寸与字号一起随可用空间走**、**宽度只从几何读**、
**超过阈值就分栏**。

### 5.3 逐文件

| 文件 | 改动 |
|---|---|
| `Views/RootView.swift` | `TabView` 加 `.sidebarAdaptable`；注入 `AdaptiveLayout`；`fullScreenCover` 里同样注入 |
| `Views/Components/Components.swift` | `Screen.size/height` 降级为「仅编辑器键盘判定」内部使用（或改成从几何读）；`TabBarClearance` 在宽档且无 tab bar 时返回 0，并补一个顶部留白（横屏浮条在顶部） |
| `Views/Home/HomeView.swift` | 拆成 `HomeLayout`（判定档位）+ `CalendarPane` + `DayPane`（复用现有 `DayContentView`）。**竖屏保持 `mode/zoom/expand` 三个 morph 状态与 `YearPageView` 不变**；只在横屏走分栏分支，不引入新的年份入口 |
| `Views/Home/CalendarLayout.swift` | 新增 `density(areaH:)` 返回 `.month(lunar:)` / `.month` / `.weekStrip`（**只在横屏/高度不足时降级**；竖屏仍按现有 `monthCellH`）|
| `Views/Home/CalendarGrids.swift` | `MonthCanvas` 支持 `rowOnly`（周条）绘制；`weekdayFontSize` 上限随格子宽度走 |
| `Views/Home/DayContentView.swift` | 宽档时限宽 660 并居中；卡片流两列交给外层 `HStack`，不在卡内做 |
| `Views/Home/MorphViews.swift` | **保留**（竖屏 morph 要用）。横屏分支不创建它们即可 |
| `Views/Footprint/FootprintView.swift` | 按 `splitsDashboard` 分栏；图表卡 `minHeight 180` |
| `Views/Search/SearchView.swift` | 按 `splitsSearch` 分栏；新增右栏预览（复用 `HighlightedText` + `DiaryPartsView` 只读渲染）；**补一行「当前关键词」栏**（`activeFilterItems` 里 `kind == .keyword` 的那些，画成可单独点掉的胶囊）—— 这是现有实现的缺口，竖屏也缺 |
| `Views/Settings/SettingsView.swift` | `LazyVGrid`（`alignment: .top`），列数取 `cardColumns`；**卡片保持自然高度，不要 `Grid` 等高** |
| `Views/Diary/DiaryPageView.swift` | 阅读列限宽 660；编辑列限宽 620；宽屏格式栏竖排贴右 |
| `Services/L10n.swift` + `Localizable.xcstrings` | 新增：`home_year_month_picker`、`a11y_prev_year`、`a11y_next_year`、`search_preview_hint`、`read_segments_index`；删除随年历一起下线的键 |
| `README.md` / `docs/design-system.md` | 补「自适应版面」一节，指向本文 |

### 5.4 实施进度

| 步骤 | 状态 |
|---|---|
| 1. `AdaptiveLayout` + `.sidebarAdaptable` | ✅ 完成 |
| 2. 首页横屏分栏（`MonthPane` / `DayPane`） | ✅ 完成 |
| 3. 横屏日历密度降级（月格 → 周条） | ✅ 完成 |
| 4. 横屏翻月 | ✅ 完成（上下滑 `DragPagePager` + 逐页 `.clipped()`） |
| 5. 足迹 / 搜索 / 设置横屏版面 | ✅ 完成 |
| 6. 搜索「当前关键词」栏（补齐原有缺口） | ✅ 完成 |
| 7. 日记页限宽 + 竖向格式栏 | ✅ 完成 |
| 8. Duo 预留（安全区左右分离，禁用 `UIScreen` 判定） | ✅ 完成（`AdaptiveLayout` 只从几何/场景读） |
| 9. 回归测试 | ✅ `AdaptiveLayoutTests`（只测日记列宽）+ `LandscapeLayoutUITests`（3 例）|

**实现中陆续修掉的 bug**（都是用户先发现的）：

1. **竖屏出现两个「今天」/ 两个年份入口** —— `MonthPane` 在竖屏 morph 月视图里也画了
   「今天」胶囊，而头部 `InfoCapsule` 本来就有。现在竖屏与横屏都只保留一个入口。
2. **横屏两栏留白过大** —— 原来两栏各自限宽，屏幕没用满。改成月历取可用宽的 52%、
   右栏吃满剩余，右栏内再限宽 560pt 居中。
3. **横屏点击日期后月历位移** —— 右栏没有固定宽度，内容变化会带动布局。现在两栏都是
   固定宽度（`HStack` 里左栏 `.frame(width:)`、右栏 `.frame(width:)`），并加了
   `LandscapeLayoutUITests.testTappingDayKeepsPaneWidthsStable` 守住。
4. **横屏月历不能滑** —— 之前只换了布局，没接翻月手势。现在用**上下滑**翻月
   （与竖屏同方向，横屏不引入第二套手势），并把相邻月裁掉。
5. **横屏年份按钮点了就消失** —— 那个胶囊只有外观没有动作；现在接上 `showYearPage()`，
   并把年份入口挪到**右栏标题行**（左栏让给日期格子），避免与头部 `InfoCapsule` 重复。
6. **横屏只剩一行日期**（最隐蔽的一个）—— `CalendarLayout.weeks()` 固定返回 6 行，
   月末那行常常整天不属于本月，于是密度判定把「5 行放得下」误判成「6 行放不下」，
   整块降级成周条。加了 `CalendarLayout.displayedWeeks(inMonth:ws:)` 去掉空尾行，
   `CalendarDensity.resolve` 也改成按**行数 + 每行高度**判断；同时把横屏标题区
   从 112pt 压到 32pt（年份并入右栏标题行、月标题一行）。
7. **竖屏「月→年」morph 月份数字跳一下** —— 年历页与 morph 起点各自算了一遍迷你月
   参数（字号 11 vs 11、行高、间距），过渡到一半会突变。现在统一走
   `CalendarLayout.miniMetrics(in:)`；并把 morph 里的 `MonthBigTitle` 放进固定高度的
   `ZStack`，字号生长不再推动下面的星期栏与网格。
8. **四屏宽度不统一** —— 每屏各写一套 `padding(.leading, 16 + contentInset)`。现在统一走
   `.adaptivePagePadding()`。
   > **2026-09-17 修正**：`contentInset`（横屏 62）**不能**再加进去 —— 几何原点已经在安全区内，
   > 第一版加上之后，横屏页头在 x = 78、卡片却在 x = 140，左半屏白掉一条 62pt。
   > 现在 `leadingPagePadding = trailingPagePadding = 16`，四屏内容与页头同一条左边线。
   > 首页的横屏分栏与 `MonthPane` 也犯过同一个错，一并修掉（§3.1.1）。

**年历的字号与间距**（按用户要求微调）：月间距 10 → 6，迷你日期字号改为按格宽推导
（`miniDayFont(cellW:cellH:)`，3 列下约 12–14pt，原为固定 11pt），迷你月标题 13 → 15pt，
选中圆直径 `contentH + 14`（并且仍被格宽/格高夹住，不会与相邻日期重叠）。

### 5.5 实施顺序（原始计划，保留备查）

1. **`AdaptiveLayout` + `.sidebarAdaptable`**：先只做外壳，不改任何页面 —— iPad/Mac 上
   导航形态立刻正确，页面还是旧的（此时横屏仍会重叠）。
2. **首页横屏分栏**（本方案价值最大的一处）：左边界让到 `gridInset`，`CalendarPane` /
   `DayPane` 并排；**竖屏路径一行代码不动**。
3. **横屏日历密度**：高度不足时月格 → 周条。竖屏的年历/整屏 morph 保持原样。
4. **足迹 / 搜索 / 设置**三屏宽档版面。
5. **日记页**限宽与竖向格式栏。
6. **Duo 预留**：安全区左右分离 + `FoldAvoidance` 钩子 + 删掉基于 `UIScreen` 的判定。
7. **回归**：`MorphPerfUITests` 重写为「密度切换」用例；补 iPad 横屏与 320pt 分屏的 UI 用例。

### 5.6 验收口径

- 在 **402×874 / 874×402 / 744×1133 / 1032×1376 / 1376×1032 / 320×1032 / 1432×900**
  七种尺寸下，五个页面都无重叠、无截断、无横向溢出（`ScrollView(.horizontal)` 除外）。
- 已用真机（模拟器）截图核对：竖屏单入口、横屏首页左右分栏 + 左栏 390pt、
  横屏足迹图表吃满宽度、横屏设置两列卡片、横屏搜索条件一行。
- 最大辅助功能字号（AX5）下，日历格子、统计行、设置行、编辑格式栏仍然可用
  （沿用 `docs/design-system.md` §6 的溢出规则）。
- 分屏 1/3（320pt）不出现分栏；窗口从 1432 拖到 320 的过程中，界面按档位逐级回落，
  不出现「半栏」。

---

## 六、我对原始想法的调整（以及为什么）

| 原始想法 | 处理 | 理由 |
|---|---|---|
| 首页固定左月历、右日记 | **采纳** | 这是横屏手机唯一可行的排法：402pt 高塞不下「月格 + 日期行 + 内容」 |
| 不再提供年历/周历切换 | **修订：竖屏一律不动** | 竖屏保留年历/周历与 morph；**横屏不提供年份切换**（上下滑切月即可），周条只在高度不足时作为**密度降级**出现 |
| 月历上下滑动切换月份 | **采纳** | 竖滑翻月在窄栏里手势冲突最小 |
| 左上角年份弹滚轴切年 | **采纳** | 年滚轴 + 月份网格，宽屏 popover、窄屏 sheet（见 `year-picker.png`） |
| 右上角回到今日 | **采纳** | 所有档位位置一致 |
| 足迹：左图表、右统计 | **调整** | 统计只有 5 个数字，独占一栏太空。改为「左统计+图表 / 右地点清单」，按「两件事」而不是「两种控件」分栏 |
| 搜索：左搜索、右结果 | **调整** | 补第三区「预览」，否则每条结果都要进出日记页 |
| 设置：卡片式 + 左右两页 | **采纳为「卡片 + 按宽度分 1/2/3 列」** | 设置项之间没有主从关系，硬做「左右两页」会把顺序读成两列语义；按列流动更稳 |
| 日记页卡片化左右双列交叉 | **不采纳，改为限宽单栏** | 正文分两列会破坏阅读顺序（眼睛要在两列间来回跳），长句尤其难受；Apple 自己的备忘录/图书/News 在 Mac 上也是单栏限宽。宽屏真正该换来的是**两侧留白 + 片段索引 + 介质并排** |
| 「一套设计兼顾手机和平板」 | **修订：手机端先做完，宽屏单独设计** | 手机端竖屏 / 横屏共用一套版面（只按宽度分档）；iPad / Mac **另做三栏版面**，因为宽屏的目标不是「排得下」而是「用宽度换密度」。两者共用同一套设计令牌与卡片组件 |

---

## 七、设计稿怎么用

```bash
# 交互浏览
open docs/design/landscape/phone.html   # 手机端（竖屏 / 横屏）
open docs/design/landscape/wide.html    # iPad / Mac 三栏（先行版）
open docs/design/landscape/gallery.html # 全部 13 张总览

# 重新导出 PNG（2×）
node tools/capture_design_mockups.mjs              # 全部
node tools/capture_design_mockups.mjs --phone      # 只手机端
node tools/capture_design_mockups.mjs ph-home      # 只 id 含 ph-home 的
```

设计稿的**唯一定义**：

| 文件 | 内容 |
|---|---|
| `devices.js` | 参考设备尺寸 + **手机横屏的系统占位常量**（`PHONE_CHROME`，来自真机实测） |
| `engine.js` | 图标、文案数据、通用绘制函数、`layoutFor()` 版面判定、渲染入口 |
| `frames-phone.js` | 手机**横屏**每一张稿 |
| `frames-phone-portrait.js` | 手机**竖屏**每一张稿（1:1 复刻当前实现） |
| `frames-wide.js` | iPad / Mac 三栏（先行版） |
| `mockup.css` | 设计令牌（与 `Assets.xcassets`、`DesignSystem.swift` 一一对应） |

`layoutFor()` 就是 §2.1 那张表的代码版 —— 实现 `AdaptiveLayout` 时直接对照，两边数
不应该有第二个来源。

**手机端（已定稿）**

**手机竖屏（1:1 复刻当前实现）**

| 稿件 | 文件 |
|---|---|
| 首页 · 月视图 | `screens/ph-home-portrait.png` |
| 首页 · 年历（morph 目标） | `screens/ph-home-year.png` |
| 首页 · 周视图（morph 目标） | `screens/ph-home-week.png` |
| 足迹 / 搜索 / 设置 | `screens/ph-footprint-portrait.png` · `ph-search-portrait.png` · `ph-settings-portrait.png` |

**手机横屏（本次设计）**

| 稿件 | 文件 |
|---|---|
| 首页 · 手机横屏（重点） | `screens/ph-home-landscape.png` |
| 首页 · 手机横屏（重点） | `screens/ph-home-landscape.png` |
| 首页 · 手机横屏 · 高度不足 | `screens/ph-home-landscape-week.png` |
| 足迹 · 手机横屏 | `screens/ph-footprint-landscape.png` |
| 搜索 · 手机横屏 | `screens/ph-search-landscape.png` |
| 设置 · 手机横屏 | `screens/ph-settings-landscape.png` |
| 日记阅读 · 手机横屏 | `screens/ph-read-landscape.png` |
| 年月滚轴（仅竖屏备选） | `screens/ph-yearmonth-overlay.png` |

**iPad / Mac（三栏先行版）**

| 稿件 | 文件 |
|---|---|
| 首页 / 足迹 / 搜索 / 设置 | `screens/wide-home.png` · `wide-footprint.png` · `wide-search.png` · `wide-settings.png` |
| iPhone Duo 内屏 | `screens/wide-duo-inner.png` |

> 设计稿是**可执行的规范**：`mockups.js` 里的 `layoutFor()` 就是 §2.1 那张表的代码版，
> 实现 `AdaptiveLayout` 时可以直接对照着写，两边数不应该有第二个来源。
