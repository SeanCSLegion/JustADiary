# 一页时光 · iOS 27.2 / iPhone Duo 适配记录与后续 TODO

> 状态：**P0 已实现**（2026-10-31；P1/P2 仍待确认）
>
> 基线环境（实测）：Xcode **27.2** (27B52)、iOS **27.2** SDK、iOS 27.1 模拟器
> runtime (24A94425)、macOS 27.2 (26B123)、Swift 6.4 工具链。
> 工程仍是 `IPHONEOS_DEPLOYMENT_TARGET = 27.0`、`SWIFT_VERSION = 5.0`；
> 27.1 才有的 Duo API 用 `@available` / `#available` 守住。
>
> 设备：用户已启动的 **iPhone Duo**（`iPhone19,4`，runtime 27.1）。
> 没有新建模拟器；测试过程中只重启过这一台。
>
> 相关文档：`docs/adaptive-layout-plan.md` §4（原文把 Duo 标为「之后要适配」）、
> `docs/design-system.md`（`FoldAvoidance` / `reservedRegions` 待做）、
> `docs/iOS27-upgrade-plan.md`（27.0 基线）。

> **2026-10-31 实现记录（P0）**
>
> - `AdaptiveLayout` 增加 `FoldRegion` / `SplitMetrics` / `verticalBarEdge` /
>   `isRegularWidth`；Reader 读 `GeometryProxy.reservedRegions`（27.1+，
>   `includeInactive`）和 `toolbarVerticalEdge`。
> - 窗口尺寸改用 key window bounds（修 50/50 分屏 / 可缩放窗口的错算）。
> - 半折横屏：折痕带变 gutter，左右两栏各留 8pt 安全边（实测 431.5 / 56 / 347）。
> - 竖排系统栏时底部只让 `safeArea.bottom`，不再减 64/83（Duo 横屏/外屏）。
> - 新增 `SplitLayoutTests` 的 Duo 用例；工程元数据升到 27.2。
> - **未做**：P1 常规宽度双列/限宽、P1 半折竖屏折痕策略（D1/D2 仍待拍板）、
>   P2 `ArrangementView` / 多窗口 / UI 测试矩阵。见下文。

---

## 0. 一句话结论

**P0 已修：折痕参与横屏分栏、窗口尺寸改用窗口 bounds、竖排系统栏不再按底部横栏留白。**
剩余的是常规宽度版面（P1）与 API/工程化（P2）。下面 §3 的问题清单保留为
「发现时的原始记录」，其中 P0 三条已在本轮实现。

---

## 1. 实测结果

| 检查项 | 结果 |
|---|---|
| `xcodebuild build`（iPhoneSimulator 27.2 SDK） | ✅ 通过，无源码错误；没有出现新的 Swift 警告 |
| `JustDiaryTests`（在 Duo 测试目的地） | ✅ 全量通过 |
| `JustDiaryUITests` | ⏳ 未在 Duo 上跑；现有用例按 18 Pro / SE 的尺寸写死，直接跑会误报 |
| iOS 27.1/27.2 新 API 是否可编译 | ✅ `reservedRegions` / `onHingeChange` 在 `@available(iOS 27.1, *)` 下、部署目标仍为 27.0 时可以 typecheck |
| 系统栏（TabBar）是否自动侧置 | ✅ 系统自动处理：内屏竖屏在底部，内屏横屏 / 外屏在侧边 |
| 应用自己画的顶栏 / 浮动控件是否避开折痕、摄像头 | ❌ 未接入 `reservedRegions`，靠固定数值，见 §3 |
| 分屏 / 可缩放窗口 | ⚠️ 未实测；代码层面的尺寸来源有 bug，见 §3 P0-2 |
| 折叠 / 展开时 App 是否存活、状态是否保留 | ✅ 单 scene 可随姿态切换；多窗口未实测 |

> 构建与测试时的 App 数据：模拟器里是空的日记库（用户环境）。测试没有改动
> 仓库里的代码，也没有提交。

---

## 2. iPhone Duo 实测几何

### 2.1 显示与尺寸

| 显示 | 原生像素 | 点尺寸 | 说明 |
|---|---|---|---|
| 内屏（LCD-1） | 2007 × 2853 @3x | **669 × 951 pt** | 展开后的主屏；可竖可横 |
| 外屏（LCD） | 1398 × 2034 @3x | **466 × 678 pt** | 合上后的外屏；宽而矮 |

- 内屏横屏时窗口为 **951 × 669 pt**，竖屏时 **669 × 951 pt**。
- 横屏 / 竖屏由系统旋转；DeviceHub 底部有 `Closed / Partially Open / Open`
  三个姿态按钮和 `Rotate Right`，**这是测试姿态的正确入口**（不要再去改屏幕电源，
  见 §7 备注）。

### 2.2 尺寸类与安全区（实测）

| 姿态 | 窗口 | Size Class | safeAreaInsets | 备注 |
|---|---|---|---|---|
| 内屏 · 竖屏 · 展开 | 669 × 951 | **Regular / Regular** | `top 82, left 0, bottom 34, right 0` | 顶部 82pt 已经让开摄像头/状态栏 |
| 内屏 · 横屏 · 展开 | 951 × 669 | **Regular / Regular** | 未逐项记录（右侧有竖排系统栏） | 竖排 TabBar 在右侧 |
| 内屏 · 横屏 · 半折 | 951 × 669 | Regular / Regular | 同上 | 有真实 division region |
| 内屏 · 竖屏 · 半折 | 669 × 951 | Regular / Regular | `top 82, bottom 34` | 有真实 division region |
| 外屏 · 合上 | 466 × 678（或旋转后 678 × 466） | compact width（待补测） | 由系统侧栏给出 | TabBar 在侧边 |

**关键：内屏是 `Regular / Regular`**，不是「放大的紧凑 iPhone」。这直接决定了
`AdaptiveLayout` 不能只看 `size.height >= size.width`；它应该同时知道
`horizontalSizeClass == .regular`。

### 2.3 reserved regions（实测值）

内屏半折横屏：

```
division: frame = (455.5, 0, 40, 669), margins = (top 0, left 20, bottom 0, right 20), active = YES
occlusion: frame = (867.0, 0, 84, 124), active = YES
```

内屏半折竖屏：

```
division: frame = (0, 455.5, 669, 40), margins = (top 20, left 0, bottom 20, right 0), active = YES
occlusion: frame = (525.0, 0, 144, 82), active = YES
```

内屏竖屏展开（平放）：

```
division: 默认查询为空（平放时 division 不 active）
occlusion: (525.0, 0, 144, 82), active = YES
```

读法：

- `frame` 是**包含 margins 的**区间。半折横屏的折痕带就是 x = **455.5…495.5**
  （中心 475.5，左右各 20pt 交互留白）；竖屏就是 y = **455.5…495.5**。
- `occlusion` 是摄像头。竖屏顶部 82pt 安全区已经覆盖了它；横屏是右上角
  84 × 124，和右侧竖排栏重叠，系统栏/系统容器会避让，自定义顶栏需要自己确认。
- Apple 的规则：**平放时 division 不 active、宽度为 0**；需要「有没有折痕」
  这种高层判断时用 `options: .includeInactive`。

### 2.4 系统栏的真实位置（截图实测）

| 姿态 | TabBar | 结论 |
|---|---|---|
| 内屏 · 竖屏 | 底部横向（和普通 iPhone 一样） | 现有 `tabBarClearance = 83` 对 |
| 内屏 · 横屏 | **右侧竖向** | 现有 `tabBarClearance = 64` 错，底部会多留 64pt |
| 外屏 · 竖屏 | **右侧竖向** | 现有 `isPortrait == true` 会按 83 留，年视图偏矮 |
| 外屏 · 横屏 | **侧边竖向**（左 / 右随姿态） | 现有 `isPortrait == false` 会按 64 留，分栏底部多留 64pt |

> 这四条是**同一类 bug**：`AdaptiveLayout` 只按「横 / 竖」猜系统栏方向，
> 而 Duo 的系统栏是**侧置**的。应该读 iOS 27.1 的
> `@Environment(\.toolbarVerticalEdge)`（`HorizontalEdge?`）或等价信息，
> 而不是继续用 83 / 64 两个固定值。

---

## 3. 问题清单（按优先级）

### P0-1 半折横屏：分栏线没有让开折痕（最明显）

- 现状：`AdaptiveLayout.splitColumns(containerWidth:)`（`AdaptiveLayout.swift:88`）
  固定按容器宽的 46% 分主栏；`HomeView.splitCalendarArea`（`HomeView.swift:337`）
  用 16.5pt 的分隔线。
- 951pt 宽时：分栏线/右栏起点大约在 461–470pt；如果几何已经扣掉右侧 84pt 竖栏
  （内容宽 867pt），右栏起点约 432pt。无论哪种，右栏内容都会从
  **455.5…495.5pt 的折痕带**里开始，实测截图中「10月27日 周二」标题正好压在折痕上。
- 半折竖屏更明显：单栏月历横穿 y = 455.5…495.5 的折痕，落在这一带的日期
  （可点击）正好在曲面里。
- **要做**：把 active `division` 传给版面；横屏分栏时把折痕带当作分隔区，
  让左栏在 `frame.minX` 之前结束、右栏在 `frame.maxX` 之后开始，并把
  gutter 至少扩到折痕带宽度（+ 8~16pt 安全边）。数值上应接近 50/50，
  与 Apple 的「Reminders 在折痕处保持两栏 50/50」一致。
- **验收**：半折横屏下，左右两栏的可视内容都不与 `455.5…495.5` 相交；
  分栏总宽仍等于容器宽，不横向溢出。

### P0-2 分屏 / 可缩放窗口：`AdaptiveLayoutReader` 用了整块屏幕尺寸

- `AdaptiveLayoutReader.resolve` 用 `scene.screen.bounds`（`AdaptiveLayout.swift:239`），
  不是窗口 bounds。
- Duo 的 50/50 分屏里，屏幕仍是 951 × 669，但 App 窗口可能只有 **475 × 951**：
  - `layout.size` 会变成 951 × 669 → `isPortrait == false`（实际窗口是竖的）；
  - `contentColumn(660)` 会返回 660（窗口只有 475，正文会溢出）；
  - `tabBarClearance` 会按 64 而不是 83；
  - 现有 `dw` 补安全区的逻辑会把「缺少的窗口宽度」误当成 trailing 安全区。
- `Screen.currentSize`（`Components.swift:31`）**已经**是用 key window bounds 的，
  两块逻辑不一致；应该统一。
- **要做**：`resolve` 用 `scene.keyWindow?.bounds.size`（首选）/
  `scene.coordinateSpace.bounds`，而不是 `screen.bounds`；安全区继续用
  `geometry.safeAreaInsets`，保留无窗口时的兜底。
- **验收**：50/50 分屏、窗口任意缩放时，`contentColumn`、分栏、`isPortrait`
  都按窗口而不是屏幕计算；不横向溢出。

### P0-3 竖排系统栏仍按底部横栏留白

- `tabBarClearance`（`AdaptiveLayout.swift:144`）返回 83（竖） / 64（横）；
  `splitPaneHeight`（`:100`）和 `singleColumnCalendarHeight`（`:122`）都减它。
- Duo 内屏横屏 / 外屏的 TabBar 在侧边，底部没有横栏：
  - 内屏横屏分栏：`669 − 8 − 64 = 597pt`，实际可用 669pt → 底部约 64pt 空白；
  - 外屏竖屏年视图：仍会按 83pt 缩短；
  - 外屏横屏分栏：仍会按 64pt 缩短。
- **要做**：给 `AdaptiveLayout` 增加「系统栏是竖排还是横排」的信息
  （iOS 27.1 的 `toolbarVerticalEdge`；27.0 上默认 nil），横排才减 83/64，
  竖排时底部最多让 `safeArea.bottom`；`TabBarClearance` 组件（Settings / Search /
  Diary 的底部占位）同样要按这个信息取值，不能继续写死 120/140。
- **验收**：内屏横屏、外屏横竖屏的日历/列表底部不再出现一条固定高度的空白；
  iPhone 18 Pro 横屏（底部横栏）仍保持 64pt，不回归。

### P1-1 内屏竖屏是 Regular/Regular，但四屏仍是「拉长的 iPhone」

实测截图里：

- `SettingsView`（`SettingsView.swift:19`）只加了 16pt 页面边距，卡片铺满
  637pt，行内文字与右侧值之间大片空白；
- `FootprintView`（`FootprintView.swift:36`）在 `isPortrait` 时走单栏，
  669pt 宽的统计/清单卡片显得空；
- `SearchView`（`SearchView.swift:161`）在 `isPortrait` 时时间与地点上下堆叠，
  横向空间浪费；
- `HomeView` 单栏月历：每格 ~95pt、农历字 ~11pt，格子明显偏大。

Apple 的 Duo 指南明确说「不要把 iPhone App 直接拉宽」，并建议在常规宽度上
使用分栏 / 双列。这里有两条路线，见 §5 的 D1 / D2：

- **保守**：所有页面最大内容宽 600–660pt 居中，保持单栏；
- **完整**：常规宽度上做双列（首页日历+详情、设置分组双列、搜索列表+预览、
  足迹图表+清单），横竖屏各一套。

### P1-2 还没有 `FoldAvoidance` / reserved regions 数据

- `docs/adaptive-layout-plan.md` §4 与 `docs/design-system.md` 都把这件事
  标为待做；代码里目前**没有任何** `reservedRegions` / `FoldAvoidance`。
- 建议在 `AdaptiveLayout` 里增加一个**与 SDK 类型解耦**的模型，例如：

  ```swift
  struct FoldRegion: Equatable, Sendable {
      var frame: CGRect       // 包含 margins
      var margins: EdgeInsets
      var isActive: Bool
  }
  ```

  `AdaptiveLayoutReader` 在 iOS 27.1+ 用
  `proxy.reservedRegions(kind: .division, options: .includeInactive)` 和
  `.occlusion` 填它；27.0 上恒为空。这样单元测试不需要 `@available`，
  UI 页面也不直接依赖 SwiftUI 的 `ReservedRegion`。
- 对外提供 `divisionRegions` / `activeDivision` / `occlusionRegions` /
  `hasFold` / `foldAxis`（横带或竖带）等只读属性。
- **坐标系要确认**：`GeometryProxy.reservedRegions` 返回的是 proxy 坐标空间；
  `AdaptiveLayoutReader` 挂在 `TabView`（`RootView.swift:88`）上，和
  `HomeView` 内层 `GeometryReader` 的原点可能差一个 safe area。实现时用
  `proxy.frame(in: .global)` 统一到窗口坐标，或明确约定「相对 reader 本地坐标」，
  并加一个探针/测试验证，不要靠猜。

### P1-3 半折竖屏：滚动内容 vs 可点击日期

- 竖屏折痕是**横带**（y 455.5…495.5），月历是连续滚动的，但日期格子可点击。
- Apple 的原则是「可滚动内容不必避开折痕；可交互元素尽量避开」。
  月历算两者的混合：连续滚动 + 每格可点。
- 三种可选策略：
  1. 把月历视为滚动内容，**只在折痕处加一条 40pt 的视觉留白**（日期网格整体下移），
     代价是月份流多一条固定空隙、跨月滚动时仍在；
  2. 按月历当前滚动位置，把折痕附近那一行日期临时下移（复杂，不建议）；
  3. 只把**浮动控件 / 底部栏 / 顶栏**挪出折痕，月历日期接受折痕
     （最省事，但和 Apple 的 Fitness 示例不一致）。
- 建议先做 1 的视觉验证（只影响半折竖屏），再决定；见 D2。

### P1-4 摄像头 occlusion 与自定义顶栏

- 内屏竖屏顶部 82pt 安全区已覆盖 144×82 的摄像头；但这是**系统**给的安全区，
  自定义全屏背景 / `.ignoresSafeArea(.top)` 的图层可能盖到它。
- 内屏横屏的摄像头在右上 84×124，和右侧竖排栏重叠。日记页顶栏
  （`DiaryPageView.swift:400` 的 `topBarOverlay`）是自绘的，不是系统 toolbar；
  需要实测它在横屏下是否与摄像头/竖栏相交（本轮截图受模拟器采集问题影响，
  没有留下可靠证据）。
- 外屏摄像头是常驻的，系统安全区已处理；但首页/日记页的自定义胶囊、
  分享按钮仍需逐一确认。

### P1-5 外屏 / 竖排系统栏下的自定义控件对齐

- 系统 TabBar 侧置时，`toolbarVerticalEdge` 会告诉你是 leading 还是 trailing；
  首页的「今天」「‹ 2026年」胶囊、日记页的顶栏按钮、搜索的浮动按钮都应该
  按这个值对齐或避让，而不是假设右侧/底部。
- 系统会在空间不足时把工具项收进 `...`（实测外屏横屏的「今天」已经变成
  `...`）；应用自绘的按钮没有这个行为，需要自己处理溢出或改用系统 toolbar。

### P2-1 新 API 的采用

已在 27.1 SDK 里确认可用（部署目标 27.0 时用 `@available(iOS 27.1, *)` 包起来）：

| API | 用途 | 建议 |
|---|---|---|
| `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` | 折痕 / 摄像头区间 | **P0 必接** |
| `ReservedRegion`（`frame` / `margins` / `isActive` / `kind`） | 数据 | 转成应用自己的 `FoldRegion` |
| `View.onHingeChange(isEnabled:_:)` / `DeviceHinge` | 铰链状态与角度 | P2：只做交互/动效，**不要拿来做版面判断**（Apple 明确说布局用 region / arrangement） |
| `ArrangementView` + `.arrangementViewStyle(.split/.overlay)` / `.axes` | 系统分栏 | P2：评估替换首页 `HStack` 分栏 / 搜索主从；它可能自动处理折痕和 50/50 |
| `toolbarVerticalBehavior(.automatic/.disabled)` | 是否使用竖排栏 | P2：当前默认 `.automatic` 已让系统侧置，不建议关掉 |
| `toolbarVerticalCompressionBehavior(...)` | 竖排栏溢出时保谁 | P2：外屏空间不足时有用 |
| `ToolbarItem.axisBehavior(...)` | 单条工具项走横/竖 | P2：日记页若改成系统 toolbar 再用 |
| `@Environment(\.toolbarVerticalEdge)` | 竖排栏在左还是右 | **P0/P1 建议接**，用于 `tabBarClearance` 和自定义胶囊对齐 |
| `UIView.reservedRegions` / `UIHinge` / `UIHingeInteraction` | UIKit 等价物 | 本项目纯 SwiftUI，除非做 UIKit 桥接，否则不用 |

> 已做过一个最小 typecheck：`GeometryProxy.reservedRegions` + `onHingeChange`
> 在 `-target arm64-apple-ios27.0-simulator` 下、带 `@available(iOS 27.1, *)`
> 可以编译。`ArrangementView` / toolbar 系列是 `anyAppleOS 27.1`，同理需要守卫。

### P2-2 多窗口 / 分屏 / 尺寸类

- 生成的 Info.plist 已有 `UIApplicationSupportsMultipleScenes = true`，
  `UISceneConfigurations = {}`（SwiftUI 自动生成）。
- Duo 内屏支持同一 App 的多个窗口，外屏不支持新建窗口（系统会处理）；
  当前 App 没有显式的多窗口 UI，是否要支持由产品决定。
- 50/50 分屏是**同一个 scene 被改尺寸**，首要修复是 P0-2；
  多窗口是另一件事，放到 P2。

### P2-3 SDK / 工程元数据

- `JustDiary.xcodeproj` 的 `LastUpgradeCheck` / `LastSwiftUpdateCheck` 仍是
  **2700**，`CreatedOnToolsVersion` 是 27.0（`generate_project.py:423-434`）。
- 已改为 **2720 / 27.2** 并同步 `generate_project.py`；部署目标仍为 27.0（见 D3）。
- README 徽章与平台说明已更新为 Xcode 27.2 / iOS 27.0+（Duo API 需 27.1）。
- 本轮 27.2 SDK 构建没有发现需要处理的新废弃 API；如果实现时用到
  27.1 独有 API，务必 `#available`，不要悄悄把最低系统提到 27.1。

### P2-4 测试与文档

- 现有 `AdaptiveLayoutTests` / `SplitLayoutTests` 里 Duo 的假设是
  `664 × 750`（`AdaptiveLayoutTests.swift` 的 `(664, 750, 24)`、
  `SplitLayoutTests.testPortraitNeverSplits` 的 `(664, 750)`），
  实际是 **669 × 951**；需要更新并补：
  - 951 × 669、669 × 951、466 × 678、678 × 466；
  - 475 × 951（50/50 分屏）；
  - 半折 region（竖带 / 横带）与分栏避让；
  - 竖排栏时 `tabBarClearance == 0/safeBottom`，横排仍是 83/64。
- `PortraitLayoutUITests` / `LandscapeLayoutUITests` 写死了 18 Pro / SE 的
  浮条位置和「横屏必须左右分栏」；Duo 横屏是左右分栏（OK），但浮条在右侧，
  `app.tabBars.frame` 的断言会失效。建议新增 `DuoLayoutUITests`，
  或者把公共断言改成从真实 `tabBars` frame 推导。
- 本轮没有跑 UI 测试（避免再造测试克隆、也避免现有断言误导）；实现后要补跑。
- 文档：把 `adaptive-layout-plan.md` §4 从「待做」改为「已适配」，
  把 `design-system.md` 里「不要在 27.0 上提前接 reservedRegions」的说明
  更新为「27.1+ 已接，P0」；`iOS27-upgrade-plan.md` 加一节 27.1 附录。

---

## 4. 实施顺序与验收

### 阶段 A（P0，不改视觉风格，先把版面算对）

1. **A1 数据模型**：`AdaptiveLayout` 增加 `horizontalSizeClass`（或 `isRegularWidth`）、
   `foldRegions`、`verticalBarEdge`；`FoldRegion` 用应用自己的值类型。
2. **A2 Reader**：`AdaptiveLayoutReader` 用窗口 bounds；在 27.1+ 读
   `reservedRegions`，27.0 返回空；处理坐标空间。
3. **A3 分栏**：`splitColumns(containerWidth:)` 支持折痕带；`HomeView` 使用
   动态 gutter；折痕带两侧各留 8~16pt；分栏总宽仍等于容器宽。
4. **A4 系统栏**：`tabBarClearance` 按 `toolbarVerticalEdge` 分支；
   `splitPaneHeight` / `singleColumnCalendarHeight` / `TabBarClearance` 全部走它。
5. **A5 回归**：18 Pro / SE 的现有数值不变；Duo 半折横屏两栏都不压折痕；
   50/50 窗口不溢出。

### 阶段 B（P1，常规宽度与半折竖屏）

1. 四屏最大内容宽 / 双列方案（D1）。
2. 半折竖屏折痕策略（D2）。
3. 摄像头 occlusion 与自定义顶栏 / 浮动按钮。
4. 外屏 / 竖排栏下自定义胶囊、`...` 溢出。

### 阶段 C（P2，API 与工程化）

1. `ArrangementView` 试点（首页 / 搜索），与现有 `HStack` 对比。
2. `onHingeChange` 只做动效（可选）。
3. 多窗口 / scene 支持（如果需要）。
4. 工程元数据、README、文档、UI 测试矩阵。

### 验收标准（摘要）

- 六种姿态（内屏开/半折/合上 × 横/竖）都能正常启动、无黑屏、无内容被系统栏遮挡。
- 半折横屏：右栏文字不进入 455.5…495.5；半折竖屏按 D2 的决策执行。
- 内屏 669/951、外屏 466/678、50/50 分屏 475 宽，正文都不横向溢出。
- iPhone 18 Pro 竖屏 402×874、横屏 874×402、SE 横屏 667×375 的已验证数值不回归。
- 单元测试 + 现有 UI 测试 + 新增 Duo 用例通过。

---

## 5. 需要你确认的决策

| 编号 | 问题 | 选项 | 我的建议 |
|---|---|---|---|
| **D1** | 内屏竖屏（Regular/Regular）怎么排？ | A. 只限宽居中（600–660）<br>B. 首页分栏 + 设置双列 + 搜索主从 | 先 A 保稳，再挑一屏做 B 试点；Duo 是常规宽度，纯 A 仍会有「拉宽感」 |
| **D2** | 半折竖屏的月历折痕怎么处理？ | A. 折痕处加 40pt 空隙（日期整体下移）<br>B. 只挪浮动控件，日期接受折痕 | A 更符合 Apple 的 Fitness 示例；先做一版截图对比再定 |
| **D3** | 最低系统版本？ | A. 保持 27.0，Duo API 加 `@available`<br>B. 提到 27.1 | **A**；Duo 只跑 27.1，但没必要为此丢掉 27.0 |
| **D4** | 本轮范围？ | A. 只做 P0<br>B. P0 + P1 视觉适配<br>C. 全做（含 ArrangementView / 多窗口） | 先 P0 + D1/D2 确认后的 P1；C 单独排期 |
| **D5** | 提交 / 推送 | 现在只留 TODO；代码改完再提交 | 按你说的「先不改代码」，本文档暂不提交 |

---

## 6. 测试矩阵（实现后要跑）

| 设备 / 姿态 | 首页 | 足迹 | 搜索 | 设置 | 日记阅读 / 编辑 | 分享 / sheet |
|---|---|---|---|---|---|---|
| Duo 内屏竖屏展开 | 月历、年历、morph | 单/双列 | 筛选 + 结果 | 分组 | 顶栏、正文限宽 | 系统 sheet |
| Duo 内屏横屏展开 | 左右分栏、竖排栏 | 双列 | 主从 | 双列 | 顶栏 + 摄像头 | 系统 sheet |
| Duo 内屏竖屏半折 | 折痕带 / 日期 | 滚动 | 滚动 | 滚动 | 键盘 / 格式栏 | 系统 sheet 自动避让 |
| Duo 内屏横屏半折 | 分栏避折痕 | 双列避折痕 | 主从避折痕 | 双列 | 顶栏避折痕 | 系统 sheet |
| Duo 外屏竖 / 横 | 侧栏 + 沉浸 | 单/双列 | 单列 | 单列 | 顶栏 | 侧栏 sheet |
| 18 Pro 竖 / 横 | 现状回归 | 现状 | 现状 | 现状 | 现状 | 现状 |
| SE 横 | 667pt 分栏回归 | — | — | — | — | — |
| Duo 50/50 分屏（475×951） | 不溢出 | 不溢出 | 不溢出 | 不溢出 | 不溢出 | — |
| 动态字体 XXL / AX | 不截断 | 不截断 | 不截断 | 不截断 | 编辑器不截断 | — |

---

## 7. 备注与边界

- **没有改任何代码**：工作区在本轮开始时是干净的；这份文件是唯一新增内容。
  没有提交、没有推送。
- **模拟器**：使用用户已启动的 iPhone Duo，未新建。测试过程中曾误用
  `simctl io screenConfig` 关/开内屏电源，导致 SpringBoard 连续重启和报错窗口；
  已通过重启**同一台**模拟器恢复，最终回到「展开 · 竖屏 · 首页」。
  后续测试姿态应只用 DeviceHub 的 `Closed / Partially Open / Open` 按钮。
- **截图**：模拟器的 display capture 在电源折腾后出现过黑帧，DeviceHub 窗口本身
  正常；本 TODO 里的数值以 Xcode API / DeviceHub 实测为准，截图只作辅助。
- **没有验证**：真机、50/50 分屏、多窗口、外屏摄像头实际工作状态、
  半折时的键盘/格式栏、通话/相机占用摄像头时的 occlusion。
- **设计稿**：Duo 没有单独设计稿；如果 D1 选 B，需要补一版 669×951 和
  951×669 的对照稿。

---

## 8. 参考资料

- Apple Tech Talk: [Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/)
- Apple Tech Talk: [Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/)
- Apple Tech Talk: [Leverage multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/)
- Apple HIG: [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- 第三方整理（API 清单，仅作索引）:
  [What can the APIs added in iOS 27.1 for iPhone Duo do?](https://dev.classmethod.jp/en/articles/ios27-1-iphone-duo-new-apis/)
