# 首页动画性能与系统显示设置适配

日期：2026-09-15 · 环境：Xcode 27 / iOS 27 SDK · 设备：iPhone 18 Pro 模拟器（iOS 27.0）

## 一、年视图 ↔ 月视图 morph 动画

### 1.1 排查方法

项目里本来就有 `-morph-log` 调试开关（`MorphProgressLog`）。我把它扩展到年↔月 morph
并在 `HomeView` 的四个关键点打了标记，然后用 UI 测试（`MorphPerfUITests`）自动驱动
「月→年」和「年→月」两次切换，再用脚本从 `morph.log` 算逐帧间隔。

命令：`python3 generate_project.py && xcodebuild ... -only-testing:JustDiaryUITests/MorphPerfUITests test`

### 1.2 找到的两个真问题

**问题 1：morph 期间三个底层视图仍在每帧重建（真正造成掉帧的原因）**

`HomeView.calendarArea` 用 `ZStack` 叠了 `yearLayer` / `monthLayer` / `weekLayer`，
morph 时靠 `.opacity(0)` 隐藏。但**透明度为 0 的视图依然会被构建、依然会在每个动画帧
重新求值**。而每个 layer 里面是 `DragPagePager`，它会**一次性构建上一页/当前页/下一页**：

| layer | 每帧实际渲染的 Canvas 数 |
|---|---|
| `yearLayer` = 3 页 × `YearPageView` × 12 个月 | **36** |
| `monthLayer` = 3 × `MonthCanvas` | 3 |
| `weekLayer` = 3 × `WeekRowCanvas` | 3 |
| morph 视图本身（再画一整份 `YearPageView` + 一个 `MonthCanvas`） | 13 |
| **合计** | **55** |

也就是说：**屏幕上只有 13 个 canvas 可见，却每帧渲染 55 个。**

修复：
- morph 期间不再构建底层 layer；
- `DragPagePager` 在 `disabled`（正是 morph 期间）时不再构建邻页——禁用的分页器本来就
  不能滚动，邻页只是被拖出来时才需要。

> 2026-09 月视图改成**连续月历流**（`MonthFlowView`）之后的现状：
> - `yearLayer`（36 张迷你月）只在 `mode == .year` 时构建 —— 月/周态下整层不存在，
>   比原来「常驻 + opacity 0」更省；
> - `weekLayer` 同理，只在 `mode == .week` 时构建；
> - 月视图（连续月历流）**始终挂载**：它的滚动位置是状态，卸载就丢，月↔周 morph
>   收尾要回到按下那一行原来的位置。它一帧只画视口内可见的 2–3 个月（十几个
>   `WeekRowCanvas`），且 morph 期间输入不变、body 不会被重新求值，代价可以忽略。

**问题 2：年↔月用的是 `easeInOut`，起步半拍慢（"感觉慢"的原因）**

月↔周切换用的是 `timingCurve(0.2, 0.75, 0.3, 1.0)`——起步带速度、尾部减速；
而年↔月用的是 `easeInOut`，从零速度起步。实测两者同为 0.6s 时长，但：

| 曲线 | 时间过 25% 时完成的进度 |
|---|---|
| `easeInOut`（原来，年↔月） | **约 13%** |
| `timingCurve(0.2,0.75,0.3,1.0)`（月↔周） | 约 65% |

这就是"对比月↔周切换感觉慢"的直接原因。修复：年↔月改用与月↔周**同一条曲线**，两者节奏一致。

### 1.3 顺带修正

`DayDraw` 的 `ResolvedText` 缓存上限只有 4000，超限直接 `removeAll()`。动画中字号每半磅
就产生一个新 key，缓存一旦在动画中途被清空，下一帧所有可见文字都要重新解析——那会表现为
明显掉帧。已把上限提到 24000 并保留注释说明。（实测该清空**并未**在本次动画中触发，
所以它不是本次卡顿的原因，但属于应修的正确性问题。）另外顺带修了 `HomeView` 里
`MonthCanvas` 的 a11y 标签也含「年」导致 UI 测试点错元素的问题，并给年份页的 12 个月份
补上了可访问性（此前只挂在 tap 手势上，VoiceOver 完全看不到）。

### 1.4 优化前后实测

| 指标 | 优化前 | 优化后 |
|---|---|---|
| 平均帧率 | 56–57 fps | **58 fps** |
| p90 帧间隔 | **26.6 ms**（已掉帧） | **16.9–17.0 ms**（满帧） |
| 最大帧间隔 | **51.7 ms** | 33–40 ms |
| >25ms 卡顿帧 | 6 次（两次各 4/2） | **4 次**（两次各 2） |
| 时间过 25% 的进度 | 13% | **65%**（与月↔周一致） |

剩余 2 次卡顿主要是动画**首帧**（首次构建 morph 视图）与一次中段帧；模拟器渲染本来就比
真机慢，且模拟器封顶 60fps，真机 ProMotion 会明显更顺。用户也提到"可能是模拟器的缘故"，
这一点与实测一致。

> 另有 `-slow-morph` / `SLOW_MORPH=1` 调试开关可把 morph 放慢到 3 秒便于肉眼观察。

## 二、系统「显示与亮度 / 辅助功能」设置的适配

### 2.1 排查结论

| 系统设置 | 适配前 | 现在 |
|---|---|---|
| 浅色 / 深色 | ✅ 已支持（`preferredColorScheme` + Asset 动态色） | 不变 |
| 跟随系统语言 | ✅ 已支持 | 不变 |
| **文字大小（动态字体）** | ❌ **完全无效**——全项目 88 处 `.font(.system(size:))` 都是固定字号 | ✅ 已支持 |
| **减弱动态效果** | ❌ 未处理，morph 照常播放 | ✅ 已支持 |
| **增强对比度** | ❌ 未处理 | ✅ 已支持 |
| Liquid Glass 外观 | ✅ iOS 27 自动套用（未设 `UIDesignRequiresCompatibility`） | 不变 |

### 2.2 动态字体（Dynamic Type）

`Font.system(size:)` 是**固定字号**，不会随系统文字大小变化——这是"设置里调了字号但 App
没反应"的根因。

新增 `Views/Components/DynamicType.swift`：

- 用 Apple 自己的 `UIFontMetrics` 从 SwiftUI 的 `DynamicTypeSize` 算出缩放系数，
  通过 `\.diaryTypeScale` 环境值下发；
- 新增 `.diaryFont(_:weight:)` 修饰符替代 `.font(.system(size:))`，**把 87 处调用点全部转换**；
- 日历是用 `Canvas` 绘制的，SwiftUI 无法代劳，因此在 `MonthCanvas` / `WeekRowCanvas`
  里对 `DayMetrics` 的字号单独缩放——用的是**减半的系数**，因为日历格子尺寸由屏幕决定，
  全量放大反而会把日期数字挤出格子。

缩放上限设为 **1.45×**：再大日历网格、编辑器工具条、足迹页 5 列统计就会重叠裁切，
比不放大更糟。

实测：
- 默认字号（large）下截图与改动前**完全一致**（系数恰为 1）；
- 切到辅助功能最大字号后文字明显变大、设置行自动换行重排。

### 2.3 减弱动态效果（Reduce Motion）

- `HomeView`：morph 改用 `CalendarLayout.reducedMorphAnimation`（0.18s 线性），
  状态照常切换，但不再有横扫整个屏幕的位移；
- `FlowLightOverlay`（装饰性流光）在开启时直接暂停 `TimelineView`。

### 2.4 增强对比度（Increase Contrast）

`diaryCard` 改为通过 `@Environment(\.colorSchemeContrast)` 取状态，开启时描边加深加粗
（0.5pt/45% → 1.5pt/90% + 外描边），卡片分组边界更清晰。已截图验证。

### 2.5 Liquid Glass 系统外观

- 产物 Info.plist **没有** `UIDesignRequiresCompatibility`——该键在 iOS 27 SDK 构建下本来
  就会被忽略，App 自动获得新版 Liquid Glass 外观，无需改动；
- 系统「Liquid Glass 色调」滑块影响的是**系统材质**；App 自己用
  `.glassEffect(.regular.tint(Theme.primary()))` 和 `.buttonStyle(.glass)` 的**品牌色**
  是刻意固定的，不会跟着系统色调走，这是预期行为。

## 三、示例数据重建

原始日记数据无法恢复，排查过程与结论见提交说明。新增
`tools/seed_sample_diary.py` 用于重新生成一套可复现的示例数据：

```bash
python3 tools/seed_sample_diary.py "iPhone 18 Pro"
```

生成 16 天 / 17 个片段，覆盖 2024–2026 三年、中国（广东/北京/浙江/上海）、
日本、美国、法国，含标题 / 小标题 / 段落 / 引用 / 无序列表 / 待办 六类内容块，以及 3 条
**完全没有地点信息**的记录用来验证「未记录」计数。2026-09-08 那条是**字体自检**条目：
每个段落样式各一段，另有粗体 / 斜体 / 下划线 / 删除线和居中段落，用来核对
`content_json` 的 `runs` / `align` 与阅读端渲染（见 `docs/editor-typography.md`）。

脚本刻意复刻了 App 内部的 `FtsSegment.segment`（在相邻 CJK 字符间插空格）来写
`diary_fts`——FTS5 的 `unicode61` 分词器会把一整串中文当成**一个** token，不这样做搜索
将完全查不到（已实测确认）。
