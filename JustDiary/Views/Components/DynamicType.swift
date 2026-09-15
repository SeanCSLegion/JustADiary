import SwiftUI
import UIKit

// MARK: - Dynamic Type support
//
// The design specifies explicit point sizes everywhere, and `Font.system(size:)`
// is a *fixed* size: it does not grow when the user raises the system text size.
// That made the app completely ignore
// 设置 › 显示与亮度 › 文字大小 and 辅助功能 › 更大字体.
//
// A single scale factor is derived from SwiftUI's `DynamicTypeSize` using
// Apple's own metrics (`UIFontMetrics`), published through the environment, and
// applied by `diaryFont(_:weight:)` and by the calendar's Canvas drawing. At the
// default size the factor is exactly 1, so the design is unchanged.

private struct DiaryTypeScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// Multiplier applied to every explicit design font size.
    var diaryTypeScale: CGFloat {
        get { self[DiaryTypeScaleKey.self] }
        set { self[DiaryTypeScaleKey.self] = newValue }
    }
}

enum DynamicTypeScale {
    /// Upper bound on the multiplier.
    ///
    /// The calendar grid, the editor toolbar and the 5-up footprint stats row are
    /// space-constrained; past this point they clip and overlap, which is worse
    /// than not growing further. Content that reflows (settings rows, the
    /// footprint list) still gets readable text at this ceiling.
    static let maximum: CGFloat = 1.45

    /// The reference body point size Apple's metrics are normalised against.
    private static let referenceBodySize: CGFloat = 17

    /// Damped factor for Canvas-drawn calendar text.
    ///
    /// The calendar draws its day numbers into a `Canvas`, where SwiftUI cannot
    /// scale the text for us, and the grid's cell size is fixed by the space
    /// available. Growing the type by half the user's factor respects the setting
    /// without pushing numbers out of their cells.
    static func calendarFactor(for scale: CGFloat) -> CGFloat {
        1 + (scale - 1) * 0.5
    }

    static func value(for size: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: category(for: size))
        let scaled = UIFontMetrics.default.scaledValue(for: referenceBodySize, compatibleWith: traits)
        return min(maximum, max(1, scaled / referenceBodySize))
    }

    private static func category(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

private struct DiaryFont: ViewModifier {
    @Environment(\.diaryTypeScale) private var scale
    var size: CGFloat
    var weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight))
    }
}

extension View {
    /// `Font.system(size:)` at `size`, scaled by the user's text-size setting.
    func diaryFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(DiaryFont(size: size, weight: weight))
    }
}


