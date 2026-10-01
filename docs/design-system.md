# 设计系统与显示规范

日期：2026-09-15 · 环境：Xcode 27 / iOS 27 SDK · 设备：iPhone 18 Pro 模拟器（iOS 27.0）

本文记录界面层的四条规范：设计令牌、动态字体、日期/时间格式、Liquid Glass 的使用边界。
改动界面时请先读这一篇，避免同类问题再次出现。

---

## 一、设计令牌（`Views/Components/DesignSystem.swift`）

改造前项目里有 10 个互不相干的圆角（1 / 4 / 8 / 12 / 16 / 18 / 20 / 22 / 26 / 28），
相邻两张卡片可能差 2pt 却没有任何理由。现在全部来自一个小令牌集：

| 令牌 | 值 | 用途 |
|---|---|---|
| `Radius.card` | 20 | 内容卡片、列表行、hero 面板 |
| `Radius.panel` | 26 | 悬浮控件面：编辑器格式栏、sheet |
| `Radius.field` | 14 | 输入框、卡片内的次级面（搜索容器、位置行高亮） |
| `Radius.image` | 14 | 卡片内联图片 |
| `Radius.badge` | 12 | 图标徽章、小色块 |
| `Radius.bar` | 4 | 图表柱、进度条 |
| `Radius.hairline` | 1 | 2pt 高的标记线（日历「有日记」下划线） |

**嵌套圆角要走「外圆角 − 内缩量」**，不要把内外圆角设成同一个值 —— 那是 Apple 对
「圆角里套圆角」的规则，直接相等会产生视觉上的「尖角内衬」。
**现状（2026-10-01 核实）：目前没有一处嵌套面按这条规则取值** —— 唯一的内外组合是
卡片（20）里的内联图片（`Radius.image` 14），而卡片内边距是 `Spacing.card`(12)，
严格同心应该是 8。这是一处刻意的偏离（14 看起来更顺眼，也没人抱怨过），改它会动到
所有内联图片的观感，所以保持原样、只把事实记在这里。
（同一次清理删掉了零调用的 `Radius.concentric(outer:inset:)` 助手；以后真要做同心面时
按这条规则取值即可，不必先把助手加回来。）

分享长图渲染器（`ImageShareService`）也走同一套品牌色与卡片语言：浅色底用
`Theme.seed` 的 #2563EB、深色底提亮一档，每条记录一张卡片，正文压在卡片的浅底上。
2026-09 重做前的版本是「三个大色球 + 满屏渐变 + 一条悬空的蓝色时间轴」：背景把
正文的对比度拉低，横幅式大日期下面重复一次首条时间，页脚只有一行几乎看不见的
「· 一页时光 ·」。现在的版面是：品牌行（品牌点 + 应用名 + 年份）→ 大日期 + 星期 →
起始时间 → 品牌色短线 → 每条记录（时间 / 地点行 + 卡片）→ 细线页脚
（「一页时光 · JustADiary」+ 当天日期）。排版与绘制共用同一份结果
（`makePage` 产出绘制指令，`draw` 只执行），不会再出现「量出来 3 行、画出来 4 行」。

`Spacing` 与 `TypeSize` 同理，只收敛已经被重复使用的值，不是重新排版。

---

## 二、动态字体

### 2.1 为什么不能用一个全局系数

`Font.system(size:)` 是**固定字号**，完全忽略
设置 › 显示与亮度 › 文字大小。第一版修复用了一个全局缩放系数，但它会把 32pt 的
日历标题和 11pt 的注释按同一个倍数放大——这既不是 Apple 的做法（每个文本样式有
自己的曲线，大字号样式的相对增幅远小于小字号），也会让大标题先撑破布局。

现在 `DynamicTypeMetrics` 把每个设计字号归到**最接近的 Apple 文本样式**，再用
`UIFontMetrics(forTextStyle:)` 得到缩放值。默认字号下每个度量都返回原值，所以默认
外观与改造前一致，只有「放大时的增幅」因角色而异。

### 2.2 为什么仍然要有上限（`ceiling(for:)`）

Apple 的原始曲线在 AX5 会把 body 从 17pt 推到约 53pt，**并且让它比标题样式涨得更快**。
套到本项目的字号梯级上会出现**层级倒挂**：15pt 正文最终比 22pt 标题还大，日记的
结构感在最需要阅读的场景下反而消失。

因此每个样式设了增幅上限，取值保证**整条梯级保持单调**——每一级都明显高于下一级：

| 设计字号 | 32 | 28 | 24 | 22 | 20 | 18 | 17 | 16 | 15 | 13 | 12 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| AX5 实际 | 44.8 | 39.2 | 34.8 | 31.9 | 29 | 27 | 25.5 | 24.8 | 24 | 21.5 | 20.4 | 19.3 |

其中 28 / 22 / 17 / 15 就是编辑器的字号梯级（见第三节），它在 AX5 下同样保持单调。

这是**有意的偏离**，理由写在上限函数的注释里。调整上限时请重新核对这张表是否仍然单调。

### 2.3 日历是唯一的例外

日历用 `Canvas` 绘制，格子尺寸由屏幕决定，所以日号走 `calendarMultiplier`
（半速）；星期栏走 `.diaryCalendarFont(_:)`，同样是半速，避免撑破固定高度的条带。

### 2.4 UIKit 侧（编辑器 / 阅读器）

`PartsCodec` 与 `ReadTextView` 在 SwiftUI 之外构建 `NSAttributedString`，无法使用
`.diaryFont`，改为接收显式的 `DynamicTypeSize`。`RootView` 通过
`\.diaryDynamicTypeSize` 下发（2026-10-01 核实：挂在 `NavigationStack` 上，
`RootView.swift:83`）。**现状（2026-10-01 核实）**：日记页已改为推进式
`navigationDestination`（见第十一节），不再有 `fullScreenCover`，也就**不需要**单独注入 ——
推进出来的 `DiaryPageView` 直接继承这层环境值（`RootView.swift:72-75`）。

编辑器不提供任意磅值：它给段落的是**语义样式**（大标题 / 小标题 / 正文 / 引用），
字号取 Apple 的 iOS 默认梯级（28 / 22 / 17 / 15，见第三节）。

---

## 三、编辑器往返不变量（最重要）

### 3.1 语义样式，字号取 Apple 的梯级

编辑器照 Apple 备忘录的做法，只提供语义段落样式，字号取 HIG › Typography 的
iOS 默认值：

| 样式 | `ContentPart.style` | 设计字号 | Apple 文本样式 |
|---|---|---|---|
| 大标题 | `title` | 28 | Title 1 |
| 小标题 | `heading` | 22 | Title 2 |
| 正文 | `body` | 17 | Body |
| 引用 | `quote` | 15 | Subheadline |

（2026-10-01 核实：属性名是 `ContentPart.style`（`Models/ContentPart.swift:63`），取值是
`ContentPartStyle` 的 `title` / `heading` / `body` / `quote`；上表原来的 `type` 与
`h1` / `h2` / `p` 是 v1 的旧键与旧值，只在读取旧数据时被归一化。）

行距与段间距按字号比例计算，只影响绘制、不落库（读取时由块类型重新推导）。
（2026-10-01 核实：段间距现在**全部由段前距承担**，段后距恒为 0 ——
`EditorBlockStyle.paragraphSpacing` / `paragraphSpacingBefore`，见 `docs/editor-typography.md` 第八节。）
设计意图与决策记录见 `docs/editor-typography.md`。

> **平台分工（2026-09-20 确认）**：iOS 版按 **Apple HIG**，Android 版（`../JustGDiary`）
> 按 **Material 3**，两端的阅读排版**有意不同**：
>
> | 段落样式 | iOS（Apple HIG） | Android（Material 3） |
> | --- | --- | --- |
> | 大标题 | Title 1 = **28** | `headlineMedium` = **28** |
> | 小标题 | Title 2 = **22** | `titleLarge` = **22** |
> | 正文 | Body = **17** | `bodyLarge` = **16** |
> | 引用 | Subheadline = **15** | `bodyMedium` = **14** |
>
> 这**不影响互通**：`content_json` 存的是**语义样式**（`title` / `heading` / `body` / `quote`）
> 与行内标志，**字号从不落库**，由各端在渲染时按自己的规范推导。
> 两端的 golden 字节级断言（`JustDiaryTests/ContentFormatTests` 与 Android 的
> `app/src/test/resources/golden/`）因此仍然成立。
> **不要**为了让两端"看起来一样"而把字号写进存储或改掉某一端的梯级。

### 3.2 块类型与字号解耦

改造前 `parts(from:)` 是**从字号反推块类型**的（`>= 22` → h1、`>= 18` → h2），
字号同时承担「字号」与「块类型」两个职责，因此改字号就必须做一次性数据迁移，
而且旧梯级 {13, 15, 18, 22} 与新梯级在 15 处重叠，无法区分「应用自己写的 15」和
「导入文档里用户自定义的 15」。

现在每个 run 同时带：

- `.diaryBlockStyle`：块类型（大标题 / 小标题 / 正文 / 引用），落库为 `ContentPart.style`；
- `.diaryDesignSize`：未缩放的设计字号，绝不能被绘制字号替代。

`parts(from:)` **优先读 `.diaryBlockStyle`**；字号推断只在没有块类型时使用
（UIKit 重新同步 typingAttributes 时丢掉自定义键的字符，见 3.4）。因此调整字号梯级
不会再改写已有日记。

`TextRun` **不再有 `size`**：字号的唯一来源是块样式。存储格式（v2，语义样式名 +
版本信封）与 v1 的兼容读取见 `docs/editor-typography.md` 第三节。

### 3.3 编辑器文本存储里必须是设计字号

编辑器文本存储里必须是设计字号（28 / 22 / 17 / 15），绝不能是实际绘制的字号：
一旦开了动态字体，17pt 正文会被画成约 25.5pt，拿绘制值反推就会把段落判成标题。
设计字号不落库——落库的是块样式，字号每次加载时由样式重新推导。

### 3.4 兜底必须精确

`.diaryDesignSize` 缺失时的兜底不能是近似反解。UIKit 会按固定的一组键从光标处
重新同步 `typingAttributes`，**自定义键会在输入第二个字符起丢失**，此时若用除法
近似反解，落库的 `size` 会逐次漂移（实测旧梯级下 15 → 18.75），而 18.75 ≥ h2 的
18，再存一次就真的把段落变成标题。因此兜底先拿绘制值与编辑器自己产出的字号做
**精确匹配**（`EditorDesignSize.authored`），只有导入文档的自定义 run 字号才走除法。

### 3.5 回归测试

`JustDiaryTests/ContentFormatTests`（单元）：在**全部 12 档字号**下把
`PartsCodec.attributedString` 的结果解析回来，断言块样式、对齐、文本与行内样式不变；
另覆盖存储格式本身（v2 信封、v1 升级、未开启的行内样式不写成 `false`）。
毫秒级，UI 测试采样不到的档位由它兜住。
（2026-10-01 核实：「12 档」= `testEditorRoundTripPreservesStylesAtEveryTextSize` 遍历
`DynamicTypeSize.allCases`，SwiftUI 目前正是 12 档；存储格式那几条见
`testSerializedContentIsVersionedAndCarriesNoFontSize` / `testLegacyV1ContentIsUpgradedOnRead` /
`testOnlySetInlineStylesAreWritten`。）

`JustDiaryUITests/EditorTypeSizeUITests`（UI）：在最大辅助功能字号下建立
`body / title / heading / quote` 四段 → 保存 → **重新打开已保存的块**（不是新建）→
再次保存，共三轮，断言块样式与文本不变；另有「放弃修改恢复到保存前」「输入区随
字号放大」「没记地点的块不能再补一个」三个用例。用例通过 `-ui-test-editor-state` 探针
读取编辑器将要落库的块样式，不需要读容器数据库。
（2026-10-01 核实：用例名依次为 `testBlockStylesSurviveReSaveAtLargestTextSize`（第 1 轮 +
`for pass in 2...3`）、`testDiscardChangesRestoresSavedContent`、`testInputAreaGrowsWithTextSize`、
`testEntrySavedWithoutLocationCannotGainOne`。）

旧版用例点的是「写日记」（新建），并没有重新解析应用自己渲染过的文本，已一并修正。

---

## 四、日期 / 时间格式

同一类信息只允许一种写法。改造前存在这些不一致：

| 问题 | 改造前 | 现在 |
|---|---|---|
| 时间被写死 24 小时制 | `HH:mm`，英文用户看到 "Started at 21:00"，而同屏的「新一天开始时间」写 "4:00 AM" | `L10n.timeOf` / `timeLabel` 取**设备**的小时制（尊重「24 小时制」开关），AM/PM 符号取应用语言 |
| 日期与星期的连接符 | 周标题用 ` – `（读起来像区间），日标题用空格 | 统一为空格 |
| 区间分隔符 | `dateRange` 用 `~` | 统一为居中的短破折号 `–`（`date_range`） |
| 相对日期 | `1天前` | `昨天` / `明天`（`index_yesterday` / `index_tomorrow`），其余仍用 N天前/后 |

各语义槽位当前取值：

| 槽位 | 函数 | zh | en |
|---|---|---|---|
| 年 | `date_year` | `2026年` | `2026` |
| 月（大标题） | `monthFull`（MMMM） | `九月` | `September` |
| 月（紧凑） | `monthName`（shortMonthSymbols） | `9月` | `Sep` |
| 年+月+日+星期 | `weekHeaderTitle` | `2026年9月15日 周二` | `Tue, Sep 15, 2026` |
| 月+日+星期 | `dayTitle` / `formatDayKey` | `9月15日 周二` | `Tue, Sep 15` |
| 月+日 | `dateOnly` | `9月15日` | `Sep 15` |
| 区间 | `dateRange` | `9月1日 – 9月15日` | `Sep 1 – Sep 15` |
| 时刻 | `timeOf` | `21:00` | `9:00 PM` |

`monthFull` 必须保持 `MMMM`：`MorphPerfUITests` 断言 `一月`，
`LanguageThemeUITests` 用 `MMMM` 反查月名。

---

## 五、Liquid Glass 的使用边界

沿用 WWDC26 session 8120 的结论：**内容区不用 Liquid Glass**（下方没有可折射的内容，
玻璃卡片会读作「浮在玻璃上的卡片」），内容卡片统一走 `diaryCard`。
玻璃属于**控件层**——浮在内容之上的导航与操作面。

这次补齐/修正的地方：

- **搜索框**（`GlassSearchField`）从 `diaryCard(cornerRadius: 28)` 改为玻璃胶囊。
  它原本是「不透明分组背景 + 28pt 圆角」：默认尺寸下碰巧看着像胶囊，一旦字号变大
  就不再是胶囊形状。
- **编辑器格式栏**（`FontToolbar`）是不透明圆角矩形，改为 `.glassEffect` 玻璃面板。
- **首页的日期胶囊、返回胶囊、未来日期 toast**：从不透明 `secondarySystemGroupedBackground`
  改为玻璃。
- **sheet 背景**：删掉了 4 处 `.presentationBackground(.ultraThinMaterial)`。
  iOS 26/27 的 sheet 默认就是新版玻璃外观，显式指定 `ultraThinMaterial` 等于把它
  退回旧观感。
- **修掉「不透明底 + 玻璃叠加」的写法**：`GlassSecondaryButton` 原本在
  `Capsule().fill(Theme.glassDim())` 之上再叠 `.glassEffect(...)`；`glassDim` 是
  *半透明* 的（浅色 45%），底下的玻璃仍然可见，所以保留（去掉后按钮几乎看不见）。
  `GlassPrimaryButton` 的品牌色实底同样**有意保留**：实底确实看不到折射，但实测
  只留 tint 会让主行动按钮明显变弱；玻璃在这里提供的是高光与边缘处理。
- **玻璃胶囊放进横向滚动里要留出上下余量**（2026-09-26 补）：`.buttonStyle(.glass)`
  的胶囊自带外沿高光与按压缩放，滚动视口贴着它就会把上下两条边裁掉 —— 搜索页的时间 /
  地点筛选行原本贴着，读起来像「玻璃被切了」。做法是在滚动内容里加
  `.padding(.vertical, 6)`（格式栏用的是 8），让视口比胶囊高一点。
- **设置页的说明控制在一行**（2026-09-26 补）：`rowLabel` / `switchRow` 的 `sub`
  是 13pt 左右、可用宽度约 170pt，**中文超过约 12 字就会折成两行**，整列卡片高度
  参差。现在长句都压到一行以内（如「在此时间之前写的内容，归入前一天」→
  「这个时间前算前一天」、「仅可修改或删除已有编辑块，历史日期不可新增内容」→
  「历史日期只能改，不能新增」）。以后新增说明也照这个长度写。
  （2026-10-01 核实：这里的 250pt 是错的，改成与 9.1 和
  `SettingsTests.testSettingsRowDescriptionsFitOneLine` 同一个数：170pt。）
- **不在玻璃上叠玻璃**（本轮补）：读日记的条目内搜索栏里，「上一个 / 下一个匹配」
  按钮原本是 `GlassIconButton`，即玻璃胶囊里的玻璃按钮——没有可折射的内容，只会
  读成一团。现在改为普通按钮，并补上此前缺失的无障碍文案
  （`read_search_prev` / `read_search_next`，原先只报符号名 `chevron.up`）。
- **格式栏的位置**（本轮补）：键盘弹起时贴在键盘上方 8pt；键盘收起时贴在
  Home Indicator 上方（`Screen.safeAreaBottom + 12`）。原来写死的 84pt 在没有
  键盘时会把格式栏悬在半空。**横竖屏一致**：都是一条横排玻璃条，并且**按内容宽度居中**
  （`ViewThatFits`：默认字号下一条放得下，大字号才退化成横滑），不拉满整行
  （2026-09-26 补，见 `docs/editor-format-behaviors.md` §3）。
- **分享面板**（`ShareSheetView`，本轮补）：日记页顶栏的分享按钮**一步**拉起一块
  `.large` sheet —— 上方是即将分享的长图预览（可滚动；手机横屏改成左右排，免得预览
  被挤没），下方直接嵌 `UIActivityViewController` 给出系统动作（拷贝 / 保存图像 /
  打印…）。旧流程是「弹出一个只有蓝色「分享」按钮的小菜单 → 再点一次才出系统面板」：
  多一步，而且点之前看不到要分享的是什么。面板自己不画标题行、也不画关闭按钮 ——
  预览图顶部就是日期、系统条目行就是文件名。
  三个实现细节：① 交给系统的是**临时文件 URL**，文件名带 `JustDiary-` 前缀
  （`JustDiary-2026-09-08.png`）：条目行因此显示真实缩略图与文件名（含大小），
  也多出「存储到文件」这类只吃文件 URL 的动作，同时避免和别的 App 的按日期文件撞名；
  ② iOS 26/27 的分享面板是**远程视图服务**渲染的（宿主视图 `ShareSheet.RemoteContainerView`），
  系统条目行右上角那个叉在视图树里根本不存在、它自己的 dismiss 又打在不存在的
  presentation controller 上（实测连点四个坐标毫无反应）—— 所以我们在它压着的位置
  放了一块 96×96 的透明点击区，**看得见的那个叉因此真的能关掉面板**；
  ③ 内容忽略底部安全区时，系统动作区至少要 340pt（SE 竖屏实测），否则最后一行
  「拷贝 / 保存图像 / 打印」的标签会被切一半。

品牌色是刻意固定的，不跟随系统「Liquid Glass 色调」滑块，这是预期行为。

---

## 六、放大字号时的溢出处理

- 固定高度改为 `minHeight`：`PageHeader`、首页 header、设置行、搜索筛选摘要行、
  位置选择行、**编辑器输入区**（160pt × 正文样式的动态字体系数）。
  （2026-10-01 核实：星期栏与周态标题行现在不在这条里 —— 它们是版面常量高度
  `CalendarLayout.weekdayHeaderH`（30）/ `dayTitleH`（40），文字靠
  `.diaryCalendarFont` 半速放大，见 2.3。）
- 单行不能换行的场合用 `lineLimit(1)` + `minimumScaleFactor`（0.6–0.9，视位置而定），
  宁可轻微缩小也不截断：设置行的尾值、足迹 5 列统计、日历大标题、周标题、
  悬浮胶囊上的短标签。其中**日历大标题、周标题、页头另外带 `allowsTightening`**
  （2026-10-01 核实：原文把四处写成同一套修饰符，但设置行尾值
  （`SettingsView.swift:190`）与足迹统计（`FootprintView.swift:111/118`）只有
  `lineLimit(1)` + `minimumScaleFactor`；`allowsTightening` 出现在
  `Components.swift:180`、`CalendarPaneViews.swift:59/70`、`HomeView.swift:149/642`、
  `MonthFlow.swift:232`）。
- 图标徽章按字号放大但**必须保持正方形**：`minWidth`/`minHeight` 放进 `HStack`
  会被行高拉成长条（这个 bug 出现过一次）。
- 底部为悬浮 tab bar 预留的间距改为 `TabBarClearance`，随字号放大——
  固定 120pt 在最大字号下会让最后一行压在 tab bar 下面。
- `PlaceholderTextView` 的占位文字高度原本写死 22pt，改为按字体行高计算。

---

## 七、整理时发现、尚未补的界面缺口

清理无用资源时顺带核实到两处「文案/能力已存在但没接上」的地方，记录在此：

1. **日历的可调节无障碍动作没有标签**。`MonthCanvas` 用
   `.accessibilityAdjustableAction` 支持上下切换日期，但没给这个动作命名；
   String Catalog 里原本有 `a11y_next_day`（后一天）与 `a11y_prev_day`（前一天）
   两条文案，**却没有任何代码引用**。它们已作为无用键删除，补上动作标签时按上面的
   语义重新添加即可（`git show bee42a5:JustDiary/Resources/Localizable.xcstrings` 可取回）。
2. **`month_jan`…`month_dec`、`week_monday`…`week_sunday` 共 19 条硬编码月/星期名**
   也没有任何引用——月名与星期名现在由 `DateFormatter` 按语言生成（见第四节）。
   这些键已作为无用资源删除，不要再往目录里加硬编码日期名。

---

## 八、清理结果：删了什么、为什么保留了什么

清理按两条依据做：**删除** = 全仓库零引用且删掉不影响行为；**保留** = 零引用但它是一个
能力或钩子，删不删属于产品决策。做过两轮：2026-09-15（界面资源）与 2026-10-01（精简代码）。

**已删除（2026-09-15）**

| 类别 | 内容 |
|---|---|
| 失效脚本 | `generate_xcstrings.py`（依赖的 `.lproj/Localizable.strings` 已不存在） |
| 过程脚本 | `validate_pbxproj.swift`（一次性调试用，零引用） |
| 本地化键 | 39 条零引用键；保留 `""` / `"%lld"` 两条 Xcode 从 `Picker("")`、`Text("\(h)")` 自动提取的占位条目 |
| 死代码 | `Animation.diaryMorph/diarySpring`、`AppTab.icon/label`（及未用的 `CaseIterable`）、`tintedGlass`、`Spacing.screen/cardGap/chip`、`Log.map/search`、`Haptics.medium`、`SQLite` 里重复的 `SQLITE_TRANSIENT`、`DiaryRepository.isFtsSupported/getFirstBlock/updateBlockLocation`、`DateUtil.addMonths/daysInMonth`、`L10n.weekdayShort`、`SearchViewModel.setLocFilter`、`MorphPerfUITests.attach` |

**已删除（2026-10-01，本轮精简）**

| 类别 | 内容 | 说明 |
|---|---|---|
| 设计组件 | `FlowLightOverlay` + `Theme.flowLightColor/flowMaskColor/flowLight` + `flowLight.colorset` | 卡片上的装饰流光，全仓零实例化；上一轮把它留作「产品决策」，本轮按「不再接」删除（`docs/animation-and-accessibility.md` §2.3 已同步） |
| 缓存清理钩子 | `DiaryImageStore.invalidate(src:)` / `invalidateAll()`、`ContentPartCache.invalidate()` | 三个入口零调用。**底层问题仍在**：图片缓存以 `src`（`images/img_<毫秒>.jpg`，非内容寻址）为键，「覆盖导入」理论上可能读到旧图；真要修是在导入后清一次缓存，届时再按需加回一个入口即可 |
| 只写不读 | `EditBlock.diaryId`、`PreviewItem.ratio`、整条「未来日期 toast」链路（`HomeView` 的 `showFutureToast` / `futureToastTask` / `showFutureDateToast()` / `.sensoryFeedback`、`DayContentView.showFutureToast`、`CalendarPaneViews` 传的 `{}`） | 都不影响行为：`diaryId` 只从行里读出来没人用；`ratio` 一路透传到 `PreviewItem` 后没人读（顺带把 `onImageTap` 从 `(String, CGFloat)` 简化成 `(String)`）；toast 的视图与状态都接好了、只是**没有任何触发点**，整条链子不可达 |
| 注入点 | `DiaryRepository.dbPathOverride` / `imagesDirOverride` | 被 `dbPath()` / `imagesDir()` 读，但全仓零赋值；删掉后这两个函数直接取 Documents |
| 遗留助手 | `Radius.concentric(outer:inset:)` | 零调用，规则本身留在第一节（嵌套圆角 = 外圆角 − 内缩量） |
| 零引用文案 | `read_start_time_loc`（只被已删的 `L10n.startLine` 用）、`share_image_placeholder`、`index_future_toast` | 删后 catalog 199 键 |
| 尺寸读法 | `Screen.height`（零调用）、`Screen.size` 收成 private | 版面判定一律走 `AdaptiveLayout` 的几何 |

**保留（零引用，但属于能力/钩子）**

1. **String Catalog 里的 `""` / `"%lld"`**：Xcode 从 `Picker("")`、`Text("\(h)")` 自动提取，
   删了下一次构建又会回来。
2. **第七节那两处界面缺口**（日历可调节动作没有标签、硬编码月/星期名不要再加）：
   它们是「能力存在但没接上」，不是垃圾，留着等对应功能一起补。

---

## 九、设置页与编辑页的取值控件

原来的语言 / 主题 / 周起始 / 导出范围都用 `confirmationDialog`（行动表）来选值。
行动表是**确认动作**用的（尤其是破坏性的），**选值应该用菜单**：更轻，而且会带当前值
的勾选。现在：

| 控件 | 形式 | 理由 |
|---|---|---|
| 语言 / 主题 / 周起始 / 导出范围 | `Menu` + 勾选 | 互斥取值的紧凑写法；iOS 26 下就是新的玻璃菜单外观 |
| 导入方式（跳过 / 覆盖） | 仍是 `confirmationDialog` | 它确认的是一个会覆盖已有数据的动作 |
| 位置精度（编辑页胶囊） | `Menu` + 勾选 | 同上；「重新获取位置」只留给新建片段（见 `docs/location-recording.md`） |
| 分享位置精度 | `Menu` + 勾选 | 四个值（隐藏 / 区县 / 城市 / 省份）；**精确地点与街道不在选项里**，见 `docs/location-recording.md` §五 |
| 新一天开始时间 | 单轮 `Picker`，标签用应用自己的时间文案 | 规则只有小时；旧实现多了一个改了也没用的分钟轮，且小时写死 `0…23`，12 小时制语言下读起来是错的 |
| 提醒时间 | `DatePicker(.hourAndMinute)` + `.wheel` | 由系统按应用语言与设备的 12/24 小时制格式化；旧实现同样写死 |

时间选择器的 sheet 用 `.medium` detent，不再写死 `.height(320)`——大字号下那个高度
会把轮盘和按钮裁掉。

### 9.1 设置行的说明必须一行放得下

行的形状是「图标 38 + 间距 12 ｜ 标题 + 说明 ｜ 值 + 箭头」，最窄的 iPhone（375pt）
扣掉页边距 / 卡片内边距 / 行内边距 / 图标 / 右侧的值与箭头之后，**说明那一列只剩约
170pt**。超了就会折成两行、行高跟着跳（`settings_share_loc_sub` 第一版写了 29 个字，
整整两行）。约定：

- 中文说明控制在 **12 字以内**（13pt 字号下约 156pt）；
- `SettingsTests.testSettingsRowDescriptionsFitOneLine` 按 170pt 逐个量 `settings_*_sub`，
  超了直接红 —— 加设置项时不用靠眼睛估；
- 只卡中文：英文同字号字宽更大，现有条目本来就在 200–260pt，靠 `rowLabel` 的
  `lineLimit(2)` 兜底。

---

## 十、自适应版面（手机竖屏 / 横屏）

完整的方案、设计稿与改动清单见 `docs/adaptive-layout-plan.md`。这一节只记与设计令牌有关的约定。

> **范围**：只做手机竖屏 / 横屏（竖屏交互完全不动；横屏首页左右分栏）。

**唯一的判定依据是「当前可用宽度 / 高度」**，不看 `UIDevice.idiom`、不看 orientation、不读
`UIScreen.main`。手机端只有两种形态：

| 形态 | 判定 | 首页 |
|---|---|---|
| 竖屏 | `height >= width` | 单栏（年 / 月 / 周三态 morph） |
| 横屏且两栏放得下 | `width > height && contentWidth >= 548.5` | 左右分栏：左月历 + 右选中日 |

阈值 548.5pt 是「主栏 260 + 详情栏 240 + 页边距 16×2 + 栏间距 16.5」，只用来挡住
「横屏但容器太窄」（分屏 / 折叠态）。**所有横屏 iPhone 都在它之上**（18 Pro 可用
750pt、SE 667pt），所以横屏首页一律是左右双列 —— 早先的 700pt 阈值会把 iPhone SE
挡在门外，让它只剩「竖屏版面横向拉长」。

导航形态用系统默认的底部浮条（`TabView` 没有额外的导航样式；2026-10-01 核实：只加了
`.tabBarMinimizeBehavior(.onScrollDown)`，`RootView.swift:65`）。**不要自己画第二套导航**，
也不要在 `TabView` 里再套 `NavigationSplitView`（会和页内已有的主从结构叠成两层导航）。

**手机横屏的系统占位是实测的**（真机 UI 测试探针）：

| 方向 | `safeAreaInsets` | 系统占位 |
|---|---|---|
| 竖屏 | T62 L0 B34 R0 | 浮条在底部；灵动岛在顶部居中 |
| 横屏 | T0 L62 B20 R62 | 浮条仍在**底部居中**（`tabBars` frame 实测 `(0, 338, 874, 64)`）；灵动岛转 90° 贴左边缘 |

浮条高度只与方向有关，**与机型无关**：竖屏 83 / 横屏 64（SE 横屏实测同样是
`(0, 311, 667, 64)`，尽管它没有 home indicator）。所以底部避让取
`AdaptiveLayout.tabBarClearance`，**不要**写成 `safeArea.bottom + 44` —— SE 横屏
`bottomInset = 0`，那样会少让 20pt，两栏最后一行被浮条压住。

所以横屏可用内容宽度是 `874 − 62 − 62 = 750pt`；几何原点**已经在安全区内**，
页面只加自己的 16pt 页边距，**不要再右移 `safeArea.leading`**。
这些值**必须从 `safeAreaInsets` 派生，不要写死**（见 `AdaptiveLayout`）。

**正文列的硬约束**：

1. 正文列限宽：阅读与编辑**同为 ≤ 660pt**（进出编辑时卡片不跳）。窄屏就是「屏宽 − 左右各 16pt 页边距」，
   不设上限时宽窗口会把正文拉成一行 100+ 个字。
2. **固定高度改为按可用空间派生，字号也要跟着走**。原来的横屏重叠就是「格子高度由可用
   高度算、`dayFont` 写死 20pt」造成的：402pt 高的横屏里格子只剩 39pt，装不下 20pt 日号
   + 11pt 农历 + 圆点。现在日历密度只有两档（月格含农历 → 月格，隐藏农历行）；
   隐藏农历那一档的行高下限是 **38pt**（44pt 是「日号 **+ 农历** + 选中圆」的高度，
   而这一档本来就不画农历），否则 iPhone SE 横屏的六行月格就放不下。
   2026-10-01：原来还有第三档「周条降级」，只判不画，已删除（见 `docs/adaptive-layout-plan.md` §3.1）。
3. 左右安全区**分别**读取（`safeAreaInsets.leading` / `.trailing`），不假设对称。
   折痕的「避免区」（`FoldAvoidance` 环境值）**是待做项**：iPhone Duo 之后要适配，
   届时在 `AdaptiveLayoutReader` 里读一次 `reservedRegion` 喂给它即可
   （`AdaptiveLayout` 的宽度分档是那套 API 的超集，不用改版面）。见
   `docs/adaptive-layout-plan.md` §4。

`TabBarClearance` 在浮条悬底时留出底部空间：横屏两栏的最后一行不能被浮条压住。

**设计稿即规范**：`docs/design/landscape/engine.js` 里的 `layoutFor()` 与上表同一条规则
（2026-10-01 已对齐：横屏 + 首页才分栏，主栏 = 容器宽 × 46%），`devices.js` 记录手机横屏的
系统占位常量，`mockup.css` 顶部的令牌与 `DesignSystem.swift` / `Assets.xcassets` 一一对应。
改令牌要两边同步。**设计稿只有手机端**——iPad / Mac 的宽屏稿已于 2026-10-01 删除。

**与折叠屏相关的 API**（`ArrangementView` / `UIArrangementViewController` / `onHingeChange` /
`GeometryProxy.reservedRegions`）留着给 iPhone Duo 适配用，**不要在 27.0 上提前接**：
它们都不在 Xcode 27.0 SDK 的公开接口里（SwiftUI 二进制有 `reservedRegions` 符号，
但 `.swiftinterface` 未声明），现在源码里也写不出来。

---

## 十一、日记页的进入方式（导航层级）

日历 → 某一天是**层级**关系，所以日记页是导航栈里**推进**出来的一页（从右往左进入、
可以从左边缘右滑返回），与 Apple 自己的「日历 → 某一天」「备忘录 → 某一条」一致；
以前它是 `fullScreenCover`（从下往上弹出、只能点「返回」关掉）。要点：

- **结构**：`RootView` 用 `NavigationStack(path: $appState.diaryPath)` 包住 `TabView`，
  日记页是它的 `navigationDestination`（`DiaryRoute` 一天一条路由）。推进时整块 tab 树
  （含底部浮条）一起被盖住，和以前的 cover 观感相同，不需要 `.toolbar(.hidden, for: .tabBar)`。
- **只给 tab 树挂 `.id(...)`**：语言 / 主题变化要重建 tab，但日记页在 `navigationDestination`
  里（`.id` 之外），设置一动不会把正开着的日记页重建掉。
- **顶栏自绘 ⇒ 导航栏藏起来**：`DiaryPageView.topBarOverlay` 就是顶栏，所以
  `.toolbar(.hidden, for: .navigationBar)`。代价是 UIKit 连
  `interactivePopGestureRecognizer` 一起停掉（隐藏导航栏时它内部 delegate 的
  `shouldBegin` 返回 false）——**实测隐藏导航栏后右滑完全不响应**，由
  `Views/Components/InteractiveBackSwipe.swift` 把内部 delegate 换成自己的判定接回来。
- **编辑态不给右滑**：正文还没落库，弹回等于无声丢掉这半篇（页面自己的规则是
  「先退出编辑，再退出页面」，有内容时点「返回」会先问一句）。判定就是 `vm.isRead`。
- **返回落到进来时的那个 tab**：从搜索结果点进去的，右滑回来还在搜索页（关键词与结果都还在）。
- 回归测试：`JustDiaryUITests/DiaryPageTransitionUITests`（盖住浮条、右滑返回、编辑态不给滑、
  从搜索结果推进后回到搜索页）。

---

## 十二、设置变化怎么传播（最小更新）

设置改动**不该重建界面**：以前 `uiTick` 被塞进 tab 树的 `.id(...)`，于是改任何一个
开关都会把四个 tab（连同搜索关键词、结果、滚动位置、开着的日记页）整个重建。
现在的分工是：

| 机制 | 含义 | 谁在用 |
|---|---|---|
| `RootView.treeIdentity` = `"\(AppLanguage.current)#\(AppConfigService.themeID)"` | 换 identity ⇒ 整棵树重建 | **只有语言与主题**：文案与配色是全局的，改一次就得全部重来（`DayDraw` 里缓存的文字颜色也一起换） |
| `DiaryRepository.bumpUiTick()` → `.uiTickChanged` | 便宜的广播：各页 VM `refreshSettings()`，由 `@Observable` 决定真正重画哪一块 | 周起始、自动记录时间（显示）、以及导入 |
| `DiaryRepository.bumpDiaryVersion()` → `.diaryVersionChanged` | 数据变了：各页重新读库 | 保存 / 删除 / 改开始时间后的 `day_key` 重算 / 导入 |
| 什么都不广播 | 只在**用到的那一刻**读设置 | 分享位置精度（`shareDiary()` 直接读 `SettingsStore.load()`）、历史编辑开关、自动插入地点 —— 没有常驻界面显示它们，而日记页每次打开都会新建 VM 读一遍最新设置 |

**已知观感问题（未修）**：设置页改成原位更新之后，**菜单类**设置项（语言 / 主题 /
周起始 / 分享位置精度 / 导出）选完值，紧接着上下滑动设置页，那一行会「先飘一下再
归位」；开关类的行没有这个现象。试过的办法都没效果：把菜单内容改成常量
（不用 `ForEach`）、给该行 `.transaction { $0.animation = nil }`；几何探针、逐帧对比
与 60fps 录屏也量不到位移（默认字号与 XXL 字号都试过，行高始终 56pt）。它只是观感，
不影响行为，暂时留着；真要修，方向大概是别让菜单行的值原位变化（例如把选择放到
sheet 里，或让整页在设置变化时重建 —— 后者会把上一节的最小更新又换回去）。

判断新设置项属于哪一档：

1. 它改变的是**每一处文案 / 配色**吗？→ 进 `treeIdentity`（目前只有语言与主题）；
2. 有**常驻**界面显示它，而且用户能在那个界面开着的时候改它吗？→ `bumpUiTick()`；
3. 只影响一次性的动作（分享渲染、进入编辑时的行为）？→ 什么都不广播，动作发生时读。

回归测试：`JustDiaryUITests/SettingsMinimalUpdateUITests` —— 在搜索页留下关键词与结果，
再去设置页改「一周从哪一天开始」和「分享位置精度」，回搜索页状态必须还在（没被重建），
同时首页星期栏第一格立刻从「一」变「日」（该生效的照样立刻生效）。把 tick 塞回
`.id` 时这条用例会红（实测）。
