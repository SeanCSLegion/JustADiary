# 一页时光（JustADiary）

基于 SwiftUI 的日记软件（iOS 27+），原为 HarmonyOS 应用迁移而来。

## 功能

- **首页日历**：月历/年历查看，支持镜头缩放切换动画、今日圆环/选中实心圆标识、日记日期圆点标注
- **日记编辑**：富文本编辑器（标题、引用、列表、待办、粗体/斜体/删除线/下划线、居中对齐），支持插入图片、自动记录时间与位置
- **足迹**：按国家/省份/城市三级聚合已记录的地点（可展开清单）+ 年度记录天数趋势图，支持按年份与自定义时间范围筛选
- **搜索**：全文搜索（SQLite FTS5 + CJK 分词）+ 时间/地点筛选，关键词高亮
- **设置**：语言（中/英，即时生效）、主题（浅/深/跟随系统）、日记开始时间、周起始、自动定位、提醒、历史编辑、备份导入导出

## 设计

- 采用 iOS 26 引入、iOS 27 继续沿用的 **Liquid Glass** 设计语言，但**只在控件层使用**：`buttonStyle(.glass)` / `.glassProminent` 的按钮、芯片、搜索框与悬浮按钮
  - 按 WWDC26 session 8120 的建议，**内容区不使用 Liquid Glass**（下方没有可折射的内容，玻璃卡片会读作「浮在玻璃上的卡片」）。内容卡片统一走 `diaryCard(cornerRadius:)`：系统分组背景色 + 细描边 + 柔和阴影
- 跟随系统显示设置：**动态字体**（`diaryFont(_:weight:)` 把显式字号按 `UIFontMetrics` 缩放，日历 Canvas 文字单独缩放）、
  **减弱动态效果**（morph 退化为快速交叉淡入）、**增强对比度**（卡片描边加深）、浅色/深色
- 本地化使用 **String Catalog**（`Localizable.xcstrings`），通过 `String(localized:locale:)` 支持应用内语言即时切换
- 主题色板迁移至 **Asset Catalog** 动态色（明暗自动切换），品牌色/混合色仍由 `Theme` 计算
- 自定义组件：`GlassChip`、`GlassActionChip`、`GlassCountBadge`、`PressableGlassIcon`、`diaryCard`（内容卡片修饰符）、`GlassEmptyState`、`AppAlertItem`

## 架构

```
JustDiary/
├── App/           # 入口、AppDelegate
├── Views/         # 首页 / 日记页 / 足迹 / 搜索 / 设置（纯展示 + 交互）
│   └── Components/   # 共享组件、动画常量
├── ViewModels/    # @Observable ViewModel（Home/Diary/Footprint/Search/Settings），数据层收敛于此
├── Services/      # 主题、定位（CLLocationUpdate.liveUpdates）、提醒、备份（Compression 框架 zip）、足迹聚合、媒体缓存
├── Data/          # SQLite（串行队列）、日记仓库
├── Models/        # 数据模型、日期工具
└── Resources/     # String Catalog、图标、动态色板
```

关键设计：
- `DiaryRepository` 所有数据库访问均在串行队列执行（`runOnQueue`）
- 备份/导入/分享渲染在后台任务执行；zip 采用标准格式（raw deflate + CRC32 校验）
- `ContentPartCache` 缓存 JSON 解析结果；`DiaryImageStore` 缓存降采样图片（ImageIO）
- 足迹页是**纯数据聚合**（`FootprintDataService`）：不依赖坐标，也不需要任何打包的地理边界数据，因此对任何国家都可用
- 并发隔离：项目启用 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，UI 层默认主线程隔离；数据与服务层（`DiaryRepository`、`SQLite`、`BackupService`、`ZipArchive`、`FootprintDataService` 等）显式标注 `nonisolated`，因为它们实际运行在串行队列或后台任务上

## 构建

- 部署目标：**iOS 27.0**
- 设备族：**iPhone + iPad**（`TARGETED_DEVICE_FAMILY = "1,2"`），可作为「Designed for iPad」在 Apple 芯片 Mac 上运行
- 项目由 `generate_project.py` 生成（PBXFileSystemSynchronizedRootGroup）——**所有构建设置都改这个脚本再重新生成**，不要手改 `project.pbxproj`。新增/删除文件后重新运行：

```bash
python3 generate_project.py
xcodebuild -project JustDiary.xcodeproj -scheme JustDiary -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

- 运行 UI 测试（覆盖导入、morph 动画、足迹页、编辑器冒烟、设置行可点击）：

```bash
xcodebuild -project JustDiary.xcodeproj -scheme JustDiary -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -parallel-testing-enabled NO test
```

## 开发辅助

- `tools/seed_sample_diary.py`：向模拟器写入一套可复现的示例日记（跨 3 年、4 个国家、
  5 类内容块），用于开发与截图验证：

```bash
python3 tools/seed_sample_diary.py "iPhone 18 Pro"
```

  脚本会同时按 App 的 `FtsSegment` 规则重建 FTS 索引，否则中文搜索查不到数据。
- 动画调试：启动参数 `-slow-morph`（或环境变量 `SLOW_MORPH=1`）把 morph 放慢到 3 秒；
  `-morph-log` 会把逐帧进度写进 `Documents/morph.log`。

## 资源再生成

- `generate_colorsets.py`：生成主题动态色 Asset Catalog 色板
- ⚠️ `generate_xcstrings.py` 已失效：它依赖的 `Resources/{en,zh-Hans}.lproj/Localizable.strings` 已不存在。现在 `Localizable.xcstrings` 是唯一真源，请直接编辑该文件。

## 版本说明

- iOS 27 / Xcode 27（Swift 6.4）适配方案见 `docs/iOS27-upgrade-plan.md`
- 首页动画性能与系统显示设置适配见 `docs/animation-and-accessibility.md`
- 升级调研（含 Apple 官方文档引用）见 `docs/research/`
