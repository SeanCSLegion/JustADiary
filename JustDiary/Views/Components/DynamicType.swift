import SwiftUI
import UIKit

// MARK: - Dynamic Type plumbing
//
// The design specifies explicit point sizes everywhere, and `Font.system(size:)`
// is a *fixed* size: it does not grow when the user raises the system text size.
// That made the app completely ignore
// 设置 › 显示与亮度 › 文字大小 and 辅助功能 › 更大字体.
//
// `RootView` publishes the user's `DynamicTypeSize` through the environment;
// `DynamicTypeMetrics` (see DesignSystem.swift) turns a design size into the
// size that should actually be drawn, using Apple's per-text-style metrics. At
// the default category every design size is returned unchanged, so the design
// is untouched there.

private struct DiaryDynamicTypeSizeKey: EnvironmentKey {
    static let defaultValue: DynamicTypeSize = .large
}

extension EnvironmentValues {
    /// The user's preferred content size category, as published by `RootView`.
    var diaryDynamicTypeSize: DynamicTypeSize {
        get { self[DiaryDynamicTypeSizeKey.self] }
        set { self[DiaryDynamicTypeSizeKey.self] = newValue }
    }
}

private struct DiaryFont: ViewModifier {
    @Environment(\.diaryDynamicTypeSize) private var typeSize
    var size: CGFloat
    var weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(.system(size: DynamicTypeMetrics.scaled(size, for: typeSize), weight: weight))
    }
}

private struct DiaryDampedFont: ViewModifier {
    @Environment(\.diaryDynamicTypeSize) private var typeSize
    var size: CGFloat
    var weight: Font.Weight

    func body(content: Content) -> some View {
        let damped = size * DynamicTypeMetrics.calendarMultiplier(for: typeSize)
        content.font(.system(size: damped, weight: weight))
    }
}

extension View {
    /// `Font.system(size:)` at `size`, resolved for the user's text-size setting.
    func diaryFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(DiaryFont(size: size, weight: weight))
    }

    /// Like `.diaryFont`, but grown at half rate.
    ///
    /// Used by the calendar chrome that sits in a fixed-height strip (the
    /// weekday header): the strip's height is part of the grid's layout math,
    /// so this text follows the user's setting without outgrowing its row.
    func diaryCalendarFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(DiaryDampedFont(size: size, weight: weight))
    }
}

extension UIFont {
    /// UIKit counterpart of `.diaryFont(_:weight:)` for code that builds fonts
    /// outside a SwiftUI view body.
    static func diary(_ size: CGFloat, weight: UIFont.Weight = .regular,
                      typeSize: DynamicTypeSize) -> UIFont {
        DynamicTypeMetrics.font(size, weight: weight, typeSize: typeSize)
    }
}
