import UIKit

enum Haptics {
    private static let tapGenerator = UIImpactFeedbackGenerator(style: .light)

    static func tap() {
        tapGenerator.prepare()
        tapGenerator.impactOccurred()
    }
}
