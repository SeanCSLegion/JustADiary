import SwiftUI

@Observable
final class AppState {
    var activeTab: AppTab = .home
    var presentEditor = false
    var editorDayKey: String?
    var uiTick = 0
}
