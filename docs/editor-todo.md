# 编辑页待办（已核实，尚未处理）

日期：2026-09-15 · 环境：Xcode 27 / iOS 27 SDK

界面规范化改造（`ae23268`）期间发现、但**本次刻意未动**的编辑器问题。
每一条都已在当前代码里核实过，不是猜测；处理时请连同对应用例一起补。

---

## E1. 正文默认字号偏小，且提升它需要数据迁移 ⭐️ 最需要决策

**现状**：`EditorDesignSize.body = 15`、`quote = 13`（见 `Views/Diary/RichTextEngine.swift`）。
Apple 的 body 是 17pt，15pt 相当于 subheadline。

**为什么不能直接改**：每个 run 的字号**会落库**（`TextRun.size` → `content_json`）。
`PartsCodec.attributedString(from:)` 在 `run.size` 存在且与块默认值不同时优先用它，
所以把 body 从 15 改成 17 **只影响新写的段落**，已有日记仍按 15 渲染。要真正生效必须做
一次性迁移。

**迁移的难点**：字号同时承担「块类型」的判别（见 `docs/design-system.md` 第三节），
而且无法区分「应用自己写的 15」和「导入文档里用户自定义的 15」。旧梯级
{13, 15, 18, 22} 与新梯级 {15, 17, 18, 22} 在 15 处重叠（旧 body vs 新 quote）。

**建议方案**（择一，需先决策再动手）：
- (a) 不动字号，接受 15pt 作为本项目的正文基准。放大字号时它会长到 24pt，
  可读性已有改善——这是本次改造后的现状。
- (b) 一次性迁移：在 `parts(from:)` 里把落在旧梯级上的字号按
  `{13→13, 15→17, 18→18, 22→22}` 归一，并给 `AppSettings` 加一个
  `editor_size_ladder_version` 标记，避免重复迁移。风险：会覆盖导入文档中恰好等于
  15 的自定义字号。
- (c) 把「块类型」从字号里彻底解耦（例如给段落存显式类型），再自由调整字号。
  最干净但改动最大。

---

## E2. 无法在应用内创建 H2 标题

**现状**：`FontToolbar` 的标题按钮只做开关：

```swift
// Views/Diary/RichTextView.swift:214
controller.applyHeading(controller.currentHeadingLevel() == 1 ? 0 : 1)
```

`applyHeading` 支持 level 0/1/2，但 UI 只会传 0 或 1。因此
**`ContentPartType.h2` 只能来自导入的文档**（由 `parts(from:)` 的 `>= 18` 判别产生）。
`editor_tool_heading` 的文案也只是「标题 / Heading」，没有层级概念。

**建议**：标题按钮改为菜单（正文 / 标题 1 / 标题 2），或长按切换层级。
`applyHeading` 与 `currentHeadingLevel()` 已经支持，主要是 UI 层改动。

**旁证**：String Catalog 里原本有 `editor_font_body`（正文）、`editor_font_heading`（大标题）、
`editor_font_sub`（小标题）三条文案，但**没有任何代码引用**——说明层级选择器当初设计过、
后来没实现。这三条已在 2026-09-15 的清理中作为无用键删除；做这一项时按上面的语义
重新添加即可（`git show bee42a5:JustDiary/Resources/Localizable.xcstrings` 可取回原文案）。

---

## E3. 「重做」按钮的图标、文案、行为三者不一致

**现状**（`Views/Diary/DiaryPageView.swift:182`）：

- 图标：`arrow.uturn.backward`（**撤销**语义）
- 无障碍文案：`editor_redo` = 「重做 / Redo」
- 实际行为：`vm.loadParts = vm.editingOriginalParts` —— 丢弃本次编辑的**全部**改动，
  回到进入编辑时的状态

`Localizable.xcstrings` 里**没有 `editor_undo`**，也没有撤销/重做的栈。

**建议**：先决定要哪种语义。若只是「放弃本次编辑」，应改用
`arrow.counterclockwise` + 新文案（如「放弃修改 / Discard changes」），并加二次确认——
当前点一下就会静默丢掉整段编辑内容，且没有撤销可用。

---

## E4. 编辑区最小高度写死

**现状**：
- `Views/Diary/DiaryPageView.swift:385` — `.frame(minHeight: 160)`
- `Views/Diary/RichTextView.swift:35` — `max(160, size.height)`

两处 160pt 都不随字号变化。最大辅助功能字号下，占位文字「开始记录这一刻的想法…」
会占掉大半高度，输入区显得局促。

**建议**：改成随 `DynamicTypeSize` 缩放（参考 `DesignSystem.swift` 的
`DynamicTypeMetrics.multiplier`），或按行数下限（如 4 行正文）计算。

---

## E5. 段落行距与字号判断耦合

**现状**（`Views/Diary/RichTextEngine.swift`，`appendLine`）：

```swift
style.lineSpacing = size == EditorDesignSize.quote ? 7 : 2
```

用「字号恰好等于 quote」来判断引用块。这在设计字号不变的今天是对的，但：
- 它与 E1 的方案 (b)/(c) 直接冲突（一旦迁移字号，这个判断会失效）；
- 2pt / 7pt 是固定值，不随字号缩放，大字号下行距显得偏紧。

**建议**：引用块的判别改用已有信号（`.backgroundColor` 已经是引用的标记，
`isQuote` 在 `parts(from:)` 里就是这么判的），行距改为按字号比例。

---

## E6. 待补的测试

- E2 修好后：补「创建 H2 → 保存 → 重开仍是 H2」的用例。
- E3 修好后：补「放弃修改后内容回到编辑前」的用例。
- 现有 `EditorTypeSizeUITests` 只覆盖段落；加入标题后应扩展为「H1/H2/引用
  在最大字号下三轮保存均不改变类型」。

---

## 参考

- 设计令牌、动态字体与上限、**编辑器往返不变量**：`docs/design-system.md`
- 往返不变量对应的回归测试：`JustDiaryUITests/EditorTypeSizeUITests.swift`
