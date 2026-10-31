# 一页时光 · SDK / iPhone Duo / Liquid Glass 适配路线（TODO）

> 状态：**只做规划，代码改动暂停**（2026-10-31）
>
> Duo 的 P0 + P1 已落地（见附录）；从现在起本文档是三条工作流的唯一路线图：
> **① 官方 SDK 升级 · ② Duo 内外屏优化 · ③ Liquid Glass 设计优化**。
>
> 基线（实测）：Xcode **27.2** (27B52)、iOS **27.2** SDK、iPhone Duo runtime
> **27.1** (24A94425)、macOS 27.2、Swift 6.4、部署目标 **27.0**、
> `SWIFT_VERSION = 5.0`。已推送：`f03e8d6`（Duo P0）、`0a6d335`（Duo P1）。
>
> 原则：**不为了新 SDK 提高最低系统**；27.1 / 27.2 API 一律 availability 守卫；
> 每个阶段先补可复现的测试与截图，再改视觉；不把「新 API 能编译」当成「必须用」。

---

## 0. 当前基线（先别重复做）

| 项 | 现状 | 结论 |
|---|---|---|
| Xcode / SDK | Xcode 27.2 (27B52) + iOS 27.2 SDK | Build 通过，无源码警告；工程元数据已到 2720 |
| 部署目标 | iOS 27.0，Swift 5 语言模式 | 保持；27.1 Duo API 用 `@available` / `#available` |
| 模拟器 | Duo runtime **27.1**；27.2 runtime 未安装 | 需要一次 27.2 runtime 的兼容性验证（见 A1） |
| Duo P0 | 折痕分栏、窗口 bounds、侧置系统栏 | 已完成，431.5 / 56 / 347 实测见附录 |
| Duo P1 | 设置 / 足迹 / 搜索 600pt 限宽居中 | 已完成；首页保持单栏与 morph |
| 单元测试 | `JustDiaryTests` 157 个通过 | 已包含 4 个 Duo 用例 |
| UI 测试 | 未在 Duo 上跑 | 现有用例写死 18 Pro / SE 的浮条位置，见 B7 |
| Liquid Glass | 已有设计边界与组件，但没有 27.2 后的系统审计 | 见工作流 C；不要先改视觉 |

**已知的模拟器坑（Xcode 27.2 release notes）**：

- Duo 刚启动后的几分钟内，Device Hub 截图 / 录屏可能是**全黑**（187146039）；
- Device Hub 里 VoiceOver / Accessibility Inspector **读不到 Duo 的屏幕内容**（187148389）；
- 内屏 / 外屏切换后，Shift / Command 等修饰键可能失效（189465196）；
- 27.2 runtime 克隆可能因权限失败（188407822），需清掉 `*.sb-*` 临时文件。

这些会伪装成 App bug。测试记录里要写明「黑帧/无障碍不可用是工具问题」。

---

## 1. 工作流 A：官方 SDK 升级

### A1（P0）把 SDK 基线做成可复现的

- 记录一份固定基线：Xcode / SDK / runtime / macOS / Swift / 部署目标 / 构建命令，
  后续每次 Xcode 小版本更新只改这一处并同步 README。
- 安装 **iOS 27.2 simulator runtime**（当前只有 27.1），至少在 27.1 与 27.2
  两个 runtime 上各跑一次构建 + 单测；Duo 的 27.2 runtime 还要验证
  `UIView` 布局边距变化（见 A2）和克隆问题。
- 把 `xcodebuild -runFirstLaunch` 更新 CoreSimulator 的步骤写进开发说明：
  Xcode 27.2 首次使用时旧 CoreSimulator 会导致 `simctl` 卡住 / 设备显示
  “Connecting display…”。
- **验收**：在一台干净机器上按文档能从 clone 到跑起 Duo；构建命令、runtime 版本、
  已知工具坑都可查。

### A2（P0）27.1 / 27.2 行为与 API 审计

- **UIKit 布局边距**：iOS 27.1 起 `UIView` 默认 layout margins 为 0，
  `UIViewController` 仍提供 `systemMinimumLayoutMargins`。本项目的
  `DiaryTextView` / `ReadTextView` / `UIActivityViewController` 包装 / 文件选择器
  需要逐一确认；必要时设 `preservesSuperviewLayoutMargins = true`。
- **废弃与行为变化**：重新跑 27.2 SDK 构建，记录所有新警告；保留
  `MKMapItem.placemark` 的 `@diagnose` 例外，不扩大全局降级。
  已知 `UIScreen.main` 已清掉，`UIScene` / 启动屏门槛已满足。
- **Duo 新能力**：27.2 支持 Standby、Apple Pencil（Duo）。Pencil / Scribble
  只做冒烟测试，除非决定做手写输入；`ArrangementView` / `onHingeChange`
  只在 B5 评估，不在本轮改。
- **验收**：一份「27.2 SDK 新 API / 行为变化 / 警告」清单；
  每个采用的 API 都有 availability 守卫和回退。

### A3（P1）CI 与测试矩阵

- 构建矩阵：Xcode 27.2 × 部署 27.0 × runtime 27.1/27.2；
  设备矩阵：iPhone 18 Pro（普通构图）+ iPhone Duo（内屏/外屏/半折）。
- 每次 PR：`xcodebuild build` + `JustDiaryTests`；UI 测试分批跑，
  不把 Duo 的 Device Hub 限制当成必过门禁。
- 考虑 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 的 CI 配置（不改本地日常构建）。
- **验收**：CI 能在一个明确版本上复现 157 个单测 + 关键 UI 冒烟。

### A4（P2）工程现代化

- 评估 Xcode 27.2 的 JSON `.xcproj` 项目格式（更易合并，但现在不是优先项）。
- Swift 6 语言模式迁移单独立项（当前 `SWIFT_VERSION = 5.0`；此前实测约 72 个错误，
  涉及 `DiaryRepository` / `L10n` / `SQLite` 的全局状态，不能顺手做）。
- Xcode 28 / iOS 28 提前做「可用性探针」，不追 beta。

### A5 版本策略

- **部署目标保持 27.0**：Duo 只跑 27.1+，但没必要让非 Duo 用户丢掉 27.0。
- 每次 Xcode 小版本：只做兼容性 + 工具链更新，不顺手改设计。
- 大版本（28）再评估是否提高最低系统；以真实用户分布为准。

---

## 2. 工作流 B：Duo 内外屏优化

### B0 已知几何

| 显示 / 姿态 | 窗口 | Size Class | 备注 |
|---|---|---|---|
| 内屏 · 竖屏 | 669 × 951 | Regular / Regular | 顶部安全区 82，底部 34 |
| 内屏 · 横屏 | 951 × 669 | Regular / Regular | 右侧竖排栏 84 |
| 外屏 | 466 × 678 / 678 × 466 | compact（竖）/ 按宽度自适应（横） | 系统栏侧置 |
| 半折横屏 | 951 × 669 | Regular / Regular | division `(455.5, 0, 40, 669)` |
| 半折竖屏 | 669 × 951 | Regular / Regular | division `(0, 455.5, 669, 40)` |

P0/P1 只覆盖了首页与三个设置类页面在典型姿态下的版面；**还没有逐屏 QA**。

### B1（P0）全屏幕 × 全姿态 QA

按下面的矩阵逐格看，先记录问题，不急着改：

| 屏幕 | 内屏竖 | 内屏横 | 半折竖 | 半折横 | 外屏竖 | 外屏横 |
|---|---|---|---|---|---|---|
| 首页（月/年/周） | ✅ | ✅ | 待看 | ✅ | 待看 | ✅ |
| 足迹 | ✅ | 待看 | 待看 | 待看 | 待看 | 待看 |
| 搜索 | ✅ | 待看 | 待看 | 待看 | 待看 | 待看 |
| 设置 | ✅ | ✅ | 待看 | 待看 | 待看 | ✅ |
| 日记阅读 | 待看 | 待看 | 待看 | 待看 | 待看 | 待看 |
| 日记编辑 + 键盘 | 待看 | 待看 | 待看 | 待看 | 待看 | 待看 |
| 分享 sheet | 待看 | 待看 | 待看 | 待看 | 待看 | 待看 |

重点检查：

- 内容是否被侧置 TabBar / 状态栏 / 摄像头遮挡；
- 键盘弹起时编辑器格式栏、光标、顶栏是否仍可见；
- 分享长图 sheet 在 466×678 外屏是否够高（系统动作区至少 340pt）；
- 动态字体 XXL / AX 下标题、筛选条、设置行是否溢出；
- 深色 / 增强对比度 / 减弱动态效果；
- 折叠 / 展开过程中是否丢状态（选中日、tab、滚动位置、编辑草稿）。

### B2（P1）外屏专门优化

外屏是 466×678 的 compact 宽度，但仍可能沿用「手机竖屏」的密度：

- 首页月历每格约 50–60pt；日期、农历、选中圆是否还清楚；
- 设置行说明在 466pt 下会不会折行 / 被侧栏挤压；
- 足迹的 5 列统计（省市 / 城市 / 国家 / 片段 / 天数）是否太挤；
- 搜索的时间 / 地点胶囊是否横向溢出；
- 日记顶栏 3 个玻璃按钮 + 返回在 466pt 下是否拥挤；编辑器格式栏是否遮住正文；
- 外屏摄像头常驻，自定义顶栏是否避开。

优先用**信息密度调整**（换行、隐藏次要标签、缩短说明、改成两行统计），
不新增一套完全不同的导航。若确实需要，再评估外屏专属 compact 版面（D7）。

### B3（P1）内屏常规宽度升级（可选，需确认 D6）

当前做法是「限宽 600 + 单栏」。内屏竖屏时设置 / 足迹 / 搜索都是限宽单栏；
内屏横屏时设置仍是全宽单列，足迹已有「趋势 + 清单」分栏，搜索仍是列表单栏。
可选的升级：

1. **设置**：横屏常规宽度下分两列（通用 / 日记规则 / 提醒 / 数据 左右分栏），
   或保持单列 600；
2. **足迹**：竖屏是否也把趋势图 + 地点清单并排；
3. **搜索**：结果列表 + 预览主从；
4. **首页**：内屏竖屏是否改成「日历 + 当日」上下分栏——这会动到年/月/周
   morph，必须单独立项，不在本轮。

建议先只做 2 / 3 的低风险分栏，首页保持现状；每屏先出 669×951 与 951×669
对照截图，再决定是否铺开。

### B4（P1）折叠 / 多任务行为

- **实时更新**：折痕的 `reservedRegions` 变化是否会触发 `AdaptiveLayout` 更新；
  目前是在 `onGeometryChange` 里读，需要在半折/展开的瞬间实测（必要时用
  `onHingeChange` 触发一次重读，但只做布局失效，不用角度做布局）。
- **50/50 分屏**：窗口 475×951 时 `containerWidth`、`contentColumn`、
  `isPortrait`、侧栏方向都要正确；在分屏里检查四个 tab + 日记页。
- **多窗口**：Duo 内屏支持多个 scene，外屏不支持新建窗口；当前 Info.plist
  已声明 multiple scenes，但没有专门的窗口管理/错误处理。先确认是否要支持，
  不支持就明确记录。
- **摄像头**：FaceTime 相机 active 时的 occlusion 是否与竖排栏/顶栏重叠。
- **键盘 / sheet**：半折时系统 sheet 会滑开，但自定义分享面板和格式栏要自己确认。

### B5（P2）Duo API 的下一步

- `ArrangementView`：D3 已决定「暂不评估」。如果 B3 要做双列，再拿它和现有
  `HStack` 对比；不要为了用它而改布局。
- `onHingeChange`：只用于动效/触感/状态提示，不用于版面判断。
- `UIHinge` / `SceneAccessory` / Apple Pencil：按产品需要评估，不默认接。

### B6（P1）无障碍与性能

- Device Hub 在 Duo 上读不到 VoiceOver 内容（工具限制），无障碍必须用**真机**
  或普通 iPhone 模拟器验证；Duo 上至少验证大字体、对比度、Reduce Motion。
- 669pt / 951pt 宽下的连续月历流、设置长列表、搜索滚动是否稳在 60/120fps；
  玻璃层和 `Canvas` 叠加时重点看。
- 命中区域：侧栏、半折边缘、玻璃胶囊在 466pt 外屏上是否仍 ≥44pt。

### B7（P1）测试自动化

- 现有 `PortraitLayoutUITests` / `LandscapeLayoutUITests` 写死了 18 Pro / SE 的
  浮条位置；Duo 横屏的 TabBar 在右侧，直接跑会误报。要么参数化，要么新增
  `DuoLayoutUITests`。
- Device Hub 没有公开的 hinge 命令，姿态切换目前靠手动；UI 测试只能在
  当前姿态下跑。考虑用「多套 destination + 预先摆好姿态」的方式做截图回归，
  不把姿态自动化写进 App 代码。
- 已知黑帧问题：等待几分钟或重启 Device Hub 后再截图，不要把黑帧当 App 回归。

---

## 3. 工作流 C：Liquid Glass 设计优化

### C0 现状盘点

| 区域 | 当前实现 | 下一步 |
|---|---|---|
| 首页返回胶囊 | 裸 `.glassEffect` Capsule | 纳入 `GlassEffectContainer` / transition |
| 首页「今天」`InfoCapsule` | `.buttonStyle(.glass)` | 检查容器化与对比度 |
| 搜索框 `GlassSearchField` | 透明底 + `.glassEffect` | 检查对比度与嵌套 |
| 筛选 chip / 动作 chip | `.buttonStyle(.glass)` | 分组容器 / union |
| 玻璃图标按钮 | `.buttonStyle(.glass)` + `.buttonBorderShape` | 统一尺寸与 hit target |
| 主 / 次按钮 | 实底 / 半透明底 + `.glassEffect` | 保留品牌色，检查 tint 与对比 |
| 编辑器格式栏 `FontToolbar` | 玻璃面板 + 普通按钮 | 容器化 + 出现/消失 transition |
| 设置导出 | `.glassProminent` | 检查 spinner / 禁用态 |
| 系统 TabBar / sheet | 系统玻璃 | Duo 侧栏 / 外屏下验证 |
| 内容卡片 | `diaryCard`，无玻璃 | ✅ 保持；不要回退 |

当前没有用 `GlassEffectContainer`、`glassEffectID` / `glassEffectUnion`、
`glassEffectTransition`。

### C1（P0）按 HIG / WWDC 做一次审计

- 只列问题，不改代码：每个玻璃面是「控件层」还是「内容层」？
  内容层出现玻璃就是 bug；控件层没有可折射内容时，裸 `.glassEffect`
  是否应该换成 `.buttonStyle(.glass)`？
- 检查「玻璃上叠玻璃」（搜索框里的图标按钮、格式栏里的按钮、chip 里的按钮）。
- 检查横向滚动裁切（`.buttonStyle(.glass)` 需要上下余量）。
- 检查 Duo：侧置 TabBar、状态栏/摄像头、半折时玻璃是否落在曲面上。
- 检查深浅色、增强对比度、降低透明度下的文字对比度；品牌色固定是有意的。
- **验收**：一张「区域 / 现状 / 结论（保留/换 API/删除）」清单 + 截图。

### C2（P1）结构与动效

- **`GlassEffectContainer`**：把首页头部、格式栏、筛选 chip 组、图标按钮组
  收进容器，让系统合并采样、减少层数；容器 spacing 与现有间距对齐。
- **`glassEffectID` / `glassEffectUnion`**：用于 chip / 过滤条件在展开、选中、
  morph 时的连续形状；不为了动效硬造动画。
- **`glassEffectTransition`**：格式栏、搜索控制条、以后新增的浮动提示的出现/消失；
  `matchedGeometry` 只用在确实有共享形状的地方。
- **`Glass.clear` / `.regular` / `.identity`**：区分「浮在内容上的控件」与
  「需要强调的主行动」；保留 `GlassPrimaryButton` 的实底品牌色。
- **不叠玻璃**：容器内只留一层玻璃；嵌套按钮改用普通样式。
- 先做 1–2 个代表性区域（首页头 + 格式栏），出前后截图，再决定是否铺开。

### C3（P1）Duo 集成

- 侧置 TabBar 是系统玻璃；自定义顶栏 / 胶囊要和它的圆角、描边、层级一致，
  不要出现「系统玻璃栏 + 自绘玻璃条」两条竞争。
- 用 `toolbarVerticalEdge` 对齐自定义控件；外屏顶栏避开摄像头。
- 半折时玻璃控件不要压在折痕上；sheet 的玻璃背景交给系统，不覆盖
  `presentationBackground`。
- 动态字体放大时，玻璃按钮的 padding / 最小高度要跟着长，不能裁字。

### C4（P1）无障碍、对比度与性能

- 增强对比度：玻璃边缘和文字要加深；降低透明度：内容不能被玻璃洗白。
- 深色模式：玻璃高光不能变成灰雾；品牌色 button 的白字对比度保持。
- VoiceOver：玻璃图标按钮必须有 label / trait；纯装饰不重复播报。
- 性能：统计一屏玻璃层数；用 `GlassEffectContainer` 合并；在 Duo 951pt
  和 466pt 外屏上分别滚动月历 / 设置 / 搜索，观察掉帧。
- **验收**：无「内容层玻璃」、无嵌套玻璃、对比度通过、滚动稳定。

### C5（P2）回归与设计文档

- 建立玻璃区域的截图基线：浅/深、增强对比度、降低透明度、XXL、Duo 内/外屏。
- 更新 `docs/design-system.md` §5 的边界与例外；记录「为什么保留品牌色实底」。
- 设计令牌与 `docs/design/` 保持同步；如果引入新圆角/间距，先改令牌再改页面。

---

## 4. 测试与验收

| 类型 | 范围 | 频率 | 备注 |
|---|---|---|---|
| Build | 27.2 SDK，部署 27.0 | 每次提交 | 0 源码警告 |
| Unit | `JustDiaryTests` 157+ | 每次提交 | Duo 用例已加 |
| UI 冒烟 | 18 Pro + Duo 典型姿态 | 每个 PR / 每日 | 先修掉写死尺寸的断言 |
| 手动姿态 | 内/外屏 × 开/半折/合 × 横/竖 | 每个 Duo 改动 | Device Hub 按钮；记录黑帧工具问题 |
| 截图回归 | 玻璃区域、限宽页面、分栏 | 每个视觉改动 | 浅/深/对比度/字号 |
| 性能 | 月历滚动、设置长列表、玻璃层 | 每轮视觉改动 | Instruments / 掉帧 |
| 无障碍 | 大字体、对比度、VoiceOver | 每轮 | Duo 的 VoiceOver 用真机 |

**退出条件**：

- 三条工作流的 P0 项全部有结论（做/不做/延后），不是「待看」；
- 每个新增 API 有 availability 守卫和回退；
- 没有内容层玻璃、没有嵌套玻璃、没有侧栏遮挡；
- 18 Pro / SE 的既有版面数值不回归；
- 文档、README、测试记录同步。

---

## 5. 建议排期

| 波次 | 内容 | 产出 |
|---|---|---|
| **第 1 波（接下来）** | A1 基线、A2 27.2 审计、B1 外屏 QA、C1 玻璃审计 | 问题清单 + 基线文档；不改视觉 |
| **第 2 波** | B2 外屏密度、B4 分屏/折叠、C2 玻璃结构、C3 Duo 集成 | 1–2 个代表性页面先落地 + 截图 |
| **第 3 波** | A3 CI、B3 双列（若 D6 同意）、B6 无障碍/性能、C4/C5 | 测试门禁、设计文档收口 |

第 1 波不写代码；第 2 波每项先出对照图再合入。

---

## 6. 还需要确认的决策

| 编号 | 问题 | 建议 |
|---|---|---|
| **D6** | 内屏横屏的设置 / 足迹 / 搜索要不要做双列？ | 先做足迹/搜索的低风险分栏，设置保持 600 单列；首页不动 |
| **D7** | 外屏是否做专属 compact 版面？ | 先按 B1 找到具体溢出点，只做密度调整；不新造导航 |
| **D8** | Liquid Glass 做到什么程度？ | 保守清理 + 容器化 1–2 处；不全面重做视觉 |
| **D9** | 是否下载 27.2 runtime 做兼容性验证？ | 建议装一次，作为 A1 的一部分 |
| **D10** | 真机 / Pencil / VoiceOver 的测试资源？ | 需要一台真机做无障碍与 Pencil 冒烟；没有就明确写「未验证」 |

---

# 附录：Duo 实测与已实现记录（2026-10-28 / 10-31）

> 以下保留当时的实测数据、问题清单和已落地细节；新的工作以 §1–§6 为准。

> **2026-10-31 实现记录（P0 + P1）**
>
> - `AdaptiveLayout` 增加 `FoldRegion` / `SplitMetrics` / `verticalBarEdge` /
>   `isRegularWidth`；Reader 读 `GeometryProxy.reservedRegions`（27.1+，
>   `includeInactive`）和 `toolbarVerticalEdge`。
> - 窗口尺寸改用 key window bounds（修 50/50 分屏 / 可缩放窗口的错算）。
> - 半折横屏：折痕带变 gutter，左右两栏各留 8pt 安全边（实测 431.5 / 56 / 347）。
> - 竖排系统栏时底部只让 `safeArea.bottom`，不再减 64/83（Duo 横屏/外屏）。
> - **D1 = 限宽居中**：`regularWidthContentCap(600)` 应用到设置 / 足迹 / 搜索；
>   首页保持单栏与年/月/周 morph 不变。
> - **D2 = 按 Apple 指南**：月历是连续滚动内容，**不**在横折痕处插空隙；
>   系统栏 / 弹层由系统避让，应用只保证自己的浮动控件不在折痕上。
> - 新增 `SplitLayoutTests` 的 Duo 用例；工程元数据升到 27.2。
> - **未做**：P2 `ArrangementView`（D3 暂不评估）/ 多窗口 / UI 测试矩阵。

---

## 0. 一句话结论

**P0 + P1 已修：折痕参与横屏分栏、窗口尺寸改用窗口 bounds、竖排系统栏不再按
底部横栏留白；Duo 内屏竖屏的设置/足迹/搜索按 600pt 限宽居中。**
半折竖屏按 Apple 指南保持滚动内容连续。剩余的是 P2 的 `ArrangementView` /
多窗口 / UI 测试矩阵；下面 §3 的问题清单保留为「发现时的原始记录」，其中
P0 三条与 P1 版面已在本轮实现。

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

### P1-1 内屏竖屏是 Regular/Regular，但四屏仍是「拉长的 iPhone」（**D1 已定**）

实测时的样子：

- `SettingsView`（`SettingsView.swift:19`）只加了 16pt 页面边距，卡片铺满
  637pt，行内文字与右侧值之间大片空白；
- `FootprintView`（`FootprintView.swift:36`）在 `isPortrait` 时走单栏，
  669pt 宽的统计/清单卡片显得空；
- `SearchView`（`SearchView.swift:161`）在 `isPortrait` 时时间与地点上下堆叠，
  横向空间浪费；
- `HomeView` 单栏月历：每格 ~95pt、农历字 ~11pt，格子明显偏大。

Apple 的 Duo 指南明确说「不要把 iPhone App 直接拉宽」，并建议在常规宽度上
使用分栏 / 双列。**D1 结论：先做保守的「限宽居中」**：

- `regularWidthContentCap(600)` 应用到 **设置 / 足迹 / 搜索**；
- 首页保持单栏与年/月/周 morph 不动（避免改掉已确认的竖屏交互）；
- 双列（首页分栏 / 设置双列 / 搜索主从 / 足迹图表+清单）留作 P2 的可选升级。

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

### P1-3 半折竖屏：滚动内容 vs 可点击日期（**D2 已定**）

- 竖屏折痕是**横带**（y 455.5…495.5），月历是连续滚动的，但日期格子可点击。
- Apple 的指南：「可滚动内容不必避开折痕；可交互元素尽量避开」。日历官方 App
  与备忘录都把正文/列表当作滚动内容，不因折痕插固定空隙；系统弹层/工具栏由系统避让。
- **D2 结论**：跟随 Apple 指南，月历保持连续滚动，**不**插 40pt 空隙；
  应用只保证自己的浮动控件（首页胶囊、底部栏、日记顶栏）不在折痕上。
  折叠/展开时月历几何不跳版。

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

## 5. 已确认的决策

| 编号 | 问题 | 结论 |
|---|---|---|
| **D1** | 内屏竖屏（Regular/Regular）怎么排？ | **A 限宽居中（600pt）**；设置 / 足迹 / 搜索已接 `regularWidthContentCap`，首页保持单栏与 morph 不动 |
| **D2** | 半折竖屏的月历折痕怎么处理？ | **按 Apple 指南：滚动内容不避让，不在折痕处插 40pt 空隙**；系统栏 / 弹层由系统处理 |
| **D3** | 最低系统版本？ | **保持 27.0**；Duo API 全部用 `@available` / `#available` |
| **D4** | 本轮范围？ | **P0 + P1 已实现**；P2 `ArrangementView` / 多窗口 / UI 测试矩阵暂不评估 |
| **D5** | 提交 / 推送 | 已提交并推送到 `origin/main`（`f03e8d6` 及后续 P1 提交） |

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
