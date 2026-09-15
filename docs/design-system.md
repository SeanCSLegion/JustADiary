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

**嵌套圆角必须用 `Radius.concentric(outer:inset:)`**，即内圆角 = 外圆角 − 内缩量。
这是 Apple 对「圆角里套圆角」的规则；直接把内外圆角设成同一个值会产生视觉上的
「尖角内衬」。分享长图渲染器（`ImageShareService`）也走同一套令牌，导出的卡片与
应用内卡片观感一致。

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

| 设计字号 | 34+ | 32 | 24 | 20 | 18 | 16 | 15 | 13 | 12 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|
| AX5 实际 | — | 44.8 | 34.8 | 29 | 27 | 24.8 | 24 | 21.5 | 20.4 | 19.3 |

这是**有意的偏离**，理由写在上限函数的注释里。调整上限时请重新核对这张表是否仍然单调。

### 2.3 日历是唯一的例外

日历用 `Canvas` 绘制，格子尺寸由屏幕决定，所以日号走 `calendarMultiplier`
（半速）；星期栏走 `.diaryCalendarFont(_:)`，同样是半速，避免撑破固定高度的条带。

### 2.4 UIKit 侧（编辑器 / 阅读器）

`PartsCodec` 与 `ReadTextView` 在 SwiftUI 之外构建 `NSAttributedString`，无法使用
`.diaryFont`，改为接收显式的 `DynamicTypeSize`。`RootView` 通过
`\.diaryDynamicTypeSize` 下发；**`fullScreenCover` 内的 `DiaryPageView` 需要单独注入**
（presentation 不会从更内层的 `.environment` 继承），这一点已在 `RootView` 注释说明。

---

## 三、编辑器往返不变量（最重要）

`parts(from:)` 是**从字号反推块类型**的：`>= 22` 判为 h1、`>= 18` 判为 h2，
其余为段落；`TextRun.size` 还会写进日记 JSON。

所以编辑器文本存储里必须是**设计字号（22 / 18 / 15 / 13）**，绝不能是实际绘制的
字号：一旦开了动态字体，15pt 段落会被画成 24pt，存回时就会被判成标题，把日记改写掉。

做法：
- 每段 run 同时带 `.font`（按用户字号解析后的绘制字体）和 `.diaryDesignSize`（未缩放的设计字号）；
- `parts(from:)` 优先读 `.diaryDesignSize`；
- 该属性缺失时的兜底必须**精确**，不能是近似反解。UIKit 会按固定的一组键从光标处
  重新同步 `typingAttributes`，**自定义键会在输入第二个字符起丢失**，此时若用除法
  近似反解，落库的 `size` 会逐次漂移（实测 15 → 18.75），而 18.75 ≥ h2 的 18，
  再存一次就真的把段落变成标题。因此兜底先拿绘制值与编辑器自己产出的字号做
  **精确匹配**（`EditorDesignSize.authored`），只有导入文档的自定义 run 字号才走除法。

回归测试：`JustDiaryUITests/EditorTypeSizeUITests`，在最大辅助功能字号下执行
「新建→保存→再次编辑保存」三轮，覆盖的正是这条不变量。它只驱动 UI；落库结果需要
按文件头的说明从模拟器容器里读 `edit_block.content_json` 核对（预期全部 `type=p`、
`size=15`）。

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
- **修掉「不透明底 + 玻璃叠加」的写法**：`GlassPrimaryButton` 原本在
  `Capsule().fill(Theme.primary())` 之上再叠 `.glassEffect(...tint:)`，
  `GlassSecondaryButton` 同理叠了 `glassDim`。不透明底之上看不到任何折射，
  玻璃效果等于白写；现在只留 tint / 玻璃本身。

品牌色是刻意固定的，不跟随系统「Liquid Glass 色调」滑块，这是预期行为。

---

## 六、放大字号时的溢出处理

- 固定高度改为 `minHeight`：`PageHeader`、首页 header、设置行、搜索筛选摘要行、
  位置选择行、周标题行。
- 单行不能换行的场合（设置行的尾值、足迹 5 列统计、日历大标题、周标题）
  用 `lineLimit(1)` + `minimumScaleFactor` + `allowsTightening`，宁可轻微缩小也不截断。
- 图标徽章按字号放大但**必须保持正方形**：`minWidth`/`minHeight` 放进 `HStack`
  会被行高拉成长条（这个 bug 出现过一次）。
- 底部为悬浮 tab bar 预留的间距改为 `TabBarClearance`，随字号放大——
  固定 120pt 在最大字号下会让最后一行压在 tab bar 下面。
- `PlaceholderTextView` 的占位文字高度原本写死 22pt，改为按字体行高计算。
