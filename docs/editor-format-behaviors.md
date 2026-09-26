# 编辑页格式按钮行为规范（现状 / 目标对照）

日期：2026-09-26 · 环境：Xcode 27 / iOS 27 SDK · 设备：iPhone 18 Pro 模拟器（iOS 27.0）

本文只讲**编辑模式**（`DiaryPageView` 的 `!vm.isRead` 分支）里格式栏的每一个按钮：

- 点下去改什么、作用范围多大（当前行 / 选区 / 只影响后续输入）；
- 「取消」（再点一次、或菜单里选回正文）改什么；
- 换行之后样式怎么走。

字体模型（语义样式 + 跟随系统字号）、存储格式 v2 见 `docs/editor-typography.md`。
本文不重复那部分，只补**作用域（scope）**这一层——也就是「影响范围是否符合预期」。

> 结论先说：按钮的作用域由 `RichEditorController` 决定，实现集中在
> `JustDiary/Views/Diary/RichTextEngine.swift`。其中 `paragraphRanges(covering:)`
> 一段的范围判定有缺陷，是「样式没及时生效 / 影响范围不对」的主要来源（见第五节 B1）。
>
> **状态：R1–R4 已按本文实现并验证**（B1–B10 全部修复，见第五、六、七节）。
> 第二、三节的表格是**规范**（应该是什么样），第四、五节保留**修复前的现状**，
> 便于回看问题从哪来。

---

## 一、术语

| 术语 | 含义 | 代码位置 |
|---|---|---|
| **行 / 段落** | 以换行结尾的一段文字。编辑器里一行 = 一个 `ContentPart`（图片除外） | `PartsCodec.parts(from:)` |
| **字符样式** | 加粗 / 斜体 / 删除线 / 下划线，存在 `TextRun` 上，可以只覆盖一行里的几个字 | `TextRun` |
| **行样式（段落样式）** | 大标题 / 小标题 / 正文 / 引用 / 列表 / 待办，存在 `ContentPart.style` 上，**整行生效** | `ContentPartStyle` |
| **行首标记** | 列表（`circle.fill`）/ 待办（`square`）行首的附件字符（U+FFFC），是真实字符，不是画出来的装饰 | `MarkerAttachment`、`PayloadAttachment` |
| **空行** | 当前行还没有任何文字（刚按回车后那一行，或整篇为空） | `paragraphIsEmpty(in:location:)` |
| **typingAttributes** | 「下一个输入字符」的样式。光标移动时 UIKit 会按光标处文字的属性重新同步，`diaryDesignSize` / `diaryBlockStyle` 两个自定义键会丢，靠字号反推兜底 | `RichEditorController.typingAttributes(for:)`、`EditorFont.designSize(of:typeSize:)` |
| **作用域** | 一次点击影响的范围：整行 / 选中各行 / 选中各字 / 只影响后续输入 | 本文的主角 |

三种作用域，后文一律用这三个词：

- **打字态**：不改动任何已有文字，只改「下一个输入字符」的样式（`typingAttributes`）。
- **行作用域**：光标所在那一整行（含已输入文字）。
- **选区作用域**：选区覆盖到的每一个字 / 每一行。

---

## 二、目标语义（本次确认）

### R1 字符样式：加粗 / 斜体 / 删除线 / 下划线

| 情形 | 行为 |
|---|---|
| 无选区（只有光标） | **打字态**。只改下一个输入字符的样式，**绝不改动已输入的任何字**；按钮高亮反映该状态 |
| 有选区 | **选区作用域**。选中区内的文字统一设置：已经全开 → 全关；否则 → 全开。选区外不动 |
| 取消 | 同上：无选区时只影响「之后输入的字符」，有选区时只影响选中区 |
| 换行 | 光标移动后状态由 UIKit 按光标处文字重新同步（这是系统行为，不额外干预） |

关键：选区**统一**处理，不能「逐段各自取反」（否则混合选区会变成一半加粗、一半取消，见 B5）。

### R2 行样式·文本类：大标题 / 小标题 / 正文 / 引用

| 情形 | 行为 |
|---|---|
| 无选区 | **行作用域**：整行切到该样式。行内已有的加粗/斜体保留 |
| 无选区、且当前行是空行 | **打字态**：不动任何已有文字（尤其**不动上一行**），只让「之后输入的文字」是该样式 |
| 有选区 | **选区作用域**：选中的每一行都切到该样式 |
| 换行 | 新行**延续**该行样式（引用延续底色，标题延续字号）；要在新行取消，就选菜单里的「正文」或再点一次「引用」 |
| 取消 | 菜单选「正文」/ 再点「引用」：只作用于当前行（或选中各行）。空行上取消 = 打字态，**上一行保持不变** |
| 互斥 | 列表 / 待办行切成文本行样式时，行首标记被移除；引用强制左对齐（与居中互斥） |
| 空行 | 空行不入库（`PartsCodec.parts(from:)` 跳过空行），所以「空行」只存在于编辑过程中的光标位置 |

### R3 行样式·标记类：列表 / 待办

| 情形 | 行为 |
|---|---|
| 无选区 | 给当前行加/去行首标记。**加**标记时该行先回到正文（去掉大标题/小标题/引用/居中），再去/加标记 |
| 有选区 | **选区作用域**：选中的每一行统一加/去标记（方向由光标所在行决定） |
| 换行（当前行有文字） | **另起一项**：新行自动带同种标记（待办新项为未完成），光标落在标记之后 |
| 换行（当前行只有标记、没有文字） | **结束列表**：标记被移除，这一行留作空正文行（它自己的换行还在）；再按一次回车得到新的空行 |
| 取消 | 再点一次按钮：只去当前行（或选中各行）的标记。**之前的行不受影响** |
| 列表 ⇄ 待办 | 直接切换（移除旧标记、插入新标记），不产生两种标记并存的行 |

### R4 居中

| 情形 | 行为 |
|---|---|
| 无选区 | **行作用域**：当前行居中/取消居中 |
| 无选区、当前行是空行 | **打字态**：只改后续输入（既有实现已正确，本次只补选区一致性） |
| 有选区 | **选区作用域**：选中每一行 |
| 互斥 | 列表 / 引用 / 待办行上按钮置灰；居中不能与它们共存 |
| 居中空行上回车 | 被忽略（既有设计，防止连出一串空居中行），见 `shouldBlockNewline(at:)` |

---

## 三、格式栏按钮总表

格式栏 = `FontToolbar`（`RichTextView.swift`），从左到右共 9 个按钮 + 2 条分隔线。
「修复前」列是本次改动**之前**的行为，❌ 标注问题编号（B1–B11 的含义见第五节，
现在都已修复）；「目标」列即第二、三节的规范，也是当前实现。

**格式栏的朝向与位置**：始终是**横排**一条，贴在键盘上方 8pt（键盘收起时贴
Home Indicator 上方）。横屏曾经改成「竖排贴右侧」的面板 —— 9 个按钮竖排约 454pt，
比 iPhone 18 Pro 横屏的可用高度 402pt 还高：整条被屏幕裁掉、又贴在全屏底部中间、
与正文列对不上，一进编辑就看不出那是格式栏（见 B11）。参照 Apple 备忘录：
键盘上方那条工具栏在横竖屏都是横向、可横向滑动的，iOS 26 起按钮更多（18 个）
也是横滑 + 按上下文排序，从不竖排到侧边。它同时**按内容宽度居中**（`ViewThatFits`：
默认字号下 9 个按钮约 360pt，一条放得下；只有大字号放不下时才退化成横滑），
不再拉满整行。

| # | 按钮 | SF Symbol | 作用域 | 点一下（修复前） | 再点一下 / 取消（修复前） | 改动已输入文字？ | 换行后 | 修复前 |
|---|---|---|---|---|---|---|---|---|
| 1 | 样式菜单：大标题 / 小标题 / 正文 | `textformat.size` + `chevron.down` | 行样式（文本类） | 光标行整行变成所选样式，且后续输入延续该样式 | 选「正文」= 取消；同样作用于光标行 | 是（整行） | 新行延续 | ❌ B1 / B2 |
| 2 | 居中 | `text.aligncenter` | 行样式（对齐） | 光标行居中（空行只改后续输入） | 再点一次：当前行取消居中 | 是（整行） | 新行延续居中 | ❌ B3（忽略选区） |
| 3 | 列表 | `list.bullet` | 行样式（标记） | 当前行去掉标题/引用/居中，行首插入 `•` | 再点一次：只去掉当前行的 `•` | 是（整行） | **不延续**（回到正文） | ❌ B4 / B6 |
| 4 | 引用 | `text.quote` | 行样式（文本类） | 当前行加引用底色、字号降到 15、左对齐、去掉行首标记 | 再点一次：当前行恢复正文 | 是（整行） | 延续引用 | ❌ B1（空行时连上一行一起改） |
| 5 | 待办 | `checklist` | 行样式（标记） | 当前行去掉标题/引用/居中，行首插入 `☐` | 再点一次：只去掉当前行的 `☐` | 是（整行） | **不延续** | ❌ B4 / B6 |
| 6 | 加粗 | `bold` | 字符样式 | 无选区：只让**之后输入**的字加粗；有选区：选区逐段各自取反 | 同左：无选区只影响后续输入 | 无选区：否；有选区：是 | 由光标处文字决定 | ❌ B5（选区逐段取反） |
| 7 | 斜体 | `italic` | 字符样式 | 同上（CJK 用 0.24 斜切矩阵，中文也能看出来） | 同左 | 同上 | 同上 | ❌ B5 |
| 8 | 删除线 | `strikethrough` | 字符样式 | 同上 | 同左 | 同上 | 同上 | ❌ B5 |
| 9 | 下划线 | `underline` | 字符样式 | 同上 | 同左 | 同上 | 同上 | ❌ B5 |

按钮通用细节：

- 每个按钮点击时都先 `Haptics.tap()`；工具栏 `onTap` 会把焦点还给编辑器（`becomeFirstResponder`），避免点完按钮键盘收起。
- 高亮（active）来自 `controller.activeStyles()` / `isCenterActive()` / `isListActive()` / `isQuoteActive()` /
  `isTodoActive()` / `currentBlockStyle()`，由 `formatTick` 驱动重算（`RichTextView.swift` 的 `.onChange(of: controller.formatTick)`）。
- 有选区时，字符样式的高亮只看**选区首字符**（B8）；行样式的高亮只看**选区起点那一行**（B8）。
- 列表 / 引用 / 待办三者互斥，且都与居中互斥：处于这三类行上时，「居中」按钮 `disabled`（`blockStyleActive`）。

---

## 四、逐按钮：现状 → 目标

### 1. 样式菜单（大标题 / 小标题 / 正文）

- 入口：`FontToolbar.styleMenu` → `RichEditorController.applyBlockStyle(_:)`。
- 现状：`paragraphRanges(covering: tv.selectedRange)` 取「光标或选区碰到的行」，逐行 `restyle`
  （保留加粗/斜体，改写字号与 `.diaryBlockStyle`，行距/段后距按样式重算，居中保留），
  最后把 `typingAttributes` 设为该样式（所以后续输入延续）。
- **问题 B1**：`paragraphRanges` 把「上一行」也算进去了。原因见 B1。
  于是「在新空行上选大标题」实际改的是**上一行**，而当前行要到输入第一个字才生效。
- **问题 B2**：因此在新空行上点样式，视觉上「没生效」（当前行没字可改），却把上一行改了；
  再选回「正文」时又把上一行改回去。这正是「样式没有及时生效 / 影响范围不符合预期」的观感来源。
- 目标：见 R2。空行 → 纯打字态；有文字的行 / 选中的行 → 全部切换；上一行不被波及。

### 2. 居中

- 入口：`toggleCenter()`；判定 `isCenterActive()`；空行上回车被 `shouldBlockNewline(at:)` 吃掉。
- 现状：当前段落居中，随后 `typingAttributes` 的 `paragraphStyle.alignment` 也跟着改（新行延续居中）。
  空行（`paragraphIsEmpty`）走「只改 typingAttributes」分支，不碰相邻行——**这一条是对的**。
- **问题 B3**：只认 `tv.selectedRange.location` 一个点，选中多行时只有起点那一行居中；
  而样式菜单 / 引用同样操作却作用于整个选区，两者不一致。
- 目标：见 R4，补齐选区作用域。

### 3 / 5. 列表 / 待办（行首标记）

- 入口：`toggleList()` / `toggleTodo()` → `toggleMarker(kind:)`；状态 `isListActive()` / `isTodoActive()`。
- 现状：
  - 取光标行的 `paragraphRange(in:around:)`（**空行处理是对的**，会返回行首的零宽范围）；
  - 打开时先 `restyle(...to: .body, cancelCenter: true)`（丢掉标题/引用/居中、并移除另一种标记），
    再在行首插入 `MarkerAttachment`；
  - 关闭时只在确认行首是该种标记时删掉那一个字符；
  - 最后把 `typingAttributes` 重置为正文。
- **问题 B4**：忽略选区，只作用于光标那一行（选中三行点列表，只给一行加标记）。
- **问题 B6**：换行**不延续**（`typingAttributes` 被重置为正文），所以「换行以后再取消」这件事
  在列表/待办上根本走不到；引用却会延续，三者行为不一致。
- **问题 B9（次要）**：只有标记、没有文字的「空项」会被 `PartsCodec.parts(from:)` 当成
  `items: [""]` 存下来（空行点一下列表再保存 → 库里多一个空待办/空列表项）。
- 目标：见 R3（选区作用域 + 换行续项 + 空项回车结束列表 + 空项不入库）。

### 4. 引用

- 入口：`toggleQuote()`；状态 `isQuoteActive()`（读段落底色）。
- 现状：与样式菜单同一套 `paragraphRanges` + `restyle`，切换 `.quote` / `.body`；
  引用行会去掉行首标记、强制左对齐、加底色；`typingAttributes` 设为引用（所以换行延续）。
- **问题 B1 / B2**：与样式菜单完全相同——在空行上点引用，改的是上一行；
  这也是「换行以后再取消，结果把之前那段引用的底色也去掉了」的直接原因。
- 目标：见 R2（空行只改后续输入；取消只影响当前行）。

### 6–9. 加粗 / 斜体 / 删除线 / 下划线

- 入口：`toggleBold()` / `toggleItalic()` → `toggleFontStyle(_:)`；`toggleStrike()` / `toggleUnderline()` →
  `toggleLineStyle(key:)`。
- 现状：
  - 无选区：只改 `typingAttributes`（**符合 R1**：不动已输入文字，只影响后续输入）；
  - 有选区：`apply` 里对每个子区间**各自取反**——已经是粗的变不粗、不是粗的变粗。
- **问题 B5**：混合选区的结果是「一半加粗、一半取消」，与「选区统一设置」的预期不符。
- 目标：见 R1（先判定整段是否全开，再统一设置）。
- 说明：无选区时，`diaryDesignSize` / `diaryBlockStyle` 会被 UIKit 重新同步掉，靠字号反推兜底，
  这条既有链路见 `docs/editor-typography.md` §2；本次不改。

---

## 五、问题清单

| 编号 | 严重度 | 位置 | 现象 | 原因 | 期望 | 本次处理 |
|---|---|---|---|---|---|---|
| **B1** | 高 | `RichTextEngine.swift` `paragraphRanges(covering:)` | 换行后在新行点「大标题 / 小标题 / 引用」，**上一行被一起改**；取消时上一行被一起改回 | 命中判定写成 `range.location >= start && range.location <= lineEnd`。上一行的 `lineEnd`（独占末尾）**正好等于**本行起点，所以光标落在任何一行的行首（回车后的默认位置）都会命中上一行 | 光标只作用于光标所在段落；空段落只改打字态 | ✅ 修 |
| **B2** | 高 | 同 B1 的连带 | 空行上选样式「没反应」 | 空行没有文字可改，真正被改的是上一行 | 与 B1 一起解决；空行上通过样式菜单的选中态给出反馈 | ✅ 修（随 B1） |
| **B3** | 中 | `toggleCenter()` | 选中多行点居中，只有第一行居中 | 只用 `selectedRange.location` 取当前段落 | 选中每一行都居中 | ✅ 修 |
| **B4** | 中 | `toggleMarker(kind:)` | 选中多行点列表/待办，只有光标那一行有标记 | 只用 `paragraphRange(in:around:)` | 选中每一行统一加/去标记 | ✅ 修 |
| **B5** | 中 | `toggleFontStyle(_:)` / `toggleLineStyle(key:)` | 混合选区点加粗 → 一部分加粗、一部分取消 | 对每个子区间各自取反 | 整段统一：全开→全关，否则全开 | ✅ 修 |
| **B6** | 中 | `toggleMarker(kind:)` | 列表/待办换行后回到正文，引用却延续；三者不一致 | `typingAttributes` 被重置为正文，且标记是真实字符，UIKit 的换行无法自动带过来 | 三者都延续；空项回车结束该样式 | ✅ 修 |
| **B9** | 低 | `PartsCodec.parts(from:)` | 空行点「列表」后直接保存 → 库里存下 `items: [""]` 空项 | 只跳过「空白文本行」，没跳过「只有标记的行」 | 只有标记没有文字的行不入库 | ✅ 修 |
| **B10** | 高（数据丢失） | `RichTextView.updateUIView` | 编辑到一半旋转屏幕/宽度变化 → 回到进入编辑时的内容，刚输入的字没了 | 宽度变化时用 `loadParts`（进入编辑时的快照）整块重载编辑器 | 宽度变化只重排图片，不动文本 | ✅ 修 |
| **B8** | 低 | `activeStyles()` / `isCenterActive()` / `currentBlockStyle()` | 混合选区时按钮高亮只按选区首字符算，可能误导 | 只探一个点 | 字符样式改为「整段全开才高亮」，与 B5 的统一语义一致 | ✅ 修 |
| **B18** | 中 | `DiaryPageView` | 进出编辑时整张卡片会变宽 / 变窄：阅读列 660、编辑列 620，横屏差 40pt（SE 横屏差 15pt） | `contentColumn(vm.isRead ? 660 : 620)` | 两个模式共用 660；输入区宽度仍差 4pt（卡片内边距 12 vs 10） | ✅ 修 |
| **B17** | 高 | `DiaryViewModel` / `DiaryPageView` | **键盘收不回来**：编辑页没有任何收起键盘的交互，顶栏按钮又被触控键盘压住，用户没法先收键盘再选文字 | 编辑器只自己处理键盘高度，没有 `resignFirstResponder` 的触发点 | 点内容空白 / 顶栏空白收起键盘，下拉内容也可以；并关掉 `autoFocusEditor`（免得视图重建后又把键盘叫回来） | ✅ 修 |
| **B15** | 中 | `DiaryPageView` | 顶栏会离开屏幕：横屏键盘弹起时「返回 / 插入图片 / 保存」实测在 y = −51 | 两件事叠在一起：① 顶栏原本挂在 ScrollView 的 `safeAreaInset` 上，`scrollTo` 一带内容滚动就跟着跑；② 触控键盘弹起时横屏可用高度只剩 402pt，SwiftUI 仍会把整页往上推（实测滚动视图变成 457pt 高、整体上移 55pt） | ① 已修：顶栏移出滚动视图，改成 ZStack 顶对齐的 overlay；② **接受为已知限制**，靠 B17 的「点空白 / 下拉收键盘」把顶栏拿回来（用户要的就是这条路径，硬撑着一屏显示反而没意义） | ✅ ① 修 / ② 记录 |
| **B16** | 中 | `RichEditorController.refitImages` | 编辑模式横竖屏切换后，图片大小不跟着列宽变 | 重排图片时仍用旧的 `min(存储宽, 可用宽)`，旋转后又被夹回存储宽度 | 与 `PartsCodec` 同一条规则：宽度 = 列宽，存储对只作比例 | ✅ 修 |
| **B12** | 中 | `DiaryViewModel.handleBack` | 编辑到一半点返回，整个日记页被关掉、掉回首页日历 | `!isRead` 时直接 `onDismiss()` | 返回只退出**编辑**，回到这一天的阅读页；有未保存内容仍先确认 | ✅ 修 |
| **B13** | 中 | `PartsCodec` / `insertImage` / `DiaryImageView` | 横屏下图片不随列宽放大（阅读区还多出上下空带），编辑区图片靠左 | 宽度取 `min(存储宽, 可用宽)` 且段落左对齐；阅读区外层比例盒按列宽、内层图按存储宽 | 图片按列宽等比放大并居中；存储的 `w/h` 只当比例 | ✅ 修 |
| **B14** | 低 | `FontToolbar` | 横屏格式栏拉满整行，比正文列还长 | `ScrollView` 自己占满可用宽度 | 按内容宽度居中（`ViewThatFits`：放得下就不滚，放不下才横滑） | ✅ 修 |
| **B11** | 高 | `DiaryPageView` / `FontToolbar` | 横屏进编辑时格式栏是**竖排**的一列，比屏幕还高：整条被裁掉、贴在全屏底部中间，与正文列对不上 | `fontToolbarVertical = layout.splitsMasterDetail`，横屏走 `VStackLayout`；9 个按钮竖排约 454pt > 横屏可用高度 402pt | 与备忘录一致：横竖屏都是键盘上方的**横排**一条 | ✅ 修（`editor.formatBar` 的 frame 断言守住） |

### B1 的细节（为什么「行首」这个位置这么常见）

```
文本："第一行\n第二行"，光标在 offset 4（第二行行首，也就是按回车后的默认位置）
paragraphRanges 的循环：
  第 1 行 = NSRange(0, 4)    // 含换行，lineEnd = 4
  第 2 行 = NSRange(4, 4)
  光标 4 对第 1 行：4 >= 0 && 4 <= 4 → 命中 ❌（上一行被改）
  光标 4 对第 2 行：4 >= 4 && 4 <= 8 → 命中 ✅
```

同一段文本，光标在 offset 3（第一行末尾）时只命中第 1 行，看起来是对的；
所以这个 bug 只在「光标正好在行首」时出现——而这恰好是**每次按回车之后**的位置，
也是「换行以后再取消」必经的位置。文本末尾追加一个换行（`"...\n"`，光标在末尾）同理：
第 1 行 `NSRange(0, len)` 被命中，「新空行」反而没有段落可言。

---

## 六、修复实现与验证

| 编号 | 实现（`RichTextEngine.swift` 除注明外） | 覆盖测试（`JustDiaryTests/EditorFormatBehaviorTests`） |
|---|---|---|
| B1 / B2 | `paragraphRanges(covering:includeEmpty:)` 重写：光标只取光标所在段落；空段落返回行首零宽范围，文本类样式据此走「只改后续输入」；选区仍按相交取每一行 | `testStyleMenuOnEmptyLineLeavesPreviousLineAlone`、`testCaretAtLineStartStylesOnlyThatLine`、`testQuoteOnEmptyLineLeavesPreviousLineAlone`、`testQuoteCancelOnNewLineKeepsPreviousQuote` |
| B3 | `toggleCenter()` 改为遍历 `paragraphRanges`；`setTypingAlignment` 统一改打字态（并改为拷贝 paragraphStyle，不再原地改共享对象） | `testCenterAppliesToEverySelectedLine`、`testCenterOnEmptyLineOnlyChangesTypingAttributes` |
| B4 | `toggleMarker(kind:)` 改为遍历 `paragraphRanges(covering:includeEmpty: true)`，倒序插入/删除；光标按净长度变化补偿，保证落在标记之后 | `testListToggleAppliesToEverySelectedLine`、`testListToggleOffOnNewLineKeepsPreviousItem`、`testListAndTodoSwapInPlace` |
| B5 | `toggleFontStyle` / `toggleLineStyle` 先判定「整段是否全开」（`selectionHasTrait` / `selectionHasStyle`），再对整段统一设置 | `testBoldTurnsOnForWholeMixedSelection`、`testBoldTurnsOffForWholeSelection`、`testStrikeTurnsOnForWholeSelection`、`testCaretOnlyChangesTypingAttributes`、`testSelectionSurvivesAFormatToggle` |
| B6 | 新增 `handleReturn(at:)`（`RichTextView` 的 `shouldChangeTextIn` 里调用）：有文字的项→插入「换行 + 同种标记」（待办新项未完成）；空项→`removeMarker` 结束该样式；空引用行同样结束引用 | `testReturnOnListItemStartsANewItem`、`testReturnOnTodoItemStartsAnUndoneItem`、`testReturnOnAnEmptyQuotedLineEndsTheQuote`、`testReturnOutsideALineStyleIsLeftToUIKit` |
| B8 | `activeStyles()` 有选区时改为「整段全开才高亮」，与 B5 的统一语义一致 | `testMixedSelectionReportsNoActiveTrait` |
| B9 | `PartsCodec.parts(from:)` 跳过「只有标记、没有文字」的行 | `testMarkerWithoutTextIsNotPersisted`、`testTrailingMarkerIsNotPersisted` |
| B10 | `RichTextView.updateUIView` 宽度变化时不再 `load(parts:)`，改调新增的 `refitImages(maxWidth:)`：只重排附件 bounds 与图片，文本与光标不动 | `testRefitImagesLeavesTextAndCaretAlone` |
| B11 | 删掉 `fontToolbarVertical` 环境值与 `FontToolbar` 的竖排分支（连同 `DiaryPageView` 的注入），格式栏恒为横排；整条挂 `editor.formatBar` 标识供 UI 测试断言 | `LandscapeLayoutUITests.testLandscapeEditorFormatBarStaysHorizontal`（横屏断言：条形宽 > 高×2、宽 > 300、不出屏、按钮都在屏内、可横滑到最后一个按钮） |

| B12 | `handleBack` 在 `!isRead` 时改为 `showRead()`（回到阅读态），确认放弃后才丢弃这次编辑；空编辑器直接回到阅读态 | `EditorFlowUITests.testBackFromTheEditorReturnsToTheDaysReadingView`、`…testBackFromAnEmptyEditorAlsoReturnsToTheReadingView` |
| B13 | 图片按列宽等比排版（`PartsCodec` 的 `w = maxW`、`insertImage` 去掉 343pt 上限）、段落 `.center`；`DiaryImageView` 去掉 `GeometryReader` + 固定宽，改成按比例填满 | `testImageFillsTheColumnAndStaysCentred`、`testImageStoredSizeIsAnAspectRatioNotALayoutSize`、`testReaderImageFillsTheWidthItIsGiven` |
| B14 | 格式栏改成 `ViewThatFits { barRow; ScrollView { barRow } }`，按钮间距 6 → 4（默认字号下 9 个按钮约 360pt，整条放得下） | `EditorFlowUITests.testFormatBarFitsInOnePieceAtTheDefaultTextSize` |

| B18 | `DiaryPageView` 的正文列统一成 `contentColumn(660)`，不再按 `isRead` 分支 | `EditorFlowUITests.testReadAndEditContentColumnsHaveTheSameWidth`（竖屏 / 横屏都比一遍阅读与编辑的输入区） |
| B17 | `DiaryViewModel.dismissKeyboard()`（让当前 first responder 辞职 + 关掉 `autoFocusEditor`）；`DiaryPageView` 的内容空白与顶栏空白各挂一个 `onTapGesture`，并加 `.scrollDismissesKeyboard(.interactively)`；内容末尾两块透明占位 `.allowsHitTesting(false)`，否则手势落不到内容上 | `EditorFlowUITests.testTappingBlankSpaceDismissesTheKeyboard`（竖屏点卡片与格式栏之间的空白、横屏点顶栏中间空白，键盘都要收起且顶栏按钮回到屏内） |
| B15 | `DiaryPageView`：顶栏从 ScrollView 的 `safeAreaInset` 改成 ZStack 里的 `topBarOverlay`（顶对齐 + `onGeometryChange` 量高度给内容当 padding） | `EditorFlowUITests.testTappingBlankSpaceDismissesTheKeyboard` 里的「滚动后顶栏位置不变」断言（横屏收键盘之后测） |
| B16 | `refitImages` 的宽度改成 `max(60, maxWidth)`，与 `PartsCodec` 一致 | `EditorSpacingTests.testImageFillsTheColumnAndStaysCentred`（同一条规则：列决定宽度） |

行距 / 段距 / 图片留白的模型与实测数值不在本文范围，见
`docs/editor-typography.md` 第五节（含 `JustDiaryTests/EditorSpacingTests`）。

设计取舍（值得回看）：

- **空行不走「行作用域」**：空行没有文字，任何「改这一行」的动作都会变成改相邻行。所以空行统一降级为打字态，
  反馈交给样式菜单的选中态与按钮高亮。
- **标记换行必须自己处理**：标记是真实字符（U+FFFC），UIKit 的 `\n` 带不过去；
  而 `typingAttributes` 里放附件不会插入字符。因此 `handleReturn` 在 `shouldChangeTextIn` 阶段直接消费这次回车。
- **「第二次回车结束行样式」只在空项上生效**：光标停在「上一行是列表项」的空行上时**不**自动续列表——
  否则「回车结束列表」会被下一次回车又续上，永远退不出去。
- **`apply` 现在会还原选区**：整段重写文本会让 UIKit 把选区塌到末尾，之前用户选中的文字点一下加粗就没了选区。

---

## 七、验证结果（2026-09-26）

| 套件 | 结果 |
|---|---|
| `JustDiaryTests/EditorFormatBehaviorTests`（作用域，23 例） | 全部通过 |
| `JustDiaryTests/EditorSpacingTests`（行距 / 段距 / 图片，15 例） | 全部通过 |
| `JustDiaryTests` 合计（另含 `ContentFormatTests` 存储格式与往返、`ShareRendererTests`、`AdaptiveLayoutTests`、`SplitLayoutTests`） | 63 例全部通过 |
| `JustDiaryUITests` 合计（`EditorTypeSizeUITests` 往返保存 / 放弃修改 / 输入区高度、`LandscapeLayoutUITests` 含横屏格式栏、`EditorFlowUITests` 含返回阅读页与格式栏放得下） | 21 例全部通过 |

复现命令（宏插件需要完整沙箱，故在 workspace 沙箱外运行）：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project JustDiary.xcodeproj -scheme JustDiary \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath .build/DerivedData \
  -only-testing:JustDiaryTests -only-testing:JustDiaryUITests
```

---

## 八、编辑模式其它按钮（非格式栏）

| 按钮 | 位置 | 点击效果 | 备注 |
|---|---|---|---|
| 图片 `photo` | 编辑态顶栏 | 拉起 `PhotoPicker`，选图后 `controller.insertImage`：在光标处插入图片附件 + 一个换行，光标移到图片之后 | 图片是独立的 `ContentPart.style == "image"` |
| 放弃修改 `arrow.counterclockwise` | 编辑态顶栏 | `confirmDiscardEditing()` → 二次确认 → `loadParts = editingOriginalParts`（回到**进入编辑时**的内容） | 新日记的 `editingOriginalParts` 进入时已清空 |
| 保存 `checkmark` | 编辑态顶栏 | `saveEditor()`：落库 `controller.currentParts()`；缺地点/跨天会有额外确认弹窗 | 空编辑器直接保存会被忽略 |
| 返回 `chevron.left` | 顶栏 | `handleBack()`：**编辑态**只退出编辑、回到这一天的阅读页（有未保存内容先弹「放弃」确认）；**阅读态**才关掉日记页回首页 | B12 |
| 地点胶囊 | 编辑卡片内 | 打开精度菜单（省 / 市 / 区 / 详细），可「重新定位」（仅新块） | 与样式无关，见 `docs/location-recording.md` |
| 待办勾选 | **阅读态**卡片内 | 直接切换该待办的 `done`（划线 + 降透明度） | 编辑态没有勾选交互，只有格式栏的「待办」按钮 |

---

## 九、边界与不变量

1. **空行不入库**：`PartsCodec.parts(from:)` 跳过纯空白行，所以编辑时的空行保存后不再存在；
   B9 修完后，「只有标记的行」同样不入库。
2. **整行样式互斥**：列表/待办 ↔ 大标题/小标题/正文/引用 互斥；居中 ↔ 列表/引用/待办 互斥。
   切换时由 `restyle` 负责「移除旧形态」（标记、底色、对齐）。
3. **行内样式（加粗等）在换行样式的重设中保留**：`restyle` 会读出原字体的 symbolic traits
   （bold / italic）再写回，所以「把一行改成大标题」不会丢加粗。
4. **删除线 / 下划线跟随文本 run**，不跟随行样式，行样式重设时不动它们。
5. **`typingAttributes` 是「之后输入」的唯一权威**，但它会被 UIKit 在光标移动时按光标处文字刷新；
   自定义键（`.diaryDesignSize` / `.diaryBlockStyle`）丢失后靠字号反推（见 `editor-typography.md`）。
6. **居中空行上回车被忽略**（`shouldBlockNewline(at:)`）：这是既有设计，避免连出一串空居中行；
   与 B6 新增的「空列表项回车结束列表」是两套独立规则（前者吞掉回车，后者消费回车并去掉标记）。
7. **换行延续的落库形态**：引用延续靠新行的换行字符继承引用属性；
   列表/待办延续靠 `handleReturn` 在光标处插入「换行 + 标记」，两条路径最终都表现为
   `ContentPart.style` 的延续（连续的列表行会被合并成一个 `list` part）。
8. **键盘的收起路径**（B17）：点内容空白、点顶栏空白、下拉内容；格式栏按钮是有意
   例外 —— 点它会 `becomeFirstResponder`，把焦点还给编辑器（连续排版不该被收键盘打断）。
9. **阅读态与编辑态的正文列同宽**（都是 660 上限，B18）：进出编辑时卡片不会跳。输入区
   宽度仍差 4pt（卡片内边距 12 vs 10），编辑区文字还另有 12pt 的输入内缩。
10. **光标停在「列表项下一行的空行」上时回车不续列表**：那一行自己没有标记，而 R3 只在
   「当前行有标记且标记后还有文字」时另起一项。这是有意的 —— 否则空项回车刚结束列表，
   下一次回车又被上一行的标记续上，用户永远退不出列表。要续列表，把光标放回带标记的
   那一行（在那行末尾按回车）。

---

## 十、代码索引

| 行为 | 文件:行 |
|---|---|
| 字体栏的组装与 active 态（含 `editor.formatBar` 标识） | `JustDiary/Views/Diary/RichTextView.swift:203-350` |
| 键盘事件入口（回车拦截、B6） | `JustDiary/Views/Diary/RichTextView.swift:160-180` |
| 编辑器宽度变化（B10 所在） | `JustDiary/Views/Diary/RichTextView.swift:114-140` |
| 字符样式：加粗 / 斜体 / 删除线 / 下划线（B5） | `RichTextEngine.swift:257-378` |
| 段落样式：样式菜单（B1/B2） | `RichTextEngine.swift:380-395` |
| `restyle`（单行改写，跳过图片行） | `RichTextEngine.swift:420-458` |
| `paragraphRanges`（B1 所在） | `RichTextEngine.swift:480-503` |
| 居中（B3） | `RichTextEngine.swift:504-540` |
| 列表 / 待办标记（B4） | `RichTextEngine.swift:581-640` |
| `handleReturn`（B6：换行续行、空项结束） | `RichTextEngine.swift:642-712` |
| 引用（B1/B2） | `RichTextEngine.swift:714-744` |
| 空行 / 段落范围判定 | `RichTextEngine.swift:746-797` |
| `activeStyles`（B8） | `RichTextEngine.swift:798-815` |
| `refitImages`（B10） | `RichTextEngine.swift:888-917` |
| `apply`（含选区还原） | `RichTextEngine.swift:924-944` |
| `imageParagraphStyle` / `readerChunk`（行距与图片留白） | `RichTextEngine.swift:1048-1090` |
| 落库解析（B9 所在） | `RichTextEngine.swift:1153-1245` |
| 阅读区块渲染（图片 padding、块间距 0） | `JustDiary/Views/Diary/MediaViews.swift:61-92` |
| 阅读块规范化（去结尾空行 / 去图片段距） | `JustDiary/Views/Diary/ReadTextView.swift:91-95` |
| 格式栏位置（键盘上方、横竖屏一致，B11） | `JustDiary/Views/Diary/DiaryPageView.swift:16-28` |
