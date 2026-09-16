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
        // A disabled pager cannot scroll, so its neighbouring pages only exist
        // to be dragged into view. Building them costs a full page render each
        // (three year pages = 36 month canvases), so skip them unless the
        // current offset actually reveals them.
        let showsNeighbours = !disabled || offset != 0
        return ZStack {
            if let prevKey, showsNeighbours {
                page(prevKey)
                    .frame(width: axis == .horizontal ? pageSize : nil,
                           height: axis == .vertical ? pageSize : nil)
                    .offset(x: axis == .horizontal ? offset - pageSize : 0,
                            y: axis == .vertical ? offset - pageSize : 0)
            }
            page(current)
                .frame(width: axis == .horizontal ? pageSize : nil,
                       height: axis == .vertical ? pageSize : nil)
                // 每页单独裁剪：页内容超出 pageSize 时不会溢到相邻页
                .clipped()
                .offset(x: axis == .horizontal ? offset : 0,
                        y: axis == .vertical ? offset : 0)
            if let nextKey, showsNeighbours {
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
            // 外部改页（今天 / morph 收尾）时也把偏移清零，且不要动画：
            // 这里若继承调用方的 withAnimation，会看见一次多余的滑动。
            var tr = Transaction()
            tr.disablesAnimations = true
            withTransaction(tr) { offset = 0 }
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
                // 夹在一页之内：越过一页继续拖，屏幕会露出当前页之外的空白，
                // 松手再回弹，观感就是「翻月不连贯」。
                offset = min(pageSize, max(-pageSize, raw))
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
                        // `current` 与 `offset` 必须在**同一个**无动画事务里改：
                        // 先换 current 再补 offset=0，会先用旧 offset 渲染一帧新页
                        // （页面向上一跳），再动画滑回原位 —— 这就是翻月末尾的跳变。
                        // 两个一起改，前后两帧像素完全一致，视觉上无缝。
                        var tr = Transaction()
                        tr.disablesAnimations = true
                        withTransaction(tr) {
                            offset = 0
                            if let target { onPageChange(target) }
                        }
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
