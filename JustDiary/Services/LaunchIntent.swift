import Foundation

enum LaunchIntent {
    static var target: String = "home"
    static var dayKey: String = ""

    static func openEditor(dayKey: String? = nil) {
        target = "editor"
        self.dayKey = dayKey ?? ""
    }

    static func clear() {
        target = "home"
        dayKey = ""
    }
}
