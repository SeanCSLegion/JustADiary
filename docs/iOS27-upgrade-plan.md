# 一页时光 · iOS 27 / macOS 27 适配升级方案

> 状态：**待确认（第 2 轮）**
> 基线环境（已实测）：Xcode 27.0 (27A266a)、iOS 27.0 SDK (24A430)、macOS 27.0 (26A428)、Swift 6.4
> 已确认：部署目标 → **iOS 27.0**；支持 **「Designed for iPad」**；改造深度 **激进**

---

## 0. 现状核查（全部实测，非推测）

| 检查项 | 结果 |
|---|---|
| iOS 27 SDK 编译 | ✅ 通过，**只有 1 条告警**（`MKMapItem.placemark`） |
| iOS 27 模拟器运行 | ✅ 正常，Liquid Glass 渲染正确 |
| UI 测试 | ✅ **4/4 通过** |
| iOS 27 **UIScene 硬门槛**（不满足会启动失败） | ✅ 已满足 |
| iOS 27 **启动屏上传门槛**（ITMS-90870） | ✅ 已满足 |
| iOS 27 新增废弃 API | ✅ 需要用的一个都没踩到 |
| Liquid Glass API 本身 | ✅ iOS 27 未改也未废弃，签名不变 |

**项目本身没坏。** 这次的价值在目标对齐、工程现代化、iPad/Mac 支持、采纳新能力，以及下面这个新增的**地图页重设计**。

---

## 1. 你已确认的决定

| # | 决定 | 我方处理 |
|---|---|---|
| 1 | 并发新默认值 —— 你不清楚是什么 | → 见 §3，已用大白话解释 + 实测数据 + 我的建议 |
| 2 | **拖拽排序不做** | ✅ 已从方案删除。理由（日记按时间线性、不是笔记）完全成立 |
| 3 | 顶栏可按官方推荐改，但**首页交互逻辑不能变** | ⚠️ 见 §5.1，需要你确认我理解的范围 |
| 4 | 内容区可以去 Liquid Glass | ✅ 采纳；见 §5.2 |
| 5 | 调研文档保留 | ✅ 已移到 `docs/research/` |
| 6 | **地图功能想重新设计** | → 见 §6，这是本轮重点 |

---

## 2. P1 · 目标版本与工程元数据

**文件**：`generate_project.py`（构建设置唯一真源）、`JustDiary.xcodeproj/project.pbxproj`、`README.md`

1. `IPHONEOS_DEPLOYMENT_TARGET`：`26.0` → **`27.0`**（Debug + Release）
2. `LastSwiftUpdateCheck` / `LastUpgradeCheck`：`2600` → **`2700`**；`CreatedOnToolsVersion`：`26.0` → **`27.0`**
3. `README.md` 同步更新

> 项目由脚本生成 pbxproj，**所有构建设置都改脚本再重新生成**，不手改 pbxproj。

---

## 3. P2 · 关于「并发新默认值」——先把它讲清楚

Xcode 27 新建工程时会**默认打开**两个 Swift 编译器开关。它们不改变功能，只改变编译器"检查你的严格程度"。下面用大白话说明。

### 3.1 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

**它是什么**：Swift 里每个类型/方法都有个隐形标签——"我该在哪个线程上跑"。以前你**不写**这个标签，编译器就不管；打开这个开关后，**不写 = 默认在主线程（MainActor）上跑**，编译器会按这个前提去检查。

**为什么要开**：iOS 的 UI 只能在主线程碰，数据竞争（两个线程同时改一份数据）是最难查的一类 bug。打开后，这类问题在**编译期**就报出来，而不是上线后偶发闪退。

**对本项目的实测代价**：0 错误、**55 个告警**。原因很具体——项目只有两处真的跑在后台：

- `Services/BackupService.swift`（21 处）：备份压缩/解压在后台 Task 里跑，但 `BackupManifest`、`AppSettings` 这些**纯数据模型**被默认当成主线程类型，后台编解码它们就不合规。
- `Data/DiaryRepository.swift`（2 处）：数据库在串行队列上跑，`blockFromRow` 等**纯静态方法**被当成主线程方法。
- 其余零星分布在 `MediaStore` / `ContentPart` / `DateUtil` / `MapViewModel`，性质相同。

**修法**：给这些**纯函数和值类型**标 `nonisolated`，意思是"我确实不在主线程，不用按主线程要求我"。

**关键点**：这**只是加标注**，不改任何一行运行逻辑，不改线程模型，不改数据库队列。被标的全是无状态的纯计算。

### 3.2 `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`

**它是什么**：以前 A 文件 `import Foundation`，就能顺带用上 Foundation 间接引入的 `os` 模块的东西。打开后不行了——**你要用哪个模块，就得自己写 `import`**。

**对本项目的实测代价**：**210 个报错，全是同一条**——9 个文件用了 `Log.xxx`（`os` 模块的 `Logger`），但自己没写 `import os`。**补上 `import os` 就全部解决**。

**为什么要开**：依赖关系显式化。否则哪天某个间接 import 消失，你的代码会毫无预兆地编译失败，而且报错信息指不到真正原因。

### 3.3 我的建议

**建议做**，理由：

- 两项都与 Xcode 27 新工程默认一致，属于"跟上官方基线"；
- 改动虽涉及 13 个文件，但**全部是机械、语义中性**的（加标注 / 加 import），不碰业务逻辑；
- 现有的 `ImportUITests` 正好覆盖备份导入导出、`LanguageThemeUITests` 覆盖设置变更，回归有保障；
- 真正的大头是 **Swift 6 语言模式（实测 72 个错误**，涉及 `DiaryRepository`/`L10n`/`SQLite` 的全局状态改造），那个我建议独立立项。而**现在做这两项，将来切 Swift 6 会省一大截**。

**可以单独裁掉**：这两项严格说不是"用 iOS 27 SDK 编译"的必需条件。你要是不想动 13 个文件，我可以只做 P1/P3/P4/P5，把 P2 留作后续任务。

### 3.4 其他构建设置（已实测验证安全）

同时对齐 Xcode 27 模板的其余设置：`LOCALIZATION_PREFERS_STRING_CATALOGS`、`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`、`ENABLE_USER_SCRIPT_SANDBOXING`，以及约 20 项 Clang/GCC 警告开关。

> 我已经把这几项**实际跑了一遍构建验证**：0 error，且没有引入任何新告警。

---

## 4. P3 · MapKit 废弃 API

### 4.1 结论：现有代码的判断是对的，不是偷懒

我写了探针程序在 macOS 27 上对 4 个中文地址做正地理编码，实测新旧 API 对比：

| 地址 | 新 API 能拿到 | 只有旧 `placemark` 能拿到 |
|---|---|---|
| 深圳市南山区科技园 | `cityName`=深圳市、`regionName`=中国 | **`administrativeArea`=广东省**、**`subLocality`=南山区** |
| 杭州市西湖区 | `cityName`=杭州市、`regionName`=中国 | **`administrativeArea`=浙江省**、**`subLocality`=西湖区** |
| 北京市海淀区中关村大街1号 | `cityName`=北京市 | **`subLocality`=海淀区**、**`thoroughfare`=中关村大街** |

**省、区、街道在新 API 里完全没有对应字段**。Apple DTS 工程师也承认了这个缺口，并明确反对手工解析地址串。所以保留 `placemark` 是当前唯一可行方案。

### 4.2 做法

1. **保留** `placemark` 作为结构化省/区/街道的唯一来源，收敛在唯一一个访问器里。
2. **消除告警**：用 Swift 6.4 新增的 `@diagnose`（SE-0522）**精准抑制这一条诊断**（我已实测有效），而不是全局关告警：
   ```swift
   @diagnose(DeprecatedDeclaration, as: ignored,
             reason: "MKAddressRepresentations 不提供 administrativeArea/subLocality；省市区统计必需")
   nonisolated func diaryPlacemark(_ item: MKMapItem) -> CLPlacemark { item.placemark }
   ```
3. 采纳新 API 中确实更好的部分：坐标改用 `mapItem.location.coordinate`；给 `MKReverseGeocodingRequest` 设 `preferredLocale`，让地址格式跟随 App 语言而非设备语言。
4. **不做**字符串解析 `cityWithContext`——Apple 明确反对，且 Apple 一旦改格式会静默算出错误的省份统计。

---

## 5. P4 / P5 · iPad·Mac 支持与新 API 采纳

### 5.1 顶栏改造范围（**需你确认**）

我原方案说的"顶栏"是指 **`DiaryPageView`（日记编辑/阅读页）的顶部按钮行**——阅读态有 4 个玻璃图标按钮（搜索/编辑/分享），编辑态有 3 个（插图/撤销/保存），窄屏或大字体下会挤压。改造是用系统 `Toolbar` + `ToolbarOverflowMenu` 做自动溢出。

**我完全不打算碰首页（`HomeView`）**：首页的年月切换、今天按钮、日历网格点击/缩放/morph 动画、拖拽翻页等交互逻辑一行都不改。

⚠️ **请确认**：你说的"首页交互不能变"，是指「别动 HomeView」对吧？还是说连日记页顶栏也不许动？我按前者理解。

### 5.2 内容区去 Liquid Glass（已批准）

WWDC26 session 8120 明确建议**内容区不要用 Liquid Glass**（下方没有可折射内容），玻璃按钮应当用 `.buttonStyle(.glass)` 而非裸 `.glassEffect`。项目目前把 `.glassEffect` 用在了所有内容卡片上。

改法：内容卡片 → 系统材质/分组背景色；Liquid Glass 只保留给**浮在内容之上的控件层**（工具条、芯片、悬浮按钮、缩放条）。

**我会先改 1~2 个代表性页面并给你截图对比**，你确认风格后再铺开——不单方面重做视觉。

### 5.3 其余采纳项（低风险）

- **`appAlert` 现代化**：现在用的 `alert(item:) -> Alert` 是 iOS 15 起就废弃的写法。改用新的 `alert(item:)`，`AppAlertItem` 结构**原样映射**，所有调用点不用改。
- **`GeometryProxy.concentricCornerRadii`**（iOS 27 新增）：替代现在手写的 `cornerRadius: 18/20/28` 魔法数字，让嵌套圆角几何一致。
- **`textInputBorderShape(_:)`**：应用到搜索框与编辑器输入区。
- **`@ContentBuilder`**：统一现有的 `@ViewBuilder` 命名。

### 5.4 iPad / Mac「Designed for iPad」

1. `TARGETED_DEVICE_FAMILY`：`1` → **`"1,2"`**（现状 `UIDeviceFamily = [1]`，是 iPhone-only，只能算「Designed for iPhone」）
2. 补齐 `UISupportedInterfaceOrientations_iPhone/_iPad` 键（现状一个都没有）
3. **可调整尺寸适配**（真正的工作量）：iOS 27 / macOS 27 下 App 完全可缩放，"方向"退化为偏好且在缩放时被忽略。
   - `Views/Components/Components.swift` 的 `Screen` 目前 fallback 硬编码 `393×852` → 改为基于 window scene 几何的自适应兜底
   - `MapViewModel.fitZoom` / `zoomRange` 用固定尺寸估算 → 见 §6，这些代码会被删除
   - 逐个核对 `GeoMapCanvas` / `CalendarGrids` / `DiaryPageView` 键盘避让的尺寸假设

⚠️ 这是**风险最高**的一段：单列 iPhone 布局变成任意尺寸，必须逐屏看截图。发现问题我会报告，不会自行"顺手改设计"。

---

## 6. 地图页重设计（本轮重点）

### 6.1 先量化问题——你的担心完全正确

| 项目 | 实测 |
|---|---|
| `Resources/map` 体积 | **2.9 MB** |
| App 全部资源体积 | 3.1 MB |
| **地图占全部资源** | **94%** |
| 地图相关代码 | **1546 行**（`GeoMap` 308 + `GeoMapCanvas` 292 + `MapView` 423 + `MapViewModel` 413 + `MapDataService` 110） |
| 覆盖范围 | `world.json` 仅国界(252K)；`china.json` 省级(572K)；`cities/` 24 个省级文件(2.1M) —— **只有中国有省/市级边界** |

所以：**94% 的包体积，换来的是一张只在中国能画全的地图**。你的判断没问题。

### 6.2 一个重要发现：数据层本来就是全球通用的

我查了数据链路：`EditBlock` / `MapPointRow` 里的 `country` / `countryCode` / `region1` / `region2` / `region3` **全部来自 `CLPlacemark`，任何国家都有值**。

**也就是说：中国以外的用户，现在已经在正确记录国家、省份、城市了——只是画不出来。**

这意味着方案非常干净：**换掉渲染层，保留数据层**。不需要数据库迁移，不需要改定位与反地理编码，历史数据全部可复用。

### 6.3 方案 A（我的推荐）：足迹档案页

把「地图」标签页改成「足迹」，用**数据驱动**替代**图形渲染**：

| 区块 | 内容 | 说明 |
|---|---|---|
| ① 总览卡 | **保留现有 5 项指标**：省市 / 城市 / 国家 / 片段 / 天数 | 你要保留的部分，原样不动 |
| ② 年度趋势 | 每年的记录天数 / 地点数柱状图 | 用系统 **Swift Charts**，**零包体积**，全球通用 |
| ③ 足迹清单 | 国家 → 省份 → 城市 三级可展开列表，每项带记录数 | 点击任一项 → 跳到该地点的日记列表（复用现有 `openDiary`） |
| ④ 时间筛选 | **保留现有**的年份 chips + 自定义时间范围 | 原样不动 |

**收益**：包体积 **−2.9 MB（−94%）**；代码 **−约 1000 行**；全球可用；完全离线；iPad/Mac 天然适配（不再有尺寸假设）。
**代价**：失去"地图"的视觉呈现。

### 6.4 方案 B（可选增强）：系统 MapKit 只画标记点

在方案 A 基础上，多加一个「在地图中查看」的二级页面，用**系统 `Map` + `Marker`** 渲染打卡点：

- **零包体积**（MapKit 是系统框架）、**全球覆盖**、无需任何 GeoJSON
- 代价：**需要联网**；且如果还想要"省份热力着色"，就又需要省份边界数据（等于回到老问题）——所以**只画点，不画边界**

### 6.5 我的建议

**做方案 A，把方案 B 留作可选**。理由：你的核心诉求是"保留统计、去掉地图、别让包变大"，A 完整满足且最干净；B 能零成本保留一点地图能力，但引入了网络依赖，对"本地优先的日记 App"来说是个取舍——**这个取舍该由你决定**。

### 6.6 需要一并决定的细节

- **标签页名称**：「地图」→「足迹」？（涉及 `map_title` 等 L10n 文案）
- **标签页图标**：现在是 `map.fill` → 换成 `figure.walk` / `globe.asia.australia.fill`？
- **类型命名**：`MapView`/`MapViewModel` 是否一并改名为 `FootprintView`/`FootprintViewModel`（纯改名，但会让代码名副其实）？
- **`MapDataService` 的质心补偿逻辑会删掉**：现在它会给"没有坐标但有地区"的记录按同城/同省均值补一个坐标——那是**只为了在地图上放点**。新设计不需要坐标。副作用：`未记录` 的计数口径会变（现在 = 无坐标且补不出质心；新口径 = 完全没有地点信息）。这个改动我认为更合理，但属于行为变化，先跟你说一声。
- **UI 测试要改**：`SmokeUITests` 现在断言地图页出现 `staticTexts["省市"]`，文案/结构变了要同步更新。

---

## 7. P7 · 回归验证清单

每阶段后 + 全案完成后：

1. `xcodebuild build`（Debug + Release）→ **0 error / 0 warning**
2. UI 测试全绿（含新增/更新的足迹页断言）
3. 运行日志核对：无新告警、无废弃 API 运行时提示
4. **多尺寸截图核对**：iPhone 17 / iPhone 17e（小屏）/ iPad Pro 13" / iPad 分屏 / 宽窗口，覆盖首页日历（月/年）、日记编辑与阅读、**足迹页**、搜索、设置
5. **备份导入导出往返测试**（P2 动了并发标注，`BackupService` 是重点回归对象）
6. 包体积对比：改前 / 改后 `.app` 实测大小
7. 「Designed for iPad」核查：产物 `UIDeviceFamily` 含 2、方向键齐备、无 iPhone-only 硬依赖

> 运行 UI 测试需要伪终端，在我的沙箱里需要一次授权；**代码修改本身不需要**。

---

## 8. 执行顺序

```
P1 目标版本/元数据  →  P2 构建设置+并发（可选）  →  P3 MapKit
   →  P4 iPad/Mac 支持  →  P5 新 API 采纳 + 内容区去玻璃
   →  P6 地图页重设计  →  P7 全量回归
```

每阶段结束汇报结果 + 验证证据，不攒到最后。

---

## 9. 第 2 轮需要你确认的问题

1. **§5.1 顶栏范围**：我理解成"只改日记页顶栏，完全不碰 HomeView"，对吗？
2. **§3.3 并发新默认值**：做（13 个文件机械改动，我推荐）/ 不做（留作后续）？
3. **§6.5 地图方案**：选 A（纯统计足迹页）/ A + B（额外加系统 MapKit 标记点页）？
4. **§6.6**：标签页叫「足迹」行吗？图标换成 `figure.walk` 行吗？要不要顺手把 `MapView`/`MapViewModel` 改名？
5. **`TabRole.prominent`**：要不要让「日记」标签页在 Tab Bar 上做成视觉重点？（纯设计取向，你说不做我就不做）

确认后我从 P1 开始。
