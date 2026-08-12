import SwiftUI

struct BlobBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.bg()
                Circle()
                    .fill(Theme.blobA())
                    .frame(width: 280, height: 280)
                    .blur(radius: 60)
                    .position(x: -60, y: 220)
                Circle()
                    .fill(Theme.blobB())
                    .frame(width: 240, height: 240)
                    .blur(radius: 60)
                    .position(x: geo.size.width + 20, y: 640)
                Circle()
                    .fill(Theme.blobC())
                    .frame(width: 200, height: 200)
                    .blur(radius: 55)
                    .position(x: geo.size.width - 30, y: -10)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

struct BlobBackgroundDense: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.bg()
                Circle()
                    .fill(Theme.blobA())
                    .frame(width: 300, height: 300)
                    .blur(radius: 70)
                    .position(x: -80, y: 200)
                Circle()
                    .fill(Theme.blobB())
                    .frame(width: 250, height: 250)
                    .blur(radius: 65)
                    .position(x: geo.size.width + 20, y: 560)
                Circle()
                    .fill(Theme.blobC())
                    .frame(width: 210, height: 210)
                    .blur(radius: 60)
                    .position(x: geo.size.width - 40, y: -30)
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

func tintedGlass(_ tint: Color?, interactive: Bool = false) -> Glass {
    let g = tint.map { Glass.regular.tint($0) } ?? .regular
    return interactive ? g.interactive() : g
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

struct FlowLightOverlay: View {
    @State private var animating = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.flowMaskColor())
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
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
    }
}

struct InfoCapsule: View {
    var text: String
    var action: (() -> Void)? = nil
    @State private var pressed = false

    var body: some View {
        Button {
            Haptics.tap()
            action?()
        } label: {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.onSurface())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .scaleEffect(pressed ? 0.94 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

struct GlassMenu: View {
    var options: [String]
    var selected: String
    var onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    onSelect(i)
                } label: {
                    HStack {
                        Text(options[i])
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.onSurface())
                        Spacer()
                        if options[i] == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.primary())
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
                if i < options.count - 1 {
                    Divider().overlay(Theme.outlineVariant().opacity(0.5))
                }
            }
        }
        .frame(width: 216)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .glassEffect(tintedGlass(nil, interactive: true),
                             in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
    }
}



struct PressableGlassIcon: View {
    var systemName: String
    var size: CGFloat = 40
    var active = false
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
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .symbolEffect(.bounce, value: active)
    }
}

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
    }
}
