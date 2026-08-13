# 一页时光（JustADiary）

基于 SwiftUI 的日记软件（iOS 26+），原为 HarmonyOS 应用迁移而来。

## 功能

- **首页日历**：月历/年历查看，支持镜头缩放切换动画、今日圆环/选中实心圆标识、日记日期圆点标注
- **日记编辑**：富文本编辑器（标题、引用、列表、待办、粗体/斜体/删除线/下划线、居中对齐），支持插入图片、自动记录时间与位置
- **地图足迹**：全球/全国/全省三级地图（自绘 GeoJSON），按国家/省市热力统计，支持筛选年份
- **搜索**：全文搜索（SQLite FTS5 + CJK 分词）+ 时间/地点筛选，关键词高亮
- **设置**：语言（中/英，即时生效）、主题（浅/深/跟随系统）、日记开始时间、周起始、自动定位、提醒、历史编辑、备份导入导出

## 设计

- 全面采用 iOS 26 **Liquid Glass** 设计语言：原生 `glassEffect`、`.glass`/`.glassProminent` 按钮样式、系统背景色卡片、玻璃搜索框与分段控件
- 本地化使用 **String Catalog**（`Localizable.xcstrings`），通过 `String(localized:locale:)` 支持应用内语言即时切换
- 主题色板迁移至 **Asset Catalog** 动态色（明暗自动切换），品牌色/混合色仍由 `Theme` 计算
- 自定义组件：`GlassChip`、`GlassActionChip`、`GlassCountBadge`、`PressableGlassIcon`、`diaryGlassCard`（玻璃卡片修饰符）、`GlassEmptyState`、`AppAlertItem`

## 架构

```
JustDiary/
├── App/           # 入口、AppDelegate
├── Views/         # 首页 / 日记页 / 地图 / 搜索 / 设置（纯展示 + 交互）
│   └── Components/   # 共享玻璃组件、动画常量
├── ViewModels/    # @Observable ViewModel（Home/Diary/Map/Settings），数据层收敛于此
├── Services/      # 主题、定位（CLLocationUpdate.liveUpdates）、提醒、备份（Compression 框架 zip）、地图数据、媒体缓存
├── Data/          # SQLite（串行队列）、日记仓库
├── Models/        # 数据模型、日期工具
└── Resources/     # String Catalog、地图 GeoJSON、图标、动态色板
```

关键设计：
- `DiaryRepository` 所有数据库访问均在串行队列执行（`runOnQueue`）
- 备份/导入/分享渲染在后台任务执行；zip 采用标准格式（raw deflate + CRC32 校验）
- `ContentPartCache` 缓存 JSON 解析结果；`DiaryImageStore` 缓存降采样图片（ImageIO）
- `MapViewModel` 相机动画由 `TimelineView` 驱动（替代 Timer，自动释放）

## 构建

- 部署目标：iOS 26.0
- 项目由 `generate_project.py` 生成（PBXFileSystemSynchronizedRootGroup），新增/删除文件后重新运行：

```bash
python3 generate_project.py
xcodebuild -project JustDiary.xcodeproj -scheme JustDiary -destination 'platform=iOS Simulator,name=iPhone 17' build
```

- 运行 UI 测试（覆盖导入、morph 动画、地图/编辑器冒烟、设置行可点击）：

```bash
xcodebuild -project JustDiary.xcodeproj -scheme JustDiary -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test
```

## 资源再生成

- `generate_xcstrings.py`：由中英 `.strings` 生成 `Localizable.xcstrings`
- `generate_colorsets.py`：生成主题动态色 Asset Catalog 色板
