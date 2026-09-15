import SwiftUI
import UIKit

// MARK: - Corner radius scale
//
// Before this existed the app used ten unrelated radii (1, 4, 8, 12, 16, 18,
// 20, 22, 26, 28) chosen per call site, so two cards sitting next to each other
// could differ by 2pt for no reason. Everything now comes from the small scale
// below, and nested surfaces use `concentric(outer:inset:)`, which is Apple's
// rule for rounded shapes inside rounded shapes: the inner radius is the outer
// radius minus the inset. Matching radii instead of subtracting produces the
// "pinched corner" look on the inner shape.
enum Radius {
    /// Content cards, list rows, hero panels.
    static let card: CGFloat = 20
    /// Floating control surfaces: the editor toolbar, sheets, popovers.
    static let panel: CGFloat = 26
    /// Inputs and inset sub-surfaces: search containers, the highlighted
    /// location row, the settings busy card.
    static let field: CGFloat = 14
    /// Inline images inside a card.
    static let image: CGFloat = 14
    /// Icon badges and small tinted squares.
    static let badge: CGFloat = 12
    /// Chart bars and other thick strokes.
    static let bar: CGFloat = 4
    /// 2pt-tall marks such as the "has a diary" underline in the calendar.
    static let hairline: CGFloat = 1

    /// Radius for a surface inset by `inset` inside a surface of radius `outer`.
    static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, outer - inset)
    }
}

// MARK: - Spacing scale
//
// Only the values that were already repeated across screens; this is not an
// attempt to re-space the app, just to stop the same layout from drifting.
enum Spacing {
    /// Screen gutter used by every tab.
    static let screen: CGFloat = 16
    /// Padding inside a content card.
    static let card: CGFloat = 12
    /// Vertical gap between stacked cards.
    static let cardGap: CGFloat = 12
    /// Gap between a card's icon badge and its text.
    static let rowIcon: CGFloat = 12
    /// Gap between chips.
    static let chip: CGFloat = 8
    /// Apple's minimum hit target.
    static let hitTarget: CGFloat = 44
}

// MARK: - Type scale
//
// Named roles for the sizes this app actually uses, so the same semantic slot
// stops being 11pt on one screen and 13pt on another. The numeric values match
// Apple's type ladder (34 / 28 / 22 / 20 / 17 / 16 / 15 / 13 / 12 / 11), which
// is what makes `DynamicTypeMetrics` able to scale each role on Apple's own
// curve for that style.
enum TypeSize {
    /// Home calendar month/year title.
    static let display: CGFloat = 32
    /// Page title in `PageHeader`.
    static let pageTitle: CGFloat = 24
    /// Sheet title.
    static let sheetTitle: CGFloat = 17
    /// Card headline such as the read-view date.
    static let cardTitle: CGFloat = 20
    /// Title inside a compact header capsule (the home calendar's year/month).
    static let headerTitle: CGFloat = 18
    /// Emphasised number in the footprint statistics row.
    static let statValue: CGFloat = 18
    /// Primary text of a list row or settings row.
    static let rowTitle: CGFloat = 15
    /// Explanatory second line of a settings/list row. Was 11pt on several
    /// screens, which is below Apple's caption floor for copy the user is
    /// expected to read.
    static let rowSub: CGFloat = 13
    /// Trailing value of a settings row.
    static let rowValue: CGFloat = 15
    /// Section header inside a card.
    static let sectionTitle: CGFloat = 13
    /// Chip / capsule label.
    static let chip: CGFloat = 14
    /// Count badge label.
    static let badge: CGFloat = 12
    /// Timestamps and location lines under a card title.
    static let meta: CGFloat = 13
    /// Least important supporting text.
    static let caption: CGFloat = 12
}

// MARK: - Dynamic Type
//
// `Font.system(size:)` is a fixed size and ignores 设置 › 显示与亮度 › 文字大小,
// which is why the app shipped for a while with a text-size setting that did
// nothing. A single global multiplier was the first fix, but it grew a 32pt
// calendar title and an 11pt caption by the same factor, which is not what
// Apple does: each text style has its own curve, and large styles grow
// proportionally far less than small ones.
//
// `DynamicTypeMetrics` therefore resolves each design size through
// `UIFontMetrics` for the matching text style, then clamps the result with a
// per-style ceiling.
//
// The ceiling is a deliberate deviation. Apple's uncapped curve takes body from
// 17pt to ~53pt at AX5, and no amount of reflow fits that into a 7-column
// calendar canvas, a 5-up statistics row, or a horizontal chip bar. Growth is
// capped highest for the styles that most need it (small supporting text) and
// lowest for the styles that are already large, which preserves Apple's shape
// while keeping every screen usable.
enum DynamicTypeMetrics {
    /// Upper bound on growth, keyed by text style.
    ///
    /// Apple's curve takes body from 17pt to ~53pt at AX5 and, at the same time,
    /// grows it *faster* than the title styles. Applied to this app's sizes that
    /// inverts the hierarchy: a 15pt paragraph would end up larger than a 22pt
    /// heading, so a diary entry would lose its structure exactly when the user
    /// most needs to read it. The ceilings below keep the whole ladder monotonic
    /// — each step stays clearly above the one below it — while still letting
    /// supporting text grow more than display text.
    ///
    /// Result at AX5 for the sizes this app uses:
    /// 32 → 44.8, 24 → 34.8, 20 → 29, 18 → 27, 16 → 24.8, 15 → 24, 13 → 21.5,
    /// 12 → 20.4, 11 → 19.3.
    static func ceiling(for style: UIFont.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 1.35
        case .title1: return 1.40
        case .title2, .title3: return 1.45
        case .body: return 1.50
        case .callout: return 1.55
        case .subheadline: return 1.60
        case .footnote: return 1.65
        case .caption1: return 1.70
        default: return 1.75
        }
    }

    /// The Apple text style whose default size is closest to `size`.
    ///
    /// Matching by nearest default size means the design stays at its intended
    /// size in the default category (every metric returns exactly `size`) and
    /// only the *growth* differs between roles.
    static func textStyle(for size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case 34...: return .largeTitle
        case 28..<34: return .title1
        case 22..<28: return .title2
        case 20..<22: return .title3
        case 17..<20: return .body
        case 16..<17: return .callout
        case 15..<16: return .subheadline
        case 13..<15: return .footnote
        case 12..<13: return .caption1
        default: return .caption2
        }
    }

    private static let lock = NSLock()
    private static var traitCache: [String: UITraitCollection] = [:]

    static func category(for size: DynamicTypeSize) -> UIContentSizeCategory {
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

    private static func traits(for size: DynamicTypeSize) -> UITraitCollection {
        let key = category(for: size).rawValue
        lock.lock()
        defer { lock.unlock() }
        if let cached = traitCache[key] { return cached }
        let traits = UITraitCollection(preferredContentSizeCategory: category(for: size))
        traitCache[key] = traits
        return traits
    }

    /// Multiplier the current content-size category applies to `size`.
    static func multiplier(for size: CGFloat, typeSize: DynamicTypeSize) -> CGFloat {
        guard typeSize != .large else { return 1 }
        let style = textStyle(for: size)
        let scaled = UIFontMetrics(forTextStyle: style).scaledValue(for: size, compatibleWith: traits(for: typeSize))
        let raw = scaled / max(size, 0.01)
        return min(ceiling(for: style), max(1, raw))
    }

    /// A design size resolved for the current content-size category.
    static func scaled(_ size: CGFloat, for typeSize: DynamicTypeSize) -> CGFloat {
        size * multiplier(for: size, typeSize: typeSize)
    }

    /// A design size resolved for the current content-size category, as a UIKit
    /// font. Used by the attributed-text pipeline (`PartsCodec`), which builds
    /// `NSAttributedString`s outside SwiftUI and so cannot use `.diaryFont`.
    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular,
                     typeSize: DynamicTypeSize) -> UIFont {
        UIFont.systemFont(ofSize: scaled(size, for: typeSize), weight: weight)
    }

    /// Damped multiplier for the calendar's Canvas-drawn day grid.
    ///
    /// The grid's cell size is fixed by the screen, so the day numbers cannot
    /// follow the full curve without leaving their cells. Half the body
    /// multiplier keeps the drawn text in step with the surrounding UI while
    /// staying inside the cells.
    static func calendarMultiplier(for typeSize: DynamicTypeSize) -> CGFloat {
        1 + (multiplier(for: 15, typeSize: typeSize) - 1) * 0.5
    }
}
