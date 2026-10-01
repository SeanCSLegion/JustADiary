import SwiftUI

/// 日记页的导航目的地：一天一条路由。
///
/// `dayKey == nil` 表示「今天」。日记页用**推进**（push）而不是弹出的 cover：
/// 日历 → 某一天是天然的层级关系，Apple 自己的「备忘录」也是这样 ——
/// 从右往左进入、可以右滑返回。
struct DiaryRoute: Hashable {
    var dayKey: String?
}

@Observable
final class AppState {
    var activeTab: AppTab = .home
    /// 日记页的导航栈；空 = 停在日历上。
    ///
    /// 它同时表达了「日记页开着没有」：以前是两个字段（`presentEditor` + `editorDayKey`），
    /// 与 cover 的 isPresented 绑定对不上时会出现「开着但不知道是哪一天」。
    var diaryPath: [DiaryRoute] = []
    /// 「设置变了」的计数器，由 `.uiTickChanged` 递增（见 `RootView.treeIdentity`）。
    ///
    /// 它的作用只是让 `RootView` 重新求值一次 body —— 语言 / 主题就在那一刻进到 identity
    /// 里、整棵树才会重建；**其余设置项不换 identity**，各页刷新自己那份设置就够了。
    /// UI 测试的 `-ui-test-state` 探针也读它，用来确认通知确实发出去了。
    var uiTick = 0

    /// 打开某一天的日记页（`dayKey == nil` = 今天）。
    func openDiary(dayKey: String?) {
        diaryPath = [DiaryRoute(dayKey: dayKey)]
    }
}
