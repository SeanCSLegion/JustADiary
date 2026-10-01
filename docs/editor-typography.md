# 编辑页字体与段落样式

日期：2026-09-16（2026-09-26 补第五节：行距 / 段距 / 图片留白）· 环境：Xcode 27 / iOS 27 SDK · 设备：iPhone 18 Pro 模拟器（iOS 27.0）

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

（2026-10-01 核实：`ContentPartStyle` 共 7 个取值 —— `title` / `heading` / `body` / `quote` /
`list` / `todo` / `image`；上表只列编辑器能选的 4 个语义样式，`list` / `todo` / `image`
落库用同名取值、绘制时按正文属性（`EditorBlockStyle.init(partStyle:)`）。）

- 格式栏左侧的「样式」菜单（SF Symbol `textformat.size`，中文环境渲染为「大小」）
  负责选择大标题 / 小标题 / 正文；引用另有 `text.quote` 按钮（块类型本身就是引用的标记，底色与竖条由 `DiaryTextView` 的装饰层画，见第七节）。
- 行距、段后距都按字号比例计算（引用 0.5×，其余 0.13×；标题/引用有段后距），
  不再写死 2pt / 7pt。
  **现状（2026-10-01 核实）**：这一句已被第八节取代 —— 行距改由 `lineHeightRatio`
  （1.25 / 1.32 / 1.50 / 1.60）决定，段距**全部由段前距承担**、段后距一律 0。
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

（2026-10-01 核实：该类共 8 例，上表 6 个用例名全部存在；另有
`testEmptyAndBrokenContentDecodesToNothing`、`testEditorRoundTripPersistsNoFontSize` 两例。）

**UI 测试** `JustDiaryUITests/EditorTypeSizeUITests`（模拟器需为中文）：

1. `testBlockStylesSurviveReSaveAtLargestTextSize`
   最大辅助功能字号下建立 `body / title / heading / quote` 四段 → 保存 →
   **重新打开已保存的块**（不是新建）→ 再次保存，共三轮，断言块样式与文本不变。
   原来的用例点的是「写日记」（新建），并没有重新解析应用自己渲染过的文本。
2. `testDiscardChangesRestoresSavedContent`
   重新打开块 → 追加文字 → 「放弃修改」→ 确认 → 断言回到保存前的内容。
3. `testInputAreaGrowsWithTextSize`
   空编辑区在默认字号下高 160pt，在最大辅助功能字号下约 240pt（E4）。

（2026-10-01 核实：该文件共 4 例，上面 3 个用例名全部存在；另有
`testEntrySavedWithoutLocationCannotGainOne`（无位置的日记重开后不能补位置），与字号 /
放弃修改无关。）

UI 用例通过 `-ui-test-editor-state` 探针读取「编辑器将要落库的块样式与文本」，不需要
从模拟器容器里读数据库；第一次启动额外带 `-ui-test-reset-data`，只清空「今天」这一天，
避免多次运行互相干扰，同时不影响首页 / 足迹 / 搜索页测试依赖的示例数据。

## 五、行距、段距与图片留白（2026-09-26）

### 5.1 模型

行内换行用 `lineSpacing`，段与段之间用「前段 `paragraphSpacing` + 后段
`paragraphSpacingBefore`」——**TextKit 会把两者相加**，所以每个样式要同时给这两个值，
只给其中一个就会出现「贴上文还是贴下文」的方向问题。全部按设计字号的比例算，跟随
设置 › 文字大小：

> **2026-09-30 起这张表已按 Apple 的规范重定**（行距取 HIG 的行高与 CJK 字体行高中的
> 更宽者，段距改由**段前距**承担），最新数值与依据见第八节；下表保留改造前的模型说明，
> 便于对照「为什么当时是那样」。（2026-10-01 核实：本节 5.1–5.3 里出现的 **10.2pt** /
> **0.6×** 也都是改造前的数值 —— `imageSpacing` 现为 `正文 × 0.8` = 13.6pt，见第八节。）

| 样式 | 设计字号 | lineSpacing（段内换行） | paragraphSpacingBefore（段前） | paragraphSpacing（段后） |
|---|---|---|---|---|
| 大标题 `title` | 28 | 0.13 × 28 = 3.6 | 0.35 × 28 = **9.8** | 0.15 × 28 = 4.2 |
| 小标题 `heading` | 22 | 0.13 × 22 = 2.9 | 0.35 × 22 = **7.7** | 0.15 × 22 = 3.3 |
| 正文 `body` | 17 | 0.13 × 17 = 2.2 | 0 | 0 |
| 引用 `quote` | 15 | 0.5 × 15 = 7.5 | 0.4 × 15 = 6 | 0.4 × 15 = 6 |
| 列表 / 待办 | 17（正文属性） | 2.2 | 0 | 0 |
| 图片 | — | — | **10.2** | **10.2** |

（缩进是另一回事：引用另有 `firstLineHeadIndent = headIndent = 16`，列表 / 待办另有
`headIndent = 18 / 26`、`firstLineHeadIndent = 0` —— 悬挂缩进，见第七节。）

> 行首标记（列表 / 待办）是这一行的**第一个字符**，而段落样式取自段落第一个字符 ——
> 所以标记自己也带着这条段落样式（`MarkerAttachment.attributed`）。不带的话整条列表项会
> 退回默认段落属性，把正文的 2.2pt 行距白丢掉（实测折行推进 20.29pt vs 正文 22.5pt，B25）。

图片的留白常量是 `EditorDesignSize.imageSpacing = 正文 × 0.8`（默认 13.6pt；2026-10-01
核实：原文写 0.6 × / 10.2pt），由 `PartsCodec.imageParagraphStyle()` 挂成图片段落的
段前 / 段后 —— 各扣掉一段看不见的空白（`imageTopSlack` / `imageBottomSlack`）之后
是 11.0 / 1.1，见第八节。

**图片的尺寸**：图片按**列宽**排版（编辑区 = 输入区宽度 − 它自己的左右内缩，
2026-10-01 核实：`BlockMetrics.textContainerInset` 左右现为 0，原文的「− 24」是编辑区
还有 12pt 内缩时的旧算法；阅读区 = 卡片正文宽度），
只按存储的 `w:h` 等比缩放并**居中**。所以存储的 `w` / `h` 从今往后只是「比例」和
「取图分辨率上限」的提示，不再是排版尺寸 —— `PartsCodec.parts(from:)` 落库时照抄
payload 里的原值，列宽变化不会改写它。横屏列变宽时图片跟着放大；段落对齐用
`.center`（`imageParagraphStyle()`），编辑区里小图也居中。**横竖屏切换时同样**：
`RichEditorController.refitImages(maxWidth:)` 按同一条规则重排已有附件（旋转、分屏都会
触发），只重排图片与附件 bounds，文本与光标不动。

### 5.2 两条链路怎么用同一个模型

- **编辑区**：整篇是一个 `UITextView`，段距全部交给 TextKit（段落样式）。
  图片段落的样式挂在**附件字符**上、结尾换行保持「正文 typingAttributes」——
  实测段落样式取段落第一个字符，所以图片行拿到图片段落自己的段前 / 段后（2026-10-01
  核实：现为 11.0 / 1.1，不再是 10.2/10.2，见第八节），而它后面新输入的那一段
  不会继承图片的段距。
- **空行**：空段落没有字形，但**有行盒**，TextKit 按「段落第一个字符」取段落样式 ——
  空段落的第一个字符就是它自己的换行符，所以编辑区里切换居中 / 引用 / 标题时，除了
  `typingAttributes`，还要把该样式写进那个换行符，这一行的行盒与光标才会立刻跟上
  （见 `docs/editor-format-behaviors.md` 的 B22）。文本**末尾**那条空行没有自己的字符，
  由 `typingAttributes` 直接排版。
- **阅读区**：`DiaryPartsView` 把内容切成「文本块 / 图片块」两种 chunk，每块一个
  `UITextView`。这里必须做两件“减法”，否则同一篇日记在编辑区和阅读区差出几十点：
  1. **去掉块尾的换行**。`sizeThatFits` 会为结尾空段落留整整一行（约 20pt）——
     以前每个文本块末尾都白多这么一行，读起来就是「图片前面莫名一大段空白」。
  2. **去掉图片块的段落样式**。图片自己就是一块，上下留白由 `DiaryPartsView` 的
     `.padding(.vertical, EditorDesignSize.readerImagePadding)` 给，段落样式会重复计一次。
  见 `PartsCodec.readerChunk(from:imageMaxWidth:typeSize:traits:)`
  （2026-10-01 核实：原文写作 `.padding(.vertical, EditorDesignSize.imageSpacing)` 与
  `readerChunk(from:typeSize:traits:)`，签名与 padding 常量都已不是代码里的样子）。
  3. **上下内缩与编辑区一致**：阅读块的 `textContainerInset` 与编辑区共用
     `BlockMetrics.textContainerInset`（6pt），两个模式的正文字形落在同一个位置。
- **分享长图**：`ImageShareService` 有自己的一套（`gapBefore` 20 / 标题 26，按 720pt
  宽绘制，约等于手机上的 10 / 13pt），方向与这里一致：标题离上文远、离下文近。
  它是独立版面，不共用这些常量。

### 5.3 上一版的问题（都已修）

| 问题 | 现象 | 处理 |
|---|---|---|
| 各样式只有段**后**距 | 小标题贴在上文下面、离自己的正文反而更远，读起来像上一段的一部分（与分享长图里的规则正好相反） | 标题 / 小标题改为「段前 0.35×、段后 0.15×」，引用对称 |
| 图片在编辑区上下 **0pt** | 图片紧贴上一行与下一行文字 | 图片段落给 10.2/10.2 |
| 图片在阅读区上下 **约 40pt** | 同一个块里的正文 → 图片之间出现一大段空白 | 去掉块尾空行 + 图片块 padding 10.2（上图：编辑与阅读一致） |
| 刚插入的图片与重开后不同 | 插入时套的是正文段落属性（行距 2.2、段距 0），重开走另一条路径 | 两条路径都走 `imageParagraphStyle()` |
| 图片文件读不出来时整行消失 | 缺图会让整篇内容重排，图片位置直接没了 | 占位附件与高度照留，只是画不出图 |
| 图片不随列宽变化 | 横屏里图片仍停在竖屏宽度：阅读区「外层比例盒按列宽、内层图按存储宽」于是上下各空一条，编辑区则靠左 | 图片按列宽等比放大 + 居中（阅读区的 `DiaryImageView` 也顺手去掉了 `GeometryReader` 套壳） |
| 标记行（列表 / 待办）被文本样式改写 | 把一行改成大标题时，图片行的段距被替换成标题的 | `restyle` 跳过图片段落 |

### 5.4 测试

`JustDiaryTests/EditorSpacingTests`（18 例；2026-10-01 核实：原文写 15 例）
用 `NSLayoutManager` **量真实排版**：
每个段落的行盒（`lineFragmentRect`）与紧致墨迹盒（`boundingRect(forGlyphRange:)`）
都要看——TextKit 会把段前 / 段后距折进段落自己的行盒，只看行盒间距会永远读到 0。
断言包括：正文段之间只有正常行距；小标题 / 大标题「上方多出来的空间 > 下方多出来的
空间」（与同样位置的正文段对比，排除字体自身度量差异）；图片上下各恰好
`imageSpacing`；读模式块不含结尾空行；图片块不含段落样式；缺图仍占位；**图片按列宽等比放大、段落居中、
存储尺寸不随列宽改写**；`DiaryImageView` 在 600pt 宽下真的画到两边（用 `ImageRenderer`
渲染后读像素，防止再出现「外层比例盒撑满、里面的图却很小」）。

---

## 六、没有做的事

- **不保留任意磅值。** v2 里已没有 `size`，导入材料中与语义样式不符的字号按块样式
  归一（无法从 v1 的 `size` 判断那是应用写的梯级值还是导入的自定义值，这也是 v1 的
  老问题）。仓库里的数据是测试数据，已按 v2 重新生成。
- **不做应用内字号档位。** 字号只跟随系统「文字大小」，与备忘录一致；应用内再给一档
  字号会和系统设置打架。
- **等宽（Monospaced）样式**：编辑器仍未提供。它需要新的 `ContentPart.style` 取值
  以及阅读、分享长图两条渲染链路的支持，超出本次范围。

---

## 七、列表 / 待办 / 引用怎么画（2026-09-30）

这三种块原先各画各的，且**编辑态与阅读态对不上**：

* 列表圆点是一个 15pt 的实心圆、紧贴正文，没有悬挂缩进 —— 换行后第二行顶到圆点底下；
* 待办复选框同样紧贴文字（`☑验证标题层级`）；
* 引用只是一段 `.backgroundColor`：底色**只跟着字走**，行尾参差、没有内边距、没有竖条，
  读起来像荧光笔而不是引用块。

现在几何集中在一处（`JustDiary/Views/Diary/BlockDecorations.swift` 的 `BlockMetrics`），
两条链路（`PartsCodec` 装配、`RichEditorController` 实时输入）都从这里取；默认档位下的
数值如下，全部乘 `BlockMetrics.scale(typeSize)`（正文 17pt 的动态字号系数）：

| 块 | 几何 |
|---|---|
| 列表 | 圆点 ⌀6.5，圆心在列左 5.5 处；文字缩进 18，`lineSpacing` 同正文、项间段前距 `EditorDesignSize.markerSpacing`（`0.15 × 17`，见第八节；2026-10-01 核实：原文写「`lineSpacing / 段距` 同正文」） |
| 待办 | 复选框 16×16（圆角 0.28×边长，描边 1.2 / 勾 2.1），圆心在列左 9 处；文字缩进 26 |
| 引用 | 底色块横跨整列、圆角 9、上下各外扩 6；左竖条宽 3、距列左 6、上下各内缩 5；文字缩进 16 |

### 7.1 标记 = 一张「宽度等于缩进」的透明画布

`MarkerGlyph` 把圆点 / 复选框画进一张画布里，**画布宽度就是这一行的左缩进**，图形画在
画布左侧 —— 与正文的间距来自画布本身。这样标记仍然只是**一个附件字符**，编辑器里
「标记 = 行首一个附件」的所有光标 / 选区算术（`toggleMarker` / `handleReturn` /
`markerDrops` / `keepCaretOnItsLine`）一个字都不用改（换成「标记 + 制表符」就要改）。

两个必须守住的细节：

1. **画布高度必须精确等于 `ascender + |descender|`，不能向上取整。** 行高由字体与附件
   尺寸取大者决定，多取整最多 1pt，带标记的行折行推进就和正文对不上了
   （`EditorSpacingTests.testMarkerLinesWrapWithTheBodyLineSpacing` 量到 0.01pt）。
2. **图形中心在基线之上 `0.32 × 正文磅值`。** 汉字字面中心约 0.36em、西文 x-height 中心
   约 0.26em，0.32 是两边都能接受的位置（与改造前复选框的落点一致，只是换成了精确的
   基线换算：画布下沿落在 descent 上，图形画在 `ascender − 中心` 处）。

颜色在生成位图时按当前 trait 解析并烤进像素（`MarkerGlyph.image`），所以深浅色切换要由
`DiaryTextView.installDecorations()` 里注册的
`registerForTraitChanges([UITraitUserInterfaceStyle.self])` 触发一次
`refreshMarkerGlyphs(typeSize:)` 就地重画（尺寸不变，不挪动任何一行）；
引用块的图层颜色同一次回调里一起重算。

### 7.2 引用 = 文字后面的一层装饰

引用的判据是**块类型**（`.diaryBlockStyle == quote`，落库为 `ContentPart.style`）；
`.backgroundColor` 退休，只有旧内容 / 导入内容还靠它兜底（`attributesAreQuote`）。
底色块与竖条由 `BlockDecorationLayer` 画在文本视图**自己的子层最底下**：

* 段落样式里给 `firstLineHeadIndent = headIndent = 16`，文字让开竖条；
* 装饰层按 TextKit 2 的**行片段**取这一段**真实行**的排版框（每行 `typographicBounds`
  的并集，只并 `characterRange.length > 0` 的行；2026-10-01 核实：原文写整段的
  `layoutFragmentFrame`，那正是下面第三个坑），
  `enumerateTextLayoutFragments(from:options:.ensuresLayout)` 走到段尾就停，
  并集之后往外扩 6pt、横跨整列。

三个坑：

| 坑 | 现象 | 处理 |
|---|---|---|
| `CALayer` 默认尺寸是 0 | 几何算得再对也什么都画不出来 | 每次刷新按 `bounds` ∪ 所有块的并集设 `frame` |
| 子层顺序会被 `UITextView` 改 | 文本层插到前面，底色盖在字上 | 每次布局把装饰层按回 `index 0`（已经不是第一个时那一次插入才真的动） |
| 用整段的 `layoutFragmentFrame` 当块的框 | **块的蓝底会随后续输入变高变矮**：它把段前距和段落结尾那个空行（`characterRange` 为空的 extra line fragment）都算进来了 —— 文档末尾的引用天然多出一整行，**一旦后面再输入内容，那个空行就消失** | 只并**真实行**的 `typographicBounds`（`characterRange.length > 0`），块因此只跟这一段文字有关；段前距也不再被算进块内（内边距恢复成设计值 6pt） |
| 用 `CGRect.isEmpty` 当守卫 | 空引用行（刚点「引用」还没输入）永远没有底块：那一行的行框**宽度是 0**，而 `isEmpty` 对宽度为 0 也成立 | 只看**纵向**：`height > 0` 才算一行；空段落只有一条 extra line fragment 时，用它的位置 + 这一档字号的正常行高（它自己的高度带着行距，直接用会让块比有字时高一行距） |

装饰层是**子层**而不是子视图：它不参与 `layoutSubviews` 的尺寸协商，也自然跟着滚动内容
一起走。

### 7.3 编辑态 == 阅读态

两条链路共用 `PartsCodec.paragraphStyle(_:center:typeSize:)` 与
`markerParagraphStyle(typeSize:kind:)`，`typingAttributes` / `restyle` /
`styleEmptyParagraph` 都走同一处（B27 那类「编辑时一个样、重开一个样」的根因就是这里
各写一份）。阅读块的 `textContainerInset` 也与编辑区统一为
`BlockMetrics.textContainerInset`（各 6pt）—— 以前是 2 / 10，同一个块进出编辑时正文
上下会跳 8pt。

`JustDiaryTests/BlockStyleRenderingTests` 逐条钉住：标记画布宽度 = 缩进、图形比画布窄、
画布不撑高行盒、引用缩进与装饰块几何、装饰层在最底下、字号档位跟着长、点按钮开的列表 /
引用与装配链路几何相同，最后**把同一个块分别用阅读链路和编辑链路渲染成图，要求逐像素
相同**（0 个像素不同；编辑器末尾那条空段落不属于正文，比较公共高度）。引用块另有四条
回归用例：高度不随后续内容变化（`testQuoteBlockDoesNotChangeWhenContentFollows`，正文 /
短段 / 折行三种情况精确比 frame；2026-10-01 核实：该用例比的是 `CGRect` 相等，
不是逐像素）、两行引用把两行都盖住、空引用行也有块、块只跟这一段
文字有关（不含段前距、不含结尾空行）。

---

## 八、行距与段距：照 Apple 的规范重定（2026-09-30）

用户反馈「行间距 / 段间距看着太小」。查证下来不是感觉问题：正文的行盒只有
**1.19em**，而真正画汉字的 PingFang SC 自己的行高是 **1.40em** —— 汉字上下几乎是贴住的；
两段正文之间更是**一点额外间距都没有**（`paragraphSpacing` = 0），用户按两次回车分段，
存下来之后那段空隙直接消失（空行不入库）。

### 8.1 三个可查的依据

1. **HIG › Typography ›「iOS built-in text styles」的行高**（[developer.apple.com/design/human-interface-guidelines/typography](https://developer.apple.com/design/human-interface-guidelines/typography)）。
   表里给的是 Size + Line height，也就是**下限**：

   | 文本样式 | 本应用的块 | Size → Line height | 倍率 |
   |---|---|---|---|
   | Title 1 | 大标题 `title` | 28 → 34 | 1.21 |
   | Title 2 | 小标题 `heading` | 22 → 28 | 1.27 |
   | Body | 正文 `body` | 17 → 22 | 1.29 |
   | Subheadline | 引用 `quote` | 15 → 20 | 1.33 |

   （模拟器实测 `UIFont.preferredFont(forTextStyle:)`：Body 17pt → `lineHeight` 20.29 +
   `leading` 1.72 = 22.01，与表一致。）

2. **HIG 同一页明确要求长段落用松行距**：

   > "when you display text in wide columns or long passages, more space between lines
   > (loose leading) can make it easier for people to keep their place while moving from
   > one line to the next."

   日记正是「long passages」，所以正文不能只贴着 1.29 的下限走。

3. **中日韩正文必须容得下真正画字的字体**（模拟器实测）：

   | 字体 | `lineHeight ÷ 字号` | 17pt 时的行高 |
   |---|---|---|
   | 系统字体 SF（行盒按它算） | 1.193 | 20.29 |
   | PingFang SC（真正画汉字的） | **1.400** | **23.80** |

   差值 3.5pt：汉字的字面几乎顶满行盒，这就是「中文看着挤」。1.40 是 CJK 的硬下限。

### 8.2 模型

```swift
EditorBlockStyle.lineHeightRatio   // 目标「总行高 ÷ 字号」
EditorBlockStyle.lineSpacing       // = 字号 × (lineHeightRatio − 1.193)
```

| 块 | lineHeightRatio | 行高（默认字号） | 依据 |
|---|---|---|---|
| 大标题 | 1.25 | 35.0（28pt） | HIG 1.21 之上留一点余量 |
| 小标题 | 1.32 | 29.0（22pt） | HIG 1.27 之上留一点余量 |
| 正文 | **1.50** | **25.5（17pt）** | 长段落松行距（HIG）+ 高于 CJK 下限 1.40 |
| 引用 | **1.60** | **24.0（15pt）** | 引用是「引文」，比正文再松一点 |

段距**全部由段前距承担**（`paragraphSpacing` 一律为 0），因为 TextKit 把段前距折进**这一段
自己的行盒**、段后距折进上一段的盒底，而每一行下面本来就还压着 `lineSpacing`。选段前距有
三个好处：两段之间的实际空隙算得清（上一段的 `lineSpacing` + 这一段的段前距）、图片上下
能配平、**贴边的段距会被 TextKit 丢掉**（读模式每块是独立文本视图，块首块尾因此不会多出
空白）。

| 块 | 段前距（默认字号） | 两段之间的实际空隙 |
|---|---|---|
| 正文 `body` | 0.50 × 17 = **8.5** | 5.2 + 8.5 = **13.7**（半行多一点） |
| 小标题 `heading` | 0.55 × 22 = 12.1 | 上面 17.3 / 下面 11.3（仍然「离上文远」） |
| 大标题 `title` | 0.55 × 28 = 15.4 | 上面 20.6 / 下面 10.1 |
| 引用 `quote` | 0.60 × 15 = 9.0 | 上下都 ≈ 14（对称） |
| 列表 / 待办项 | 0.15 × 17 = **2.55** | 5.2 + 2.6 = **7.8**（同一组，挨紧；2026-10-01 核实：按本节模型「上一段的 `lineSpacing` + 这一段的段前距」与代码常量（body `lineSpacing` 5.219、`markerSpacing` 2.55）推出来是 **7.8** —— 这是**推导值，没有测试钉住**；原文的 4.3 + 2.6 = 6.8 在代码里找不到来源） |

### 8.3 图片：两次「看不见的空白」

TextKit 2 把附件放在**基线上**，于是行盒和墨迹不重合。17pt 正文实测：

* 图片**上方**：上一段的行盒底比它的墨迹低 **2.6pt**（0.153em）—— 眼睛看不到；
* 图片**下方**：下面那一行的墨迹从自己的行盒顶往下 **12.5pt**（0.735em）才开始
  （CJK 字面远低于 ascent）—— 同样看不到。

所以图片的段前距要 **−2.6**、段后距要 **−12.5**（各扣掉那一段看不见的空白；
2026-10-01 核实：原文段前距写作 +2.6，与 `imageParagraphStyle()` 的
`imageSpacing − imageTopSlack` 以及本段「读模式同样扣掉 2.6pt」的说法相反），
肉眼上下的空白才真的一样多（都是一段正文之间的 13.7pt）。读模式那一侧由
`DiaryPartsView` 的 padding 给，值同样扣掉了正文块
自己的 `textContainerInset` 与那 2.6pt（`EditorDesignSize.readerImagePadding`），两个模式
因此画出同样的留白。另外**紧跟在图片后面的那一段不再加段前距**（`appendLine(followsImage:)`）
—— 图片自己已经把间距给足，而且读模式里那一段本来就是新的一块、段前距同样不生效。

这些常数是**字体几何**（换字体 / 换书写系统要重新实测），不是设计偏好；
`EditorSpacingTests.testImageIsNotGluedToTheTextAroundIt` 把它画成位图逐行量过。

### 8.4 测试

`JustDiaryTests/EditorSpacingTests` 现在钉住：

* 段后距一律为 0、段前距 > 0，且 大标题 > 小标题 > 正文（`testParagraphSpacingComesFromTheSpaceBefore`）；
* 每个块的行高 ≥ HIG 的行高，成段的块 ≥ CJK 下限，正文 = 1.50
  （`testLineHeightFollowsTheAppleLadderAndTheCJKFloor`）；
* 真排一遍：两段正文之间的空隙 = 段前距（`testBodyParagraphsAreSeparatedByHalfALine`）、
  小标题离上文比离下文远（`testHeadingKeepsMoreRoomAboveThanBelow`）、图片上下的**可见**
  留白一样多且等于 `imageSpacing`（`testImageIsNotGluedToTheTextAroundIt`，按像素量）、
  编辑区与读模式图片留白同值（`testImageIsVisuallyBalancedByTheModel`）；
* 读模式块内的段距与编辑区逐段相等（`testReaderTextChunkKeepsItsParagraphGaps`）。
