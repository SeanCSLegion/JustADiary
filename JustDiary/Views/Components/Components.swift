import SwiftUI
import UIKit

// MARK: - Animations

extension Animation {
    static let diaryQuick = Animation.easeOut(duration: 0.22)
    static let diaryStandard = Animation.easeInOut(duration: 0.3)
    static let diaryMorph = Animation.easeInOut(duration: 0.4)
    static let diarySpring = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

// MARK: - Screen metrics

enum Screen {
    static var size: CGSize {
        if Thread.isMainThread {
            return currentSize
        }
        return DispatchQueue.main.sync { currentSize }
    }

    /// Size of the scene the app is actually presenting in.
    ///
    /// This must not be a hard-coded device size: from iOS 27 the app is fully
    /// resizable (iPad windowing, iPhone Mirroring, and "Designed for iPad" on
    /// Mac), so a fixed fallback would silently lay out for the wrong size. The
    /// key window's bounds track resizing; the scene's screen is the next best
    /// source, and the final fallback only applies before any scene exists.
    private static var currentSize: CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let scene else { return CGSize(width: 390, height: 844) }
        if let window = scene.keyWindow { return window.bounds.size }
        return scene.screen.bounds.size
    }

    static var height: CGFloat { size.height }
    static var width: CGFloat { size.width }
}

// MARK: - Background

struct BlobBackground: View {
    var dense = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.bg()
                if dense {
                    Circle().fill(Theme.blobA()).frame(width: 300, height: 300)
                        .blur(radius: 70).position(x: -80, y: 200)
                    Circle().fill(Theme.blobB()).frame(width: 250, height: 250)
                        .blur(radius: 65).position(x: geo.size.width + 20, y: 560)
                    Circle().fill(Theme.blobC()).frame(width: 210, height: 210)
                        .blur(radius: 60).position(x: geo.size.width - 40, y: -30)
                } else {
                    Circle().fill(Theme.blobA()).frame(width: 280, height: 280)
                        .blur(radius: 60).position(x: -60, y: 220)
                    Circle().fill(Theme.blobB()).frame(width: 240, height: 240)
                        .blur(radius: 60).position(x: geo.size.width + 20, y: 640)
                    Circle().fill(Theme.blobC()).frame(width: 200, height: 200)
                        .blur(radius: 55).position(x: geo.size.width - 30, y: -10)
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

struct DiaryBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                BlobBackground()
                    .ignoresSafeArea()
            }
    }
}

extension View {
    func diaryBackground() -> some View {
        modifier(DiaryBackground())
    }
}

// MARK: - Glass primitives

func tintedGlass(_ tint: Color?, interactive: Bool = false) -> Glass {
    let g = tint.map { Glass.regular.tint($0) } ?? .regular
    return interactive ? g.interactive() : g
}

extension View {
    /// Content-area card surface.
    ///
    /// WWDC26 session 8120 advises against Liquid Glass in the content area:
    /// there is nothing behind it to refract, and a glass card reads as "a card
    /// sitting on glass". Liquid Glass is reserved here for the control layer
    /// that floats above content (chips, icon buttons, the search field, the
    /// share/primary buttons). Content cards therefore use the system grouped
    /// background with a hairline border and a soft shadow.
    func diaryCard(cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        modifier(DiaryCard(cornerRadius: cornerRadius, interactive: interactive))
    }
}

private struct DiaryCard: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    var cornerRadius: CGFloat
    var interactive: Bool

    func body(content: Content) -> some View {
        let increased = contrast == .increased
        return content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Theme.onSurface().opacity(increased ? 0.55 : 0.0), lineWidth: 1)
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(Theme.outlineVariant().opacity(increased ? 0.9 : 0.45),
                                        lineWidth: increased ? 1.5 : 0.5)
                        }
                }
                .shadow(color: Theme.shadowColor().opacity(interactive ? 0.22 : 0.14),
                        radius: interactive ? 12 : 8,
                        y: interactive ? 4 : 2)
        }
    }
}

// MARK: - Page header

struct PageHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .diaryFont(24, weight: .medium)
                .foregroundStyle(Theme.onSurface())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            trailing()
        }
        .frame(height: 52)
    }
}

// MARK: - Buttons

struct GlassPrimaryButton: View {
    var title: String
    var icon: String? = nil
    var fullWidth = false
    var compact = false
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .diaryFont(compact ? 12 : 13, weight: .semibold)
                }
                Text(title)
                    .diaryFont(compact ? 13 : 14, weight: .medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.55))
            .padding(.horizontal, compact ? 14 : 20)
            .padding(.vertical, compact ? 7 : 12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if enabled {
                Capsule()
                    .fill(Theme.primary())
                    .glassEffect(.regular.tint(Theme.primary()).interactive(true), in: Capsule())
                    .shadow(color: Theme.glowColor(), radius: compact ? 8 : 10, y: compact ? 2 : 3)
            } else {
                Capsule()
                    .fill(Theme.primaryContainer())
                    .opacity(0.6)
            }
        }
    }
}

struct GlassSecondaryButton: View {
    var title: String
    var icon: String? = nil
    var fullWidth = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .diaryFont(13, weight: .semibold)
                }
                Text(title)
                    .diaryFont(14, weight: .medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Theme.onSurfaceVariant())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(Theme.glassDim())
                .glassEffect(.regular, in: Capsule())
        }
    }
}

struct GlassIconButton: View {
    var systemName: String
    var size: CGFloat = 32
    var tint: Color? = nil
    var accessibilityLabel: String? = nil
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .diaryFont(size > 36 ? 16 : 14, weight: .semibold)
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Theme.onSurfaceVariant()))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}

struct PressableGlassIcon: View {
    var systemName: String
    var size: CGFloat = 40
    var active = false
    var accessibilityLabel: String? = nil
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .diaryFont(16, weight: .medium)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(active ? AnyShapeStyle(Theme.primary()) : AnyShapeStyle(Theme.onSurface()))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .symbolEffect(.bounce, value: active)
        .accessibilityLabel(accessibilityLabel ?? systemName)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - Sheet header

struct GlassSheetHeader: View {
    var title: String
    var onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .diaryFont(17, weight: .medium)
                .foregroundStyle(Theme.onSurface())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            GlassIconButton(systemName: "xmark") { onClose() }
        }
    }
}

// MARK: - Chips

struct GlassChip: View {
    var label: String
    var active = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(label)
                .diaryFont(13)
                .foregroundStyle(active ? Theme.primary() : Theme.onSurface())
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct InfoCapsule: View {
    var text: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            Haptics.tap()
            action?()
        } label: {
            Text(text)
                .diaryFont(13, weight: .medium)
                .foregroundStyle(Theme.onSurface())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }
}

// MARK: - Badges & action chips

struct GlassCountBadge: View {
    var text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .diaryFont(10, weight: .semibold)
            }
            Text(text)
                .diaryFont(12, weight: .medium)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.primary())
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(Theme.primaryContainer())
        }
    }
}

struct GlassActionChip: View {
    var label: String
    var systemImage: String? = nil
    var active = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .diaryFont(11, weight: .medium)
                }
                Text(label)
                    .diaryFont(13)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(active ? Theme.primary() : Theme.onSurface())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - Empty state

struct GlassEmptyState: View {
    var systemImage: String
    var text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .diaryFont(26)
                .foregroundStyle(Theme.onSurfaceVariant().opacity(0.5))
            Text(text)
                .diaryFont(14)
                .foregroundStyle(Theme.onSurfaceVariant())
            if let actionTitle, let action {
                GlassPrimaryButton(title: actionTitle, compact: true, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
    }
}

// MARK: - Shared alert

struct AppAlertItem: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var cancelLabel: String = L10n.str("cancel")
    var secondaryLabel: String?
    var primaryAction: (() -> Void)?

    static func confirm(title: String, message: String, confirmLabel: String,
                        action: (() -> Void)? = nil) -> AppAlertItem {
        AppAlertItem(title: title, message: message, secondaryLabel: confirmLabel, primaryAction: action)
    }

    static func info(title: String, message: String, action: (() -> Void)? = nil) -> AppAlertItem {
        AppAlertItem(title: title, message: message, primaryAction: action)
    }
}

extension View {
    /// Presents `AppAlertItem` through the current item-based `alert` API, which
    /// renders buttons in the system order with the platform's Liquid Glass
    /// presentation. The previous implementation routed through `Alert`, which
    /// SwiftUI deprecated in iOS 15.
    func appAlert(item: Binding<AppAlertItem?>) -> some View {
        alert(item.wrappedValue?.title ?? "", item: item) { current in
            if let secondary = current.secondaryLabel {
                Button(secondary) { current.primaryAction?() }
                Button(current.cancelLabel, role: .cancel) {}
            } else {
                Button(current.cancelLabel) { current.primaryAction?() }
            }
        } message: { current in
            Text(current.message)
        }
    }
}

// MARK: - Search field

struct GlassSearchField<Content: View>: View {
    @Binding var text: String
    var placeholder: String
    var cornerRadius: CGFloat = 28
    var focus: FocusState<Bool>.Binding? = nil
    var onSubmit: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Content

    init(text: Binding<String>,
         placeholder: String,
         cornerRadius: CGFloat = 28,
         focus: FocusState<Bool>.Binding? = nil,
         onSubmit: (() -> Void)? = nil,
         @ViewBuilder trailing: @escaping () -> Content = { EmptyView() }) {
        self._text = text
        self.placeholder = placeholder
        self.cornerRadius = cornerRadius
        self.focus = focus
        self.onSubmit = onSubmit
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .diaryFont(15)
                .foregroundStyle(Theme.onSurfaceVariant())
            TextField(placeholder, text: $text)
                .diaryFont(15)
                .tint(Theme.primary())
                .applyFocus(focus)
                .submitLabel(.search)
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .diaryFont(15)
                        .foregroundStyle(Theme.onSurfaceVariant())
                }
                .buttonStyle(.plain)
            }
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .diaryCard(cornerRadius: cornerRadius, interactive: true)
    }
}

// MARK: - Rows

struct RowDivider: View {
    var horizontalPadding: CGFloat = 0

    var body: some View {
        Divider()
            .overlay(Theme.outlineVariant().opacity(0.5))
            .padding(.horizontal, horizontalPadding)
    }
}

struct GlassIconBadge: View {
    var systemName: String
    var size: CGFloat = 38
    var cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.primaryContainer())
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Theme.glassBorder(), lineWidth: 1)
                }
            Image(systemName: systemName)
                .diaryFont(16)
                .foregroundStyle(Theme.onSurface())
        }
    }
}

// MARK: - Flow light overlay

struct FlowLightOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var paused = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.flowMaskColor())
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused || reduceMotion)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let cycle = (t.truncatingRemainder(dividingBy: 4.0)) / 4.0
                    let pos = cycle * geo.size.width * 2
                    let alpha = max(0, 1 - abs(cycle - 0.5) * 4)
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, Theme.flowLightColor(), .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width, height: 3)
                        .position(x: pos - geo.size.width / 2, y: 6)
                        .opacity(alpha)
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, Theme.flowLight(), .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width, height: 3)
                        .position(x: geo.size.width - pos + geo.size.width / 2, y: geo.size.height - 6)
                        .opacity(alpha * 0.7)
                }
            }
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .allowsHitTesting(false)
        .task {
            try? await Task.sleep(for: .seconds(10))
            withAnimation(.easeInOut(duration: 1.0)) {
                paused = true
            }
        }
        .onDisappear { paused = false }
    }
}

// MARK: - View extensions

extension View {
    @ViewBuilder
    fileprivate func applyFocus(_ focus: FocusState<Bool>.Binding?) -> some View {
        if let focus {
            self.focused(focus)
        } else {
            self
        }
    }
}
