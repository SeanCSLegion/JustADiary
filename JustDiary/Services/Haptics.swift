import UIKit

enum Haptics {
    private static let tapGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)

    static func tap() {
        tapGenerator.prepare()
        tapGenerator.impactOccurred()
    }

    static func medium() {
        mediumGenerator.prepare()
        mediumGenerator.impactOccurred()
    }
}
