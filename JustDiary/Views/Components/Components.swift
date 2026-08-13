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
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?.screen.bounds.size
            ?? CGSize(width: 393, height: 852)
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

struct GlassCapsule: View {
    var cornerRadius: CGFloat = 28
    var blur: CGFloat = 26
    var opacity: Double = 1
    var tint: Color? = nil
    var interactive = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .glassEffect(tintedGlass(tint, interactive: interactive),
                         in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(opacity)
    }
}

extension View {
    func diaryGlassCard(tint: Color? = nil, cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .glassEffect(tintedGlass(tint, interactive: interactive),
                             in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
                .font(.system(size: 24, weight: .medium))
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
                        .font(.system(size: compact ? 12 : 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: compact ? 13 : 14, weight: .medium))
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
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .medium))
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
                .font(.system(size: size > 36 ? 16 : 14, weight: .semibold))
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
                .font(.system(size: 16, weight: .medium))
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
                .font(.system(size: 17, weight: .medium))
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
                .font(.system(size: 13))
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
                .font(.system(size: 13, weight: .medium))
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
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.primary())
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(Theme.primaryContainer())
                .glassEffect(.regular.tint(Theme.primary()).interactive(true), in: Capsule())
                .shadow(color: Theme.glowColor(), radius: 6, y: 2)
        }
    }
}

struct GlassActionChip: View {
    var label: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Theme.primary())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
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
                .font(.system(size: 26))
                .foregroundStyle(Theme.onSurfaceVariant().opacity(0.5))
            Text(text)
                .font(.system(size: 14))
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
    func appAlert(item: Binding<AppAlertItem?>) -> some View {
        alert(item: item) { item in
            if let secondary = item.secondaryLabel {
                return Alert(title: Text(item.title), message: Text(item.message),
                             primaryButton: .default(Text(secondary)) {
                    item.primaryAction?()
                },
                             secondaryButton: .cancel(Text(item.cancelLabel)))
            }
            return Alert(title: Text(item.title), message: Text(item.message),
                         dismissButton: .default(Text(item.cancelLabel)) {
                item.primaryAction?()
            })
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
                .font(.system(size: 15))
                .foregroundStyle(Theme.onSurfaceVariant())
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .tint(Theme.primary())
                .applyFocus(focus)
                .submitLabel(.search)
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.onSurfaceVariant())
                }
                .buttonStyle(.plain)
            }
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .diaryGlassCard(cornerRadius: cornerRadius, interactive: true)
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
                .fill(Theme.glassDim())
                .glassEffect(tintedGlass(nil),
                             in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Theme.glassBorder(), lineWidth: 1)
                }
            Image(systemName: systemName)
                .font(.system(size: 16))
                .foregroundStyle(Theme.onSurface())
        }
    }
}

// MARK: - Flow light overlay

struct FlowLightOverlay: View {
    @State private var paused = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.flowMaskColor())
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { context in
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
