import SwiftUI

struct Theme {
    static let seed = Color(hex: 0x2B5DB7)

    static func primary(_ trait: UITraitCollection? = nil) -> Color { seed }

    static func onPrimary(_ trait: UITraitCollection? = nil) -> Color {
        (trait?.userInterfaceStyle ?? .light) == .dark ? Color(hex: 0x191C20) : .white
    }

    static func primaryContainer(_ trait: UITraitCollection? = nil) -> Color {
        let isDark = (trait?.userInterfaceStyle ?? .light) == .dark
        return blend(seed, isDark ? Color(hex: 0x101318) : .white, 0.78)
    }

    static func onPrimaryContainer(_ trait: UITraitCollection? = nil) -> Color {
        let isDark = (trait?.userInterfaceStyle ?? .light) == .dark
        return isDark ? blend(seed, .white, 0.75) : darken(seed, 0.52)
    }

    static func primaryShadow() -> Color { seed.opacity(0.20) }

    static func flowLightColor() -> Color { seed.opacity(0.40) }

    static func glowColor() -> Color { seed.opacity(0.15) }

    static func flowMaskColor() -> Color { seed.opacity(0.05) }

    static func primaryUIColor() -> UIColor {
        UIColor { trait in seed.resolved(rgb: trait) }
    }

    static func glowUIColor() -> UIColor {
        UIColor(red: 0x2B/255, green: 0x5D/255, blue: 0xB7/255, alpha: 0.15)
    }

    static func primaryContainerUIColor() -> UIColor {
        UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let target = isDark ? UIColor(hex: 0x101318) : UIColor.white
            return blendUIColor(UIColor(hex: 0x2B5DB7), target, 0.78)
        }
    }

    // MARK: - Static tokens (light / dark)

    static func bg(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0xFAF9FD, dark: 0x101318, trait: trait)
    }

    static func surface1(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0xF1F4FA, dark: 0x1E222B, trait: trait)
    }

    static func surface2(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0xE9EDF6, dark: 0x262B36, trait: trait)
    }

    static func quoteBg(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0xE4EAF9, dark: 0x2B3344, trait: trait)
    }

    static func onSurface(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0x191C20, dark: 0xE1E2E8, trait: trait)
    }

    static func onSurfaceVariant(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0x44474F, dark: 0xC5C6D0, trait: trait)
    }

    static func outlineVariant(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0xC5C6D0, dark: 0x44474F, trait: trait)
    }

    static func glass(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0x9EFCFFFF, dark: 0x94304348, trait: trait)
    }

    static func glassStrong(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0xC9FFFFFF, dark: 0xCC20262F, trait: trait)
    }

    static func glassDim(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0x73FFFFFF, dark: 0x80262B36, trait: trait)
    }

    static func glassBorder(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0x8CFFFFFF, dark: 0x33FFFFFF, trait: trait)
    }

    static func flowLight(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0xCCFFFFFF, dark: 0x59FFFFFF, trait: trait)
    }

    static func blobA(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0x80AAC7FF, dark: 0x8000468F, trait: trait)
    }

    static func blobB(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0x99BAD8FF, dark: 0x8C264678, trait: trait)
    }

    static func blobC(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0x6EBBE9FF, dark: 0x6E264678, trait: trait)
    }

    static func imageScrim() -> Color { Color(hex: 0xCC000000) }

    static func shadowColor(_ trait: UITraitCollection? = nil) -> Color {
        dynamic(light: 0x14000000, dark: 0x26000000, trait: trait)
    }

    static func dynamic(light: UInt32, dark: UInt32, trait: UITraitCollection?) -> Color {
        guard let trait else {
            return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
        }
        return (trait.userInterfaceStyle == .dark) ? Color(hex: dark) : Color(hex: light)
    }

    static func blend(_ a: Color, _ b: Color, _ ratio: Double) -> Color {
        let ac = a.resolvedRGB()
        let bc = b.resolvedRGB()
        return Color(red: ac.r + (bc.r - ac.r) * ratio,
                     green: ac.g + (bc.g - ac.g) * ratio,
                     blue: ac.b + (bc.b - ac.b) * ratio)
    }

    static func darken(_ color: Color, _ ratio: Double) -> Color {
        let c = color.resolvedRGB()
        return Color(red: c.r * (1 - ratio), green: c.g * (1 - ratio), blue: c.b * (1 - ratio))
    }

    private static func blendUIColor(_ a: UIColor, _ b: UIColor, _ ratio: Double) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * CGFloat(ratio),
                       green: ag + (bg - ag) * CGFloat(ratio),
                       blue: ab + (bb - ab) * CGFloat(ratio),
                       alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        let a = Double((hex >> 24) & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a == 0 ? 1 : a)
    }

    func resolvedRGB() -> (r: Double, g: Double, b: Double) {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
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
