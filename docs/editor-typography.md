# 编辑页字体与段落样式

日期：2026-09-16 · 环境：Xcode 27 / iOS 27 SDK · 设备：iPhone 18 Pro 模拟器（iOS 27.0）

本文是 2026-09-15 记录的编辑页待办（原 `docs/editor-todo.md`，E1–E6）的**处理结果**，
同时说明编辑页的字体模型。通用规则（设计令牌、动态字体上限、玻璃边界）见
`docs/design-system.md`；编辑器往返不变量见该文第三节。

---

## 一、模型：照 Apple 备忘录做「语义样式 + 跟随系统字号」

Apple 备忘录不让用户挑任意磅值，而是给段落一个**语义样式**（Title / Heading /
Subheading / Body），字号由系统「文字大小」经 `UIFontMetrics` 解析。编辑页现在照此
实现，字号直接取 HIG › Typography 的 iOS 默认梯级：

| 样式 | 编辑页名称 | `ContentPart.type` | 设计字号 | Apple 文本样式 |
|---|---|---|---|---|
| Title | 大标题 | `h1` | 28 | Title 1 |
| Heading | 小标题 | `h2` | 22 | Title 2 |
| Body | 正文 | `p` | 17 | Body |
| Quote | 引用 | `quote` | 15 | Subheadline |

- 格式栏左侧的「样式」菜单（SF Symbol `textformat.size`，中文环境渲染为「大小」）
  负责选择大标题 / 小标题 / 正文；引用另有 `text.quote` 按钮（它同时是引用的底色标记）。
- 行距、段后距都按字号比例计算（引用 0.5×，其余 0.13×；标题/引用有段后距），
  不再写死 2pt / 7pt。
- 正文 15 → 17 是 HIG 对 iOS 正文的默认值；放大字号时正文约 25.5pt（AX5）。

## 二、E1–E6 处理结果

| 编号 | 原问题 | 处理 |
|---|---|---|
| E1 | 正文 15pt 偏小，改字号需要数据迁移 | 改为 Apple 梯级 **28 / 22 / 17 / 15**；块类型与字号解耦后**不需要迁移**（见下） |
| E2 | 应用内无法创建 H2 | 标题按钮改为**样式菜单**（大标题 / 小标题 / 正文），`editor_font_heading` / `editor_font_sub` / `editor_font_body` 三条文案按原语义重新加回 |
| E3 | 「重做」按钮图标、文案、行为不一致，且静默丢弃编辑 | 改为 `arrow.counterclockwise` +「放弃修改 / Discard Changes」+ 二次确认；`editor_redo` 删除 |
| E4 | 编辑区最小高度写死 160pt | 改为按正文样式的动态字体系数缩放（默认仍 160pt，AX5 约 240pt），`PlaceholderTextView.minimumHeight` |
| E5 | 行距用「字号 == quote」判断引用块 | 引用改由块类型 / 底色判定，行距改为字号比例 |
| E6 | 缺 H1/H2/引用与放弃修改的用例 | `JustDiaryUITests/EditorTypeSizeUITests` 重写，见第三节 |

### E1 的关键：块类型不再从字号反推

改造前 `parts(from:)` 用字号反推块类型（`>= 22` → h1、`>= 18` → h2），字号同时承担
「字号」和「块类型」两个职责。于是：

- 改字号梯级会改写已有日记，必须先做一次性迁移；
- 旧梯级 {13, 15, 18, 22} 与新梯级在 15 处重叠，无法区分「应用自己写的 15」和
  「导入文档里用户自定义的 15」。

现在文本存储里每个 run 同时带 `.diaryBlockStyle`（块类型）与 `.diaryDesignSize`
（未缩放的设计字号），落库时块类型写入 `ContentPart.type`，`parts(from:)`
**优先读块类型**，字号推断只作为兜底（导入文档，或 UIKit 重新同步 typingAttributes
时丢掉自定义键的字符）。因此：

- 调整梯级不会再改写已有日记；
- `TextRun.size` 只在 run 的字号**确实不等于**所在块的默认字号时才写入，
  它的含义因此是唯一的：**自定义字号**（导入材料）；
- 存量测试数据按新结构重新生成：`python3 tools/seed_sample_diary.py "iPhone 18 Pro"`
  （示例里含标题 / 小标题 / 正文 / 引用 / 列表 / 待办，以及粗体、斜体、下划线、
  删除线和居中段落）。

### E3 的语义选择

「放弃修改」保留「回到进入编辑时的内容」这一行为（不做撤销栈），但补上二次确认；
另外修掉一个连带 bug：新日记的 `editingOriginalParts` 会沿用上一次编辑过的块，
现在 `enterWrite()` 会把它清空——否则在新日记里点「放弃修改」会恢复出上一个块的内容。

### 没有采用的方案

E2 备选的「长按切换层级」没有采用：样式菜单与备忘录的「Aa → 样式」一致，可发现性更好，
长按对 VoiceOver 用户也不友好。

## 三、测试

`JustDiaryUITests/EditorTypeSizeUITests`（模拟器需为中文）：

1. `testBlockStylesSurviveReSaveAtLargestTextSize`
   最大辅助功能字号下建立 `p / h1 / h2 / quote` 四段 → 保存 →
   **重新打开已保存的块**（不是新建）→ 再次保存，共三轮，断言块类型与文本不变。
   原来的用例点的是「写日记」（新建），并没有重新解析应用自己渲染过的文本。
2. `testDiscardChangesRestoresSavedContent`
   重新打开块 → 追加文字 → 「放弃修改」→ 确认 → 断言回到保存前的内容。
3. `testInputAreaGrowsWithTextSize`
   空编辑区在默认字号下高 160pt，在最大辅助功能字号下约 240pt（E4）。

两个用例都通过 `-ui-test-editor-state` 探针读取「编辑器将要落库的块类型与文本」，
不需要从模拟器容器里读数据库；第一次启动额外带 `-ui-test-reset-data`，只清空
「今天」这一天，避免多次运行互相干扰，同时不影响首页 / 足迹 / 搜索页测试依赖的示例数据。

## 四、没有做的事

- **不做字号迁移。** 存量条目里 `run.size` 有值就按它渲染（导入材料可能是任意字号），
  这是有意保留的：迁移无法区分应用自己写的 15 与导入的自定义 15。仓库里的数据是测试
  数据，已按新结构重新生成。
- **不做任意磅值 / 应用内字号档位。** 字号只跟随系统「文字大小」，与备忘录一致；
  应用内再给一档字号会和系统设置打架。
- **等宽（Monospaced）样式**：编辑器仍未提供。它需要新的 `ContentPart.type`
  以及阅读、分享长图两条渲染链路的支持，超出本次范围。
