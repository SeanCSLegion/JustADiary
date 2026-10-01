# 位置的记录规则

日期：2026-09-16 · 环境：Xcode 27 / iOS 27 SDK · 设备：iPhone 18 Pro 模拟器（iOS 27.0）
（2026-10-01 增补第五、六、七节：分享精度、与 Apple 权限对齐、记忆精度）

自动定位（设置 › 自动插入地点）只在**新建片段**时生效一次。这条规则同时决定了
保存提示、编辑态的位置胶囊，以及和「允许修改 / 删除历史日记」的关系；改动其中
任何一处时请一起考虑。

---

## 一、规则

| 场景 | 行为 |
|---|---|
| 新建片段 | 打开编辑器时获取一次；胶囊显示「位置获取中…」，失败后变成「重新获取位置」 |
| 新建片段保存时还没有位置 | **二次确认**（未获取到位置 → 取消 / 仍然保存）；确认后按无位置保存，**此后无法再添加** |
| 编辑已有片段（今天的或历史的） | **不重新获取**。显示该片段记录的位置，只允许调整精度 |
| 编辑一个没有位置的片段 | 显示只读的「未记录地点」，不提供任何获取入口 |
| 允许修改 / 删除历史日记 | 只决定「能不能编辑」；编辑时与今天的片段走同一套规则（可调精度、不可获取） |

（2026-10-01 核实：表里与「没有位置」有关的三行（新建片段、新建片段保存、编辑一个
没有位置的片段）都以设置项「自动插入地点」（`autoLoc`）为前置 —— 关掉它时新建片段
既不获取位置、保存时也不再二次确认，编辑一个没有位置的片段连「未记录地点」这一行
都不显示。）

## 二、为什么

- 位置是「写这条日记时人在哪」，属于当时的事实。事后重新获取会把它悄悄改成
  「现在在哪」，而这条日记的时间戳还是过去。
- 允许保存后再补位置，等于让两个不同时刻的位置混在同一条记录里，足迹页的
  国家 / 省份 / 城市聚合也会跟着漂移。
- 因此：**获取一次并落库**，之后只能调整**显示精度**——精度只改 `loc_text` 与
  `loc_precision`，不动经纬度与地区列，足迹聚合不受影响。
- 与之配套，编辑态不再提供「重新获取位置」入口。此前编辑今天的片段时胶囊会显示
  「未获取到位置」并允许重新获取，但保存路径 (`updateBlockContent`) 根本不写位置列，
  重新获取的结果被静默丢弃——这正是要修掉的 bug。

## 三、实现要点

- **精度调整要有地址可算**。片段只存 `country` / `region1…3` / `loc_text`，
  不存地点名与街道；编辑态因此用 `LocationResolver.text(for:precision:)` 的
  **`LocRegion` 重载**（`Services/LocationService.swift:306`；另一个同标签的重载收
  `CLPlacemark`，:259，只在记录时那一次用）从这些列重建地址，
  并只提供它们能表达的级别（省 / 市 / 区县）加上**记录时的那个
  级别**（`exact` / `street` 的完整文本只存在于 `loc_text` 里）。回到记录级别时
  原样恢复该文本（`LocationSnapshot.recordedPrecision` / `recordedText`），
  不会因为一次来回就丢掉地点名。
- **保存路径**：新建走 `addBlock` / `addBlockToDiary`（写位置列）；编辑走
  `updateBlockContent(blockId:contentJson:locText:locPrecision:)`，只写
  `loc_text` / `loc_precision`。
- **「没有位置」的判定**：拿到坐标但反向地理编码为空，同样按没有位置处理，
  否则会存下一条有坐标、没有地名、且再也补不上的记录。
- **编辑态的位置来自片段本身**：`enterEditBlock` 用
  `DiaryViewModel.locationSnapshot(from:)` 从库里的列重建，不再从 `nil` 开始
  （此前编辑一个**有**位置的片段，胶囊会错显为「未获取到位置」）。
- **新建时清空上一条的位置**：`enterWrite()` 显式 `location = nil`，否则上一个
  片段的位置会被带进新片段并一起落库。
- **地址文案去重**：MapKit 常把地点名与街道都报成同一个字符串
  （「深南大道, 深南大道」），`LocationResolver.text` 现在保留一个。

## 四、测试

`JustDiaryUITests/EditorTypeSizeUITests`：

- `testEntrySavedWithoutLocationCannotGainOne`：无位置保存 → 出现二次确认 → 确认后
  重新打开该片段 → 只读「未记录地点」、没有精度菜单、也没有「重新获取位置」。
- 其余的编辑器用例带 `-ui-test-no-autoloc`，与模拟器的位置状态无关。

测试钩子（同 `-ui-test-reset-*` 一类的约定）：

- `-ui-test-no-location`：让 `LocationService.currentLocation()` 直接返回 `nil`，
  从而稳定进入「获取失败」分支；
- `-ui-test-no-autoloc`：把 `autoLoc` 置为关闭，给不关心位置的用例使用。

（2026-10-01 核实：两个开关都不在 `Services/LaunchIntent.swift`（那里只负责 `openEditor`
的跳转意图）——`-ui-test-no-location` 在 `LocationService.currentLocation()` 开头判断，
`-ui-test-no-autoloc` 在 `App/JustDiaryApp.swift` 的 `AppDelegate` 里写 `autoLoc = false`。）

---

## 五、分享：地点只从地区列重建（2026-10-01）

此前分享长图直接把 `edit_block.loc_text` 抄进去 —— 记录时是什么精度，分享出去就是
什么精度：在写字楼下写的一条日记，分享图上是「腾讯滨海大厦, 深南大道 · 南山区 · …」。

现在这条路径走 `LocationResolver.shareText(recorded:region:cap:)`
（`DiaryViewModel.shareDiary()` → `ShareBlock.capped(_:cap:)`），规则三条：

1. **`loc_text` 不是输入**。分享文案只用 `country` / `region1…3` 重建，所以地点名与
   街道在分享这条路径上根本不存在。这一条比「看精度标签」更强：早期版本、以及地区列
   还没回填的记录，`loc_text` 里可能带着地点名，而 `loc_precision` 只标到 `province`，
   只信标签迟早会漏（`DiaryRepository.migrateLocationMeta` 就是这么标的）。
2. **上限只到区县**。设置项「分享位置精度」（`share_loc_precision`）只有
   **隐藏 / 区县 / 城市 / 省份** 四个值，默认**区县**；`LocPrecision.shareable` 里没有
   `exact` / `street`，`AppSettings.normalize()`（导入备份的入口）与 `shareText`
   （渲染前的最后一道）各夹一次，比区县更细或不在梯子上的值一律按区县处理。
3. **只能更粗，不能更细**：实际级别 = `min(记录精度, 上限)`。地区列重建为空
   （早年记录、或这行本来就没有地点）时**不显示地点**，而不是退回原文。

分享图上没有别的出口：头部第二行只有时间（`metaLine`），文件名只带 `day_key`。

## 六、记录精度与 Apple 的定位权限对齐（2026-10-01）

Apple 的定位权限是**两档**的：`authorizationStatus`（有没有授权）与
`accuracyAuthorization`（精确位置 / 模糊位置）。此前只看了「是不是 `fullAccuracy`」：

- 给了精确位置就无条件写 `exact` —— 一个误差 3km 的坐标也会被标成「精确地点」；
- 只给模糊位置时，默认记 `province`，菜单里却摆着 `city` / `district` —— **菜单比
  权限更细**，用户选了个系统根本给不出的级别。

现在上限由 `LocationResolver.maxPrecision(accuracyAuthorization:horizontalAccuracy:)`
一次算清（纯函数，`LocationPrecisionTests` 逐格测）：

| 系统给的 | 上限 | 依据 |
|---|---|---|
| 模糊位置（`reducedAccuracy`） | 城市 | SDK 对 `CLAccuracyAuthorizationReducedAccuracy` 的说明：坐标被吸附到「设备所在区域」的代表点、`horizontalAccuracy` 约 5km、两次定位可能隔 20 分钟 —— 区县已经不可信 |
| 精确位置 + `horizontalAccuracy` ≤ 10m | 精确地点 | 十米级才指得到某一栋楼 |
| ≤ 100m | 街道 | |
| ≤ 1000m | 区县 | |
| ≤ 5000m | 城市 | |
| 更粗、或负值（Apple：坐标无效） | 省份 | 只有省界还站得住 |

配套的三处：

- **上限随快照一起走**：`LocationResolver.snapshot(location:placemark:preferred:accuracyAuthorization:)`
  是纯计算（反向地理编码留在 `resolve` 里），算出的 `LocationSnapshot.maxPrecision` 就是
  编辑器菜单的上限。这个字段**故意没有默认值** —— 它第一次写出来时 `resolve` 漏传了，
  于是「已经给了精确位置，菜单里却只剩省份」；
- **新建片段的精度菜单**只给不粗于上限的级别（`availablePrecisions(maxPrecision:)`），
  已有片段不受影响 —— 那条地点早就存在库里、阅读页也照常显示，菜单只决定按哪一级显示；
- **模糊位置下的升级入口**：胶囊菜单里多一项「使用精确位置…」
  （`DiaryViewModel.requestFullAccuracyAndRelocate()`），走 Apple 的
  `requestTemporaryFullAccuracyAuthorization(withPurposeKey:)`，用途键
  `JustDiaryPreciseLocation` 写在 `Info.plist` 的
  `NSLocationTemporaryUsageDescriptionDictionary`（英文在
  `en.lproj/InfoPlist.strings`，键就是用途键本身）。没接 iOS 18 的
  `CLServiceSession`：那需要在整个定位期间持有一个 session，而这里只是用户点一下、
  拿一次定位。只对新片段开放，与「重新获取位置」同一条件；
- **无效坐标不再入库**：`horizontalAccuracy < 0` 的定位（Apple 说这种点的经纬度无效）
  会被 `LocationService.currentLocation()` 跳过，继续等下一个有效解。

## 七、上一次手动选的精度会被记住（2026-10-01）

此前 `applyPrecision` 只改当前这条快照：手动从「精确地点」调到「省份」后，下一条新日记
又回到「权限能给多细就给多细」，每次写日记都得重选一遍。

现在它同时写进 `AppSettings.defaultLocPrecision`（键 `default_loc_precision`，
默认 `auto` = 跟随权限），新片段解析定位时用
`LocationResolver.effective(precision:cap:)` 取 `min(记住的值, 权限上限)`：

- 记住的级别**只会让记录更粗**，永远不会顶穿 Apple 当前权限算出来的上限；
- 编辑历史片段时改精度同样会被记住（那是用户最近一次表达过的偏好）；
- 取值只能是梯子上的级别或 `auto`，`normalize()` 会把坏值收回 `auto`。

## 八、测试

- `JustDiaryTests/LocationPrecisionTests`：权限 × 精度的上限梯子、菜单不会给出比上限更细的
  级别、`effective` 只降不升、`shareText` 与 `ShareBlock.capped` 不含地点名 / 街道
  （含「上限被写成 exact」这种误用）、隐藏时为空、地区列为空时不退回原文。
- `JustDiaryTests/SettingsTests`：两个新设置项的默认值、旧备份（缺键）仍能整份解码、
  导入的 `exact` / `street` 会被收到区县、`none`（隐藏）不会被误收。
- `JustDiaryUITests/ShareLocationPrecisionUITests`：设置里那一项只有
  隐藏 / 区县 / 城市 / 省份，菜单里没有「精确地点」「街道」，选择跨重启保留。
- `JustDiaryUITests/LocationPrecisionMenuUITests`：**端到端**那一格 —— 模拟器给了精确位置
  与一个坐标时，编辑器的菜单必须给得出完整梯子（没有定位就跳过；跑之前先
  `simctl privacy … grant location` + `simctl location … set`）。
