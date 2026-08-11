# 一页时光（JustADiary）

基于 SwiftUI 的日记软件（iOS 26+），原为 HarmonyOS 应用迁移而来。

## 功能

- **首页日历**：月历/年历查看，支持镜头缩放切换动画、今日圆环/选中实心圆标识、日记日期圆点标注
- **日记编辑**：富文本编辑器（标题、引用、列表、待办、粗体/斜体/删除线/下划线、居中对齐），支持插入图片、自动记录时间与位置
- **地图足迹**：全球/全国/全省三级地图（自绘 GeoJSON），按国家/省市热力统计，支持筛选年份
- **搜索**：全文搜索 + 时间/地点筛选，关键词高亮
- **设置**：语言（中/英）、主题（浅/深/跟随系统）、日记开始时间、周起始、自动定位、提醒、历史编辑、备份导入导出

## 设计

- 全面采用 iOS 26 **Liquid Glass** 设计语言：原生 `glassEffect`、`.glass`/`.glassProminent` 按钮样式、系统背景色卡片、玻璃搜索框与分段控件
- 卡片使用系统推荐底色（浅色纯白 / 深色 `secondarySystemGroupedBackground`），无主题色污染
- 自定义组件：`GlassChip`（筛选胶囊）、`PressableGlassIcon`（圆形玻璃图标按钮）、`diaryGlassCard`（玻璃卡片修饰符）

## 构建

- 部署目标：iOS 26.0
- 项目由 `generate_project.py` 生成（PBXFileSystemSynchronizedRootGroup），新增/删除文件后重新运行：

```bash
python3 generate_project.py
xcodebuild -project JustDiary.xcodeproj -scheme JustDiary -destination 'platform=iOS Simulator,name=iPhone 17' build
```

- 运行 UI 测试：

```bash
xcodebuild -project JustDiary.xcodeproj -scheme JustDiary -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## 目录结构

```
JustDiary/
├── App/           # 入口、AppDelegate
├── Views/         # 首页 / 日记页 / 地图 / 搜索 / 设置
├── Services/      # 主题、定位、提醒、备份、地图数据
├── Data/          # SQLite、日记仓库
├── Models/        # 数据模型、日期工具
└── Resources/     # 本地化、地图 GeoJSON、图标
```
