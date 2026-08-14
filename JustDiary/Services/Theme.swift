import SwiftUI

struct Theme {
    static let seed = Color(hex: 0x2563EB)

    static func primary() -> Color { seed }

    static func onPrimary() -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x191C20) : .white })
    }

    static func primaryContainer() -> Color { Color("primaryContainer") }

    static func glowColor() -> Color { seed.opacity(0.15) }

    static func flowLightColor() -> Color { seed.opacity(0.40) }

    static func flowMaskColor() -> Color { seed.opacity(0.05) }

    static func primaryUIColor() -> UIColor {
        UIColor { trait in seed.resolved(rgb: trait) }
    }

    static func primaryContainerUIColor() -> UIColor {
        UIColor(named: "primaryContainer") ?? .systemFill
    }

    // MARK: - Asset catalog tokens

    static func bg() -> Color { Color("bg") }
    static func onSurface() -> Color { Color("onSurface") }
    static func onSurfaceVariant() -> Color { Color("onSurfaceVariant") }
    static func outlineVariant() -> Color { Color("outlineVariant") }
    static func glassDim() -> Color { Color("glassDim") }
    static func glassBorder() -> Color { Color("glassBorder") }
    static func flowLight() -> Color { Color("flowLight") }
    static func blobA() -> Color { Color("blobA") }
    static func blobB() -> Color { Color("blobB") }
    static func blobC() -> Color { Color("blobC") }
    static func shadowColor() -> Color { Color("shadowColor") }

    static func onSurfaceUIColor() -> UIColor { UIColor(named: "onSurface") ?? .label }
    static func onSurfaceVariantUIColor() -> UIColor { UIColor(named: "onSurfaceVariant") ?? .secondaryLabel }
    static func quoteBgUIColor() -> UIColor { UIColor(named: "quoteBg") ?? .secondarySystemFill }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        let a = Double((hex >> 24) & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a == 0 ? 1 : a)
    }

    func resolved(rgb trait: UITraitCollection) -> UIColor {
        UIColor(self).resolvedColor(with: trait)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        let a = CGFloat((hex >> 24) & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: a == 0 ? 1 : a)
    }
}
