# 编辑页字体与段落样式

日期：2026-09-16 · 环境：Xcode 27 / iOS 27 SDK · 设备：iPhone 18 Pro 模拟器（iOS 27.0）

本文是 2026-09-15 记录的编辑页待办（原 `docs/editor-todo.md`，E1–E6）的**处理结果**，
同时说明编辑页的字体模型与 `content_json` 的存储格式。通用规则（设计令牌、动态字体
上限、玻璃边界）见 `docs/design-system.md`；编辑器往返不变量见该文第三节。
格式按钮**作用域**（每个按钮点一下 / 取消各影响哪一段、行样式换行怎么延续）见
`docs/editor-format-behaviors.md`。

---

## 一、模型：照 Apple 备忘录做「语义样式 + 跟随系统字号」

Apple 备忘录不让用户挑任意磅值，而是给段落一个**语义样式**（Title / Heading /
Subheading / Body），字号由系统「文字大小」经 `UIFontMetrics` 解析。编辑页现在照此
实现，字号直接取 HIG › Typography 的 iOS 默认梯级：

| 样式 | 编辑页名称 | `ContentPart.style` | 设计字号 | Apple 文本样式 |
|---|---|---|---|---|
| Title | 大标题 | `title` | 28 | Title 1 |
| Heading | 小标题 | `heading` | 22 | Title 2 |
| Body | 正文 | `body` | 17 | Body |
| Quote | 引用 | `quote` | 15 | Subheadline |

- 格式栏左侧的「样式」菜单（SF Symbol `textformat.size`，中文环境渲染为「大小」）
  负责选择大标题 / 小标题 / 正文；引用另有 `text.quote` 按钮（它同时是引用的底色标记）。
- 行距、段后距都按字号比例计算（引用 0.5×，其余 0.13×；标题/引用有段后距），
  不再写死 2pt / 7pt。
- 正文 15 → 17 是 HIG 对 iOS 正文的默认值；放大字号时正文约 25.5pt（AX5）。

## 二、E1–E6 处理结果

| 编号 | 原问题 | 处理 |
|---|---|---|
| E1 | 正文 15pt 偏小，改字号需要数据迁移 | 改为 Apple 梯级 **28 / 22 / 17 / 15**；存储里不再有磅值（第三节），因此**不需要按梯级做迁移** |
| E2 | 应用内无法创建 H2 | 标题按钮改为**样式菜单**（大标题 / 小标题 / 正文），`editor_font_heading` / `editor_font_sub` / `editor_font_body` 三条文案按原语义重新加回 |
| E3 | 「重做」按钮图标、文案、行为不一致，且静默丢弃编辑 | 改为 `arrow.counterclockwise` +「放弃修改 / Discard Changes」+ 二次确认；`editor_redo` 删除 |
| E4 | 编辑区最小高度写死 160pt | 改为按正文样式的动态字体系数缩放（默认仍 160pt，AX5 约 240pt），`PlaceholderTextView.minimumHeight` |
| E5 | 行距用「字号 == quote」判断引用块 | 引用改由块类型 / 底色判定，行距改为字号比例 |
| E6 | 缺 H1/H2/引用与放弃修改的用例 | `JustDiaryTests/ContentFormatTests` + `JustDiaryUITests/EditorTypeSizeUITests` 重写，见第四节 |

### E1 的关键：块类型不再从字号反推

改造前 `parts(from:)` 用字号反推块类型（`>= 22` → h1、`>= 18` → h2），字号同时承担
「字号」和「块类型」两个职责。于是改字号梯级会改写已有日记，必须先做一次性迁移；
而且旧梯级 {13, 15, 18, 22} 与新梯级在 15 处重叠，无法区分「应用自己写的 15」和
「导入文档里用户自定义的 15」。

现在编辑器文本存储里每个 run 带 `.diaryBlockStyle`（块类型）与 `.diaryDesignSize`
（未缩放的设计字号），落库时块类型写入 `ContentPart.style`，`parts(from:)`
**优先读块类型**，字号推断只作为兜底（UIKit 重新同步 typingAttributes 时丢掉自定义键
的字符）。因此调整梯级不会再改写已有日记。存储格式见下一节。

### E3 的语义选择

「放弃修改」保留「回到进入编辑时的内容」这一行为（不做撤销栈），但补上二次确认；
另外修掉一个连带 bug：新日记的 `editingOriginalParts` 会沿用上一次编辑过的块，
现在 `enterWrite()` 会把它清空——否则在新日记里点「放弃修改」会恢复出上一个块的内容。

### 没有采用的方案

E2 备选的「长按切换层级」没有采用：样式菜单与备忘录的「Aa → 样式」一致，可发现性更好，
长按对 VoiceOver 用户也不友好。

## 三、存储格式 v2

`edit_block.content_json` 也随字体模型一起改了，因为 v1 的格式里「字号」仍是权威：

**v1**（裸数组，块类型用 HTML 名，每个 run 都带磅值）：

```json
[{"type":"h1","runs":[{"text":"标题","size":22}]},
 {"type":"p","runs":[{"text":"正文","size":15,"bold":false}]}]
```

**v2**（带版本的信封，语义样式名，run 只有行内样式）：

```json
{"v":2,"parts":[{"style":"title","runs":[{"text":"标题"}]},
                {"style":"body","runs":[{"text":"正文"},{"text":"粗","bold":true}]}]}
```

| 项目 | v1 | v2 |
|---|---|---|
| 顶层 | 裸 `[ContentPart]` | `{"v":2,"parts":[…]}` |
| 块样式 | `type`，值 `h1`/`h2`/`p`/`ul`/`img` | `style`，值 `title`/`heading`/`body`/`list`/`todo`/`quote`/`image` |
| run | `text` + 行内样式 + **`size`（磅值）** | `text` + 行内样式，**没有 `size`** |
| 未开启的行内样式 | 写成 `false` | 省略（`nil`） |
| 键顺序 / 转义 | — | `sortedKeys` + `withoutEscapingSlashes`，输出稳定 |

理由：

- **`size` 必须去掉。** 字号现在由样式决定、跟随系统「文字大小」，落库的磅值只能描述
  「编辑器既写不出也改不了」的字号；它能做的只有让阅读端显示一个在编辑器里一改样式
  就被抹掉的值。（顺带：这也就是 E1 的迁移——旧数据里的 15 / 18 / 22 全部归到语义样式，
  不再需要按梯级映射。）
- **样式名要语义化。** 存储里的 `h1`/`h2` 是从 HTML 借来的名字，与模型里的
  Title/Heading/Body 对不上；`ul`/`img` 同理。
- **要能演进。** 这个格式刚刚静默改过一次语义（字号从权威变成装饰），没有版本号就
  无法判断一段 JSON 该按哪套规则理解。`v` 让下一次改动可以确定地迁移。

兼容与迁移：

- `ContentFlatten.parseContent` 同时接受 v1 与 v2：v1 的 `type` 键、HTML 名与 `size`
  在解码时映射 / 丢弃，**旧备份可以直接导入**。
- `serializeContent` 只写 v2。保存、导入、搜索索引重建都经过
  `ImagePathUtil.normalizeContent`（parse + serialize），这些路径都会顺手升级。
- 启动时 `DiaryRepository.migrateContentFormat()` 把库里剩下的 v1 行原地改写一次，
  由 `SettingsStore.contentFormatVersion` 保证只跑一次。它只改 `content_json`，
  文本没变，因此 `search_text` 与 FTS 索引不受影响。
- 示例数据同步改成 v2：`python3 tools/seed_sample_diary.py "iPhone 18 Pro"`。

## 四、测试

**单元测试** `JustDiaryTests/ContentFormatTests`（毫秒级，覆盖 UI 测试采样不到的部分）：

| 用例 | 断言 |
|---|---|
| `testSerializedContentIsVersionedAndCarriesNoFontSize` | 落库是 `{"v":2,…}`，没有 `size` / `type` 键，能够原样解回 |
| `testLegacyV1ContentIsUpgradedOnRead` | v1 数组的 `type` / HTML 名 / `size` 被正确映射与丢弃，`normalizeContent` 后是 v2 |
| `testOnlySetInlineStylesAreWritten` | 未开启的行内样式不写成 `false` |
| `testEditorRoundTripPreservesStylesAtEveryTextSize` | **全部 12 档字号**下 加载 → 解析 都保持块样式、对齐、文本与行内样式 |
| `testEditorRoundTripKeepsTodoStateAndItemGrouping` | 连续列表 / 待办项合并成一条，`done` 状态不丢 |
| `testEveryEditorStyleMapsToItsPersistedNameAndBack` | 编辑样式 ↔ 存储样式一一对应；未知样式按正文处理 |

**UI 测试** `JustDiaryUITests/EditorTypeSizeUITests`（模拟器需为中文）：

1. `testBlockStylesSurviveReSaveAtLargestTextSize`
   最大辅助功能字号下建立 `body / title / heading / quote` 四段 → 保存 →
   **重新打开已保存的块**（不是新建）→ 再次保存，共三轮，断言块样式与文本不变。
   原来的用例点的是「写日记」（新建），并没有重新解析应用自己渲染过的文本。
2. `testDiscardChangesRestoresSavedContent`
   重新打开块 → 追加文字 → 「放弃修改」→ 确认 → 断言回到保存前的内容。
3. `testInputAreaGrowsWithTextSize`
   空编辑区在默认字号下高 160pt，在最大辅助功能字号下约 240pt（E4）。

UI 用例通过 `-ui-test-editor-state` 探针读取「编辑器将要落库的块样式与文本」，不需要
从模拟器容器里读数据库；第一次启动额外带 `-ui-test-reset-data`，只清空「今天」这一天，
避免多次运行互相干扰，同时不影响首页 / 足迹 / 搜索页测试依赖的示例数据。

## 五、没有做的事

- **不保留任意磅值。** v2 里已没有 `size`，导入材料中与语义样式不符的字号按块样式
  归一（无法从 v1 的 `size` 判断那是应用写的梯级值还是导入的自定义值，这也是 v1 的
  老问题）。仓库里的数据是测试数据，已按 v2 重新生成。
- **不做应用内字号档位。** 字号只跟随系统「文字大小」，与备忘录一致；应用内再给一档
  字号会和系统设置打架。
- **等宽（Monospaced）样式**：编辑器仍未提供。它需要新的 `ContentPart.style` 取值
  以及阅读、分享长图两条渲染链路的支持，超出本次范围。
