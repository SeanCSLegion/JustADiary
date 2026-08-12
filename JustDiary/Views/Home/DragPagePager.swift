import SwiftUI

struct DragPagePager<Key: Hashable, Page: View>: View {
    var keys: [Key]
    var current: Key
    var axis: Axis = .vertical
    var pageSize: CGFloat
    var disabled: Bool = false
    var onPageChange: (Key) -> Void
    @ViewBuilder var page: (Key) -> Page

    @State private var offset: CGFloat = 0

    var body: some View {
        let idx = keys.firstIndex(of: current) ?? 0
        let prevKey = idx > 0 ? keys[idx - 1] : nil
        let nextKey = idx < keys.count - 1 ? keys[idx + 1] : nil
        ZStack {
            if let prevKey {
                page(prevKey)
                    .frame(width: axis == .horizontal ? pageSize : nil,
                           height: axis == .vertical ? pageSize : nil)
                    .offset(x: axis == .horizontal ? offset - pageSize : 0,
                            y: axis == .vertical ? offset - pageSize : 0)
            }
            page(current)
                .frame(width: axis == .horizontal ? pageSize : nil,
                       height: axis == .vertical ? pageSize : nil)
                .offset(x: axis == .horizontal ? offset : 0,
                        y: axis == .vertical ? offset : 0)
            if let nextKey {
                page(nextKey)
                    .frame(width: axis == .horizontal ? pageSize : nil,
                           height: axis == .vertical ? pageSize : nil)
                    .offset(x: axis == .horizontal ? offset + pageSize : 0,
                            y: axis == .vertical ? offset + pageSize : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture(prevKey: prevKey, nextKey: nextKey), isEnabled: !disabled)
        .onChange(of: current) { _, _ in
            offset = 0
        }
    }

    private func dragGesture(prevKey: Key?, nextKey: Key?) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !disabled else { return }
                let t = axis == .vertical ? value.translation.height : value.translation.width
                var raw = t
                if t > 0, prevKey == nil { raw = rubber(t) }
                if t < 0, nextKey == nil { raw = -rubber(-t) }
                offset = raw
            }
            .onEnded { value in
                guard !disabled else { return }
                let t = axis == .vertical ? value.translation.height : value.translation.width
                let p = axis == .vertical ? value.predictedEndTranslation.height : value.predictedEndTranslation.width
                let goNext = nextKey != nil && (p < -90 || (p < 0 && t < -60))
                let goPrev = prevKey != nil && (p > 90 || (p > 0 && t > 60))
                if goNext || goPrev {
                    let target = goNext ? nextKey : prevKey
                    let delta = goNext ? -pageSize : pageSize
                    withAnimation(.snappy(duration: 0.3)) {
                        offset = delta
                    } completion: {
                        var tr = Transaction()
                        tr.disablesAnimations = true
                        withTransaction(tr) { offset = 0 }
                        if let target { onPageChange(target) }
                    }
                } else {
                    withAnimation(.snappy(duration: 0.3)) {
                        offset = 0
                    }
                }
            }
    }

    private func rubber(_ x: CGFloat) -> CGFloat {
        let c = pageSize * 0.25
        return c * x / (x + c)
    }
}
