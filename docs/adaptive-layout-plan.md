# 手机自适应布局方案（竖屏 / 横屏）

环境：Xcode 27.0 / iOS 27.0 SDK · 目标：iPhone（竖屏 + 横屏）
设计稿：`docs/design/landscape/phone.html`（可交互）· `screens/ph-*.png`

本文回答一件事：**同一套代码，怎么在手机竖屏和手机横屏上都排得好看**。

> **当前状态**：手机端**已实现**（首页横屏分栏、日历密度降级、横屏上下滑动翻月、
> 足迹/搜索/设置/阅读页的横屏版面、关键词栏），并有 `AdaptiveLayoutTests`、
> `LandscapeLayoutUITests` 与 `MorphPerfUITests` 守住。
>
> 三个已确认的前提：
> 1. **竖屏交互完全不动** —— 年历 / 月历 / 周历三态与之间的 morph 动画原样保留。
> 2. **横屏不提供年份切换** —— 整块头部与年份胶囊都不出现，只上下滑切月；横屏不引入
>    第二套交互，以免和竖屏的年历 morph 打架。
> 3. **横屏左侧安全区 62pt 已经由几何原点承担** —— 实测 `safeAreaInsets`：
>    竖屏 `T62 L0 B34 R0`、横屏 `T0 L62 B20 R62`，几何原点已在安全区内，页面只加自己的
>    16pt 边距；**不要再减一次**，否则就是重复避让。

---

## 一、结论摘要

1. **只有一条判定规则**：版面按「当前可用宽度/高度」判定，不看设备型号、不看
   `UIDevice.idiom`、不看 `UIDevice.orientation`、不读 `UIScreen.main`
   （这条直接来自 Apple 的 Duo 适配指南：Duo 展开后**仍然是 iPhone**，但宽高都是
   regular；按型号分支的代码在它上面必然错）。
2. **导航用系统默认的底部浮条**：`TabView` 不加额外样式，就是 iPhone 原生的底部浮条。
   **不自己写第二套导航**。
3. **正文永远单栏**：阅读页限制在 ≤660pt（约 60–75 字符）并居中。用户提的
   「日记页卡片左右双列交叉排列」在阅读场景会破坏阅读顺序，不采用（理由见 §6）。
4. **砍掉两级整屏层级**：「年历」整屏视图与「月↔周整屏 morph」在横屏里是净负担。
   年月选择收敛到左上角入口，横屏只上下滑切月；月历密度按可用高度自动决定
   （月格 ↔ 周条）。

---

## 二、自适应系统

### 2.1 唯一的判定规则：手机横屏且两栏都放得下 → 首页分栏

代码里只剩这一条判据（`AdaptiveLayout.splitsMasterDetail`）：

| 形态 | 可用宽度 | 导航形态 | 首页 |
|---|---|---|---|
| 手机竖屏 | 任何 | 底部浮条 | 年 / 月 / 周三态 morph，单栏 |
| 手机横屏 | ≥ 548.5pt 且 `width > height` | 底部浮条 | **左右分栏**：左月历 + 右选中日 |

阈值不是拍脑袋：**月历 7 列至少需要 260pt（每格 ~37pt）才有可用性，详情栏至少需要
240pt 才不至于每行只折 3–4 个字**，加上左右页边距 16×2 与栏间距 16.5，就是分栏的
下限 **548.5pt**。

> **这个下限的作用只是挡住「横屏但容器太窄」（分屏 / 折叠态）**，不是用来区分机型的。
> 早先写的是 `contentWidth >= 700`（按「月历 280 + 正文 320 + 边距」估的），结果
> iPhone SE 横屏只有 **667pt**（SE 没有刘海，左右安全区都是 0）被挡在门外：同一个
> 横屏排版，18 Pro（可用 750pt）左右分栏、SE 却只是把竖屏版面横向拉长 —— 两栏都
> 不好读。现在任何横屏 iPhone 都拿得到左右双列。

落到具体设备：

| 设备 / 形态 | 参考尺寸 (pt) | 可用内容宽 | 首页 |
|---|---|---|---|
| iPhone 18 Pro 竖屏 | 402 × 874 | 402 | 月历 + 下方日记（现状保留） |
| iPhone 18 Pro 横屏 | 874 × 402 | 750 | **左右分栏**（左月历 345 / 右日记 356.5） |
| iPhone SE 竖屏 | 375 × 667 | 375 | 单栏（与 18 Pro 竖屏同一套） |
| iPhone SE 横屏 | 667 × 375 | 667 | **左右分栏**（左月历 307 / 右日记 311.5） |
| iPhone Duo 内屏 | ≈664 × 750 | 664 | 单栏（宽但不矮，与手机竖屏同一套） |

> 关键点：**不按机型分支**。只看可用宽度/高度与安全区，所以 Duo 这类还没上市的设备
> 不需要任何专用代码；SE 能分栏也是同一条规则推出来的结果，不是给它开的后门。

### 2.2 导航：系统默认的底部浮条，app 只负责避让

**真机实测**（iPhone 18 Pro / iOS 27，UI 测试读 accessibility frame）：

| 形态 | 系统导航的实际位置 |
|---|---|
| 竖屏 | 底部浮条：`app.tabBars` frame `(0, 791, 402, 83)`，按钮 54pt 高 |
| 横屏 | **同样在底部居中**：`app.tabBars` frame `(0, 338, 874, 64)`，按钮 36pt 高；同时 `safeArea.leading = 62` |

所以首页横屏除了避让左侧 `leading` 之外，**还要在底部为浮条留出空间**，否则两栏的
最后一行会被压住，见 §3.1.1。

横向的顶部/底部浮条（早期设计稿里的做法）是错的：系统不会那样排，猜出来的位置在真机上
会和内容打架。

**为什么不用 `NavigationSplitView` 当外壳**：那是「列表 → 详情」的容器，会把 4 个 tab
降级成一层列表，还会和页内已有的主从结构（日历→日记、结果→预览）套成两层嵌套导航。
页内分栏用普通 `HStack` 就够，不需要第二个导航容器。

**我们能做、也该做的只有一件事**：让内容避开左侧 `safeArea.leading`（横屏 62pt）。
而几何原点已经在安全区内，所以**四屏只需要加自己的 16pt 页边距**
（`.adaptivePagePadding()`，见 §5.2 的关键约定 1）；`AdaptiveLayout.contentWidth` 只用于
「可用内容宽度」这类计算，**不要**再叠进页边距，也不要 `MonthPane` / 分栏内各减一遍
（见 §3.1.1）。

### 2.3 页内分栏的两条约束（只用于首页横屏）

1. **分栏用 `HStack` + 固定宽度的主栏**，详情栏 `frame(maxWidth:.infinity)`。
   主栏不需要拖动分隔条 —— 它的宽度由内容决定（月历 7 列），不是用户偏好。
2. **详情栏里的文字列必须限宽**（阅读 660 / 编辑 620）。否则屏宽一宽，正文就会被
   拉成一行 100+ 个字。

---

## 三、逐屏版面

设计图见 `docs/design/landscape/screens/`，下列文件名即对应图片。

### 3.1 首页 `ph-home-*.png`

| 形态 | 版面 |
|---|---|
| 竖屏（402pt） | **保持现状**：`‹ 年月` 胶囊 +「今天」→ 72pt 标题槽（32pt 月标题）→ 30pt 星期栏 → 六行月格（有日记＝下划线、今天＝圆环、选中＝实心圆、未来 35%）；点日期 morph 到周视图、点年月胶囊 morph 到年历。设计稿里这三屏（`ph-home-portrait` / `ph-home-week` / `ph-home-year`）是**按实现 1:1 复刻**的对照基准 |
| 横屏（18 Pro 874 × 402） | 系统占位已含在安全区里 → **可用 750 × 382**；页面只再加 16pt 边距；**左栏月历 345pt + 右栏日记 356.5pt**；左栏上下翻月 |
| 横屏（SE 667 × 375） | 同一条规则推出来的结果：SE 没有刘海，**整屏 667 都是可用宽度**；**左栏月历 307pt + 右栏日记 311.5pt**；因为屏矮，密度会自动隐藏农历行，六行日期每格约 40pt |
| 横屏・高度不足 | 左栏降级为**周条**（一行 7 天，横向翻周），右栏高度不变 |
| 横屏・年份 | **不提供年份切换**：整块头部隐藏、右栏标题行也**没有年份胶囊**；上下滑跨月时自然跨年 |
| 横屏・回到今日 | 「今天」放在**右栏标题行**（左栏整行留给月标题与日期格子） |

**日历密度按高度自适应**，这是替代原来「月↔周整屏 morph」的关键：

```
可用高度 ≥ 6×60 + 标题        → 月格（显示农历；横屏一般到不了）
可用高度 ≥ 6×38 + 标题        → 月格（隐藏农历行）
否则                          → 周条（1 行，横向翻周）
```

隐藏农历那一档的下限是 **38pt**（不是 44）：44pt 是「20pt 日号 **+ 11pt 农历** + 选中圆」
需要的高度，既然农历行本来就不画，六行只需要 ~40pt 一格。若这里坚持 44，
**SE 横屏（375pt 高）会被降级成周条** —— 左右分栏的左栏只剩一行日期，横屏首页等于
没有月历。40pt 的格子放 ~14pt 日号 + ~32pt 选中圆仍然宽裕（日号字号本来就由格高推导）。

横屏手机 18 Pro 402pt 高，扣掉顶部 8pt、底部给系统浮条让出的 64pt，日历区 330pt；
标题槽 34 + 星期栏 26 = 60，剩 270 给 5–6 行 → 每格 45–54pt（日号 15–18pt）。
SE 横屏 375pt 高，日历区 303pt，剩 243 给 6 行 → 每格 40pt（日号 ~14pt），仍然可点。
如果连 38pt 都放不下（键盘弹起、Duo 折成一半），才自动变周条。

**年月切换（仅竖屏）**：竖屏**保持现在的整屏年历 + 缩放 morph**，不加新入口、不改形状。
- 横屏**不提供**年份切换（只上下滑切月），也没有任何可以点进年历的按钮。

**morph 终点即真实排版**：`MonthPane` 的标题槽 / 星期栏高度（竖屏 `bigTitleH(72)` +
`weekdayHeaderH(30)`，横屏 34 + 26）**必须**与 morph 里的槽位用同一组常量，
否则动画收尾、真实图层接上时会整体跳一下；年历迷你月的日期字号也必须由
`CalendarLayout.miniMetrics` 统一提供 —— 年历页与 morph 起点各算一遍时，收尾会出现
字号跳变。

**回到今日**：竖屏在右上角（现状不变）；横屏在右栏标题行右侧，位置固定。

### 3.1.1 手机横屏的系统占位（实测）

18 Pro 横屏（可用 750 × 402）：

```
x:  0 ───── 62 ─ 78 ─────────── 423 ─ 439 ─────────────── 795.5 ─ 812 ─ 874
    │ 安全区 │16│   左栏月历 345   │ 16 │    右栏日记 356.5       │16│安全区
y:  0 ───────────────────────────────────────────────────────────────
    │ 8pt 顶部留白                                                      │
    │  月标题 34 → 星期栏 26 → 5/6 行日期（每格 45–54）                   │
    │                                                                   │
    │        ┌─────────────────────────┐ ← 系统浮条：y 338–402，居中    │
    │        │  日记  足迹  搜索  设置   │    会盖住两栏的最后一行        │
    ────────────────────────────────────────────────────────────────── 402
```

SE 横屏（可用 667 × 375，无安全区；浮条一样高、一样贴底）：

```
x:  0 ─ 16 ──────────── 323 ─ 339.5 ─────────── 651 ─ 667
    │  16│   左栏月历 307    │ 16.5 │   右栏日记 311.5  │16│
y:  0 ───────────────────────────────────────────────────────
    │ 8pt 顶部留白                                             │
    │  月标题 34 → 星期栏 26 → 6 行日期（每格 40，隐藏农历）      │
    │                                                          │
    │      ┌───────────────────────┐ ← 系统浮条：y 311–375，居中 │
    │      │ 日记  足迹  搜索  设置  │    高度同样是 64pt          │
    ──────────────────────────────────────────────────────── 375
```

- 实测 18 Pro `safeAreaInsets`：竖屏 `T62 L0 B34 R0`、横屏 `T0 L62 B20 R62`；
  横屏**可用内容宽度就是 750pt**（874 − 62 − 62），几何原点已经在安全区内。
- 实测 `app.tabBars` frame：18 Pro 横屏 `(0, 338, 874, 64)`、**SE 横屏
  `(0, 311, 667, 64)`** —— 浮条由系统绘制，**同一方向上高度与机型无关**
  （竖屏 83 / 横屏 64），两条都紧贴屏幕底边。
- 所以页面**只需要加自己的 16pt 边距**，日历紧贴 `leading = 62 + 16 = 78`
  （SE 是 `0 + 16 = 16`）起。**不要**再减一次 `safeArea.leading`：重复避让会把日历
  推到 x ≈ 222，左半屏白白空着 —— 这就是「横屏没有充分利用屏幕、左右避让过多」的根因。
- 顶部没有安全区（`T0`），标题行由页面自己留 8pt；底部要让出的是**浮条自身的高度**
  （`AdaptiveLayout.tabBarClearance`，横屏 64pt）。
  **不要**写成 `bottomInset + 44`：那个式子只在有 home indicator 的机型上
  （横屏 `bottomInset = 20`）碰巧等于 64，SE 横屏 `bottomInset = 0` 时只让出 44pt，
  最后一行日期会被浮条压住 20pt。
- 导航形态交给系统（`TabView` 默认样式），app 不自己画第二条导航；
  宽度/高度都从几何与 `safeAreaInsets` 派生（只有浮条高度是按方向取的实测常量，
  因为它由系统绘制、无法从安全区推出），Duo 折痕、左右不对称安全区、未来 27.1 的
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

> 横屏的**真实可用宽度是 750pt**（874 − 62 − 62），达不到 900pt 的分栏阈值，所以
> **做不了**左右分栏；正确做法是这里写的：不分栏，但把两个块**并排**放进同一列里。

### 3.3 搜索 `ph-search-landscape.png`

- 手机横屏（可用 750pt）：**条件压成一行** —— 搜索框一行，下面
  「时间范围 | 地点」两组筛选并排成一行（省下约 60pt 竖高留给结果）；
  **结果保持与竖屏一致的单栏纵向列表** —— 横屏每行更长、摘要多显示半行，扫读更快。
- **关键词栏**：搜索框下方一行「关键词」，每个生效中的关键词是一个可单独点掉的胶囊
  （多个关键词时一眼看清在搜什么），右侧是「清除全部条件」。竖屏与横屏共用。

> 多关键词的处理沿用实现里已有的 `activeFilterItems`（`SearchFilterItem`：keyword /
> time / location 三类），不需要新模型 —— 只是把「关键词」这一类单独画成一行展示。

### 3.4 设置 `ph-settings-landscape.png`

卡片式，**竖屏与横屏共用单列**。卡片顺序不变，每张卡自我完整
（通用 / 规则 / 提醒 / 数据 / 关于）。设置没有主从关系，所以不做「左列表右详情」。

### 3.5 日记页 `ph-read-landscape.png`

- **阅读**：正文单栏限宽 **660pt** 居中（手机竖屏就是屏宽 − 左右各 16 的页边距）。
  大标题 28 / 小标题 22 / 正文 17 / 引用 15 不变。
  图片与地图可以与正文并排 —— 那是「并排的介质」，不是「并排的文字」。
- **编辑**：正文列宽 **≤620pt**；横屏键盘弹起时把格式栏改成**竖向贴右侧**，
  窄屏退回键盘上方的横向玻璃条。位置规则沿用 `docs/design-system.md` §5：
  键盘弹起时贴键盘上方 8pt，收起时贴 Home Indicator 上方。

---

## 四、iPhone Duo

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
| 删掉 `Screen.size` / `Screen.height` 作为布局依据的用法 | 保留 `Screen.safeAreaBottom`（底部安全区，编辑器要用），它从当前场景读、允许为 0 |
| 所有分栏判定改用实测宽度 | 见 §5.1 的 `AdaptiveLayout` |
| 左右 padding 分别取 `safeAreaInsets.leading/trailing` | 不假设对称 |
| 给折痕预留一个「避免区」 | 定义一个 `FoldAvoidance` 环境值，27.0 先恒为 `nil`；27.1 到位后只改这一处 |
| 不在 `fullScreenCover` 里假设全屏尺寸 | 编辑器已改成用几何尺寸 |

**不要在 27.0 上提前用**：`ArrangementView` / `UIArrangementViewController` /
`onHingeChange` / `reservedRegion` 都是 iOS 27.1 的 API（已在 Xcode 27.0 SDK 中确认不存在）。
等 SDK 上线再接，本方案的 `AdaptiveLayout` 是它的超集，接的时候不用改版面。

---

## 五、代码落点

### 5.1 `Views/Components/AdaptiveLayout.swift`

一个环境值 + 一个容器视图，把 §2 的规则变成代码（**只这一处判定宽度**）：

```swift
struct AdaptiveLayout {           // EnvironmentValue
    var size: CGSize
    var safeArea: EdgeInsets      // 四边分别给（横屏时 leading 往往非 0）

    /// 底部为系统浮条 / 指示条预留
    var bottomInset: CGFloat

    /// 可用内容宽度：扣掉左右安全区（横屏左侧 62pt 的导航胶囊）
    var contentWidth: CGFloat

    /// 首页（手机横屏）：横屏 + 两栏都放得下 → 左右分栏。
    /// 下限 548.5 = 主栏 260 + 详情栏 240 + 页边距 16×2 + 栏间距 16.5
    var splitsMasterDetail: Bool {
        size.width > size.height && contentWidth >= Self.minSplitContentWidth
    }
    /// 竖屏：保持单栏
    var isPortrait: Bool { size.height >= size.width }

    /// 分栏两栏的宽度：主栏按容器宽的 46%（夹在 260…440），但必须给详情栏
    /// 留够 240；两栏之和 + 页边距 + 分隔线正好铺满容器，不会溢出。
    func splitColumns(containerWidth: CGFloat) -> (master: CGFloat, detail: CGFloat)

    /// 分栏两栏的高度：容器高 − 顶部 8 − 底部浮条（`tabBarClearance`）。
    func splitPaneHeight(containerHeight: CGFloat) -> CGFloat

    /// 底部浮条要占的高度（内容忽略底部安全区时用）：竖屏 83 / 横屏 64。
    /// **不是** `bottomInset + 44` —— 那个式子只在有 home indicator 的机型上碰巧对，
    /// SE 横屏 `bottomInset = 0` 时会少让 20pt。
    var tabBarClearance: CGFloat

    /// 正文列宽上限：宽屏必须限宽，否则一行 100+ 字。
    /// 返回的是正文列本身，页面内边距（左右各 16）加在它外面。
    func contentColumn(_ max: CGFloat = 660) -> CGFloat {
        min(max, max(240, size.width - 2 * pagePadding))
    }
}
```

**实现时不要把这些写成常量**：宽度/高度要从几何与 `safeAreaInsets` 派生（横屏时
`leading` 就是导航胶囊那一条），这样 Duo 的折痕、左右不对称的安全区、未来的
`reservedRegion` 都能接上。几何由 `RootView` 的 `.adaptiveLayoutReader()` 读一次并下发，
页面内部不要再各自读 `UIScreen.main`。

### 5.2 逐文件

| 文件 | 改动 |
|---|---|
| `Views/RootView.swift` | 注入 `AdaptiveLayout`；`fullScreenCover` 里同样注入 |
| `Views/Components/Components.swift` | `Screen.size/height` 降级为「仅编辑器键盘判定」内部使用；`TabBarClearance` 在横屏浮条悬底时留出高度 |
| `Views/Home/HomeView.swift` | 拆成判定 + `MonthPane` + `DayPane`（复用现有 `DayContentView`）。**竖屏保持 `mode/zoom/expand` 三个 morph 状态与 `YearPageView` 不变**；只在横屏走分栏分支，不引入新的年份入口 |
| `Views/Home/CalendarLayout.swift` | `density(areaH:)` 返回 `.month(lunar:)` / `.month` / `.weekStrip`（**只在横屏/高度不足时降级**；竖屏仍按现有 `monthCellH`）|
| `Views/Home/CalendarGrids.swift` | `MonthCanvas` 支持 `rowOnly`（周条）绘制；`weekdayFontSize` 上限随格子宽度走 |
| `Views/Home/DayContentView.swift` | 正文明细列限宽 660 并居中 |
| `Views/Home/MorphViews.swift` | **保留**（竖屏 morph 要用）。横屏分支不创建它们即可 |
| `Views/Footprint/FootprintView.swift` | 竖屏单栏；手机横屏把「趋势图 / 地点清单」并排 |
| `Views/Search/SearchView.swift` | 手机横屏把「时间 / 地点」两组条件并排；「当前关键词」栏（`activeFilterItems` 里 `kind == .keyword` 的那些，画成可单独点掉的胶囊）|
| `Views/Settings/SettingsView.swift` | 竖屏 / 横屏共用单列卡片 |
| `Views/Diary/DiaryPageView.swift` | 阅读列限宽 660；编辑列限宽 620；横屏格式栏竖排贴右；顶栏悬浮在正文之上 |
| `README.md` / `docs/design-system.md` | 补「自适应版面」一节，指向本文 |

四条关键约定（都踩过坑）：

1. **宽度只从几何读**：`AdaptivePagePadding` 的 `leading/trailing` 都是 16，
   不含安全区。四屏统一走 `.adaptivePagePadding()`，不要各写一套
   `padding(.leading, 16 + 安全区)` —— 横屏会把 62pt 再加一遍，页头在 x = 78、
   卡片却在 x = 140，左半屏白掉一条。
2. **分栏宽度固定**：`HStack` 里两栏都 `.frame(width:)`，右栏内容变化不会带动布局；
   右栏内再限宽居中。
3. **翻月与密度**：`CalendarLayout.displayedWeeks(inMonth:ws:)` 去掉空尾行后再判密度，
   否则「5 行放得下」会被误判成「6 行放不下」，整块降级成周条。
4. **窄栏里的 UIKit 视图必须自己实现 `sizeThatFits`**：`UIViewRepresentable` 默认按
   UIView 的 intrinsic size 排版，而正文用的 `FittedTextView` 在首次测量时
   `bounds.width = 0`，兜底值 **320pt** 比 SE 横屏右栏（311.5pt，扣掉页边距 20×2 与
   卡片内边距 12×2 只剩 ~247pt）还宽 —— 卡片于是比栏宽，外层
   `frame(maxWidth:.infinity)` 再把它居中，左侧压住月历、右侧被裁掉
   （实测正文右边界到过 807pt，整屏只有 667）。`ReadTextView.sizeThatFits` 返回
   「被提议的宽度 + 该宽度下的高度」即可。**空日记页看不出这个 bug**，
   回归由 `LandscapeLayoutUITests.testDayPaneWithDiaryFitsThePaneWidth` 守住
   （它先写一段长日记再转横屏量宽度）。

### 5.3 验收口径

- 在 **402×874 / 874×402 / 375×667 / 667×375 / 320×874** 五种尺寸下，五个页面都无
  重叠、无截断、无横向溢出（`ScrollView(.horizontal)` 除外）。
- 最大辅助功能字号（AX5）下，日历格子、统计行、设置行、编辑格式栏仍然可用
  （沿用 `docs/design-system.md` §6 的溢出规则）。
- **横屏 iPhone 一律分栏**（18 Pro 750pt、SE 667pt 都算），竖屏一律单栏；
  横屏但容器窄于 548.5pt（分屏 / 折叠态）时才退回单栏。
- 横屏两栏底部都不压系统浮条：18 Pro 日历区 330pt、SE 303pt。

---

## 六、我对原始想法的调整（以及为什么）

| 原始想法 | 处理 | 理由 |
|---|---|---|
| 首页固定左月历、右日记 | **采纳** | 这是横屏手机唯一可行的排法：402pt 高塞不下「月格 + 日期行 + 内容」 |
| 不再提供年历/周历切换 | **修订：竖屏一律不动** | 竖屏保留年历/周历与 morph；**横屏不提供年份切换**（上下滑切月即可），周条只在高度不足时作为**密度降级**出现 |
| 月历上下滑动切换月份 | **采纳** | 竖滑翻月在窄栏里手势冲突最小 |
| 右上角回到今日 | **采纳** | 竖屏在右上角，横屏在右栏标题行右侧 |
| 足迹：左图表、右统计 | **调整** | 统计只有 5 个数字，独占一栏太空。手机横屏改为「趋势图 / 地点清单」并排 |
| 搜索：左搜索、右结果 | **调整** | 手机横屏把条件压成一行、结果保持单栏 |
| 设置：卡片式 + 左右两页 | **手机端采纳为单列卡片** | 设置项之间没有主从关系，硬做「左右两页」会把顺序读成两列语义 |
| 日记页卡片化左右双列交叉 | **不采纳，改为限宽单栏** | 正文分两列会破坏阅读顺序（眼睛要在两列间来回跳），长句尤其难受；Apple 自己的备忘录/图书/News 也是单栏限宽 |
| 手机竖屏 / 横屏共用一套版面 | **采纳** | 只按宽度判定，两套形态共用同一套设计令牌与卡片组件 |

---

## 七、设计稿怎么用

```bash
# 交互浏览
open docs/design/landscape/phone.html    # 手机端（竖屏 / 横屏）
open docs/design/landscape/gallery.html  # 总览

# 重新导出 PNG（2×）
node tools/capture_design_mockups.mjs            # 全部
node tools/capture_design_mockups.mjs --phone    # 只手机端
node tools/capture_design_mockups.mjs ph-home    # 只导出 id 含 ph-home 的
```

设计稿的**唯一定义**：

| 文件 | 内容 |
|---|---|
| `devices.js` | 参考设备尺寸 + **手机横屏的系统占位常量**（`PHONE_CHROME`，来自真机实测） |
| `engine.js` | 图标、文案数据、通用绘制函数、`layoutFor()` 版面判定、渲染入口 |
| `frames-phone.js` | 手机**横屏**每一张稿 |
| `frames-phone-portrait.js` | 手机**竖屏**每一张稿（1:1 复刻当前实现） |
| `mockup.css` | 设计令牌（与 `Assets.xcassets`、`DesignSystem.swift` 一一对应） |

`layoutFor()` 里手机那部分就是 §2.1 那张表的代码版 —— 实现 `AdaptiveLayout` 时直接对照，
两边数不应该有第二个来源。

**手机竖屏（1:1 复刻当前实现）**

| 稿件 | 文件 |
|---|---|
| 首页 · 月视图 | `screens/ph-home-portrait.png` |
| 首页 · 年历（morph 目标） | `screens/ph-home-year.png` |
| 首页 · 周视图（morph 目标） | `screens/ph-home-week.png` |
| 足迹 / 搜索 / 设置 | `screens/ph-footprint-portrait.png` · `ph-search-portrait.png` · `ph-settings-portrait.png` |

**手机横屏**

| 稿件 | 文件 |
|---|---|
| 首页 · 手机横屏（重点） | `screens/ph-home-landscape.png` |
| 首页 · 手机横屏 · 高度不足 | `screens/ph-home-landscape-week.png` |
| 足迹 · 手机横屏 | `screens/ph-footprint-landscape.png` |
| 搜索 · 手机横屏 | `screens/ph-search-landscape.png` |
| 设置 · 手机横屏 | `screens/ph-settings-landscape.png` |
| 日记阅读 · 手机横屏 | `screens/ph-read-landscape.png` |

> 设计稿是**可执行的规范**：`engine.js` 里的 `layoutFor()` 手机那部分是 §2.1 的代码版，
> 实现 `AdaptiveLayout` 时可以直接对照。
