import UIKit

nonisolated struct ShareBlock {
    var time: Int64
    var loc: String
    var parts: [ContentPart]
}

/// 分享长图渲染器（2026-09 重做）。
///
/// 旧版是「三个大色球 + 满屏渐变 + 一条悬空的蓝色时间轴」：背景花花绿绿把正文的对比度
/// 拉低，横幅式的大日期下面又重复一次首条时间，底部只有一行几乎看不见的「· 一页时光 ·」。
///
/// 新版按应用内已有的语言来：
/// - **卡片**：每条记录一张白（深色下是深灰）卡片，与应用内「每条记录一张卡」一致，
///   文字永远压在浅底上；
/// - **克制的背景**：极淡的中性渐变 + 一层品牌色晕染，不再抢内容；
/// - **清楚的头部**：品牌行 → 大日期 + 星期 → 起始时间 / 地点 → 品牌色短线；
/// - **正经的页脚**：细线 +「一页时光 · JustADiary」+ 当天日期。
///
/// 排版与绘制**共用同一份结果**：`makePage` 一次算出每段文字的矩形并产出绘制指令，
/// 绘制阶段只执行指令，不会出现「量出来 3 行、画出来 4 行」的错位（旧实现两边各算一遍）。
nonisolated enum ShareRenderer {
    static let width = 720.0

    // MARK: - 版面常量

    private enum M {
        static let margin = 56.0
        static var content: Double { width - margin * 2 }
        static let top = 56.0
        static let brandH = 34.0
        static let afterBrand = 24.0
        static let dateH = 74.0
        static let afterDate = 12.0
        static let metaH = 34.0
        static let afterMeta = 26.0
        static let ruleWidth = 64.0
        static let ruleHeight = 5.0
        static let afterRule = 40.0
        static let entryHeadH = 38.0
        static let afterEntryHead = 14.0
        static let cardPadH = 30.0
        static let cardPadV = 28.0
        static let cardRadius = 26.0
        static let betweenEntries = 30.0
        static let partGap = 20.0
        static let looseGap = 26.0
        static let beforeFooter = 46.0
        static let footerH = 30.0
        static let bottom = 48.0
    }

    private enum F {
        static let brand = UIFont.systemFont(ofSize: 26, weight: .semibold)
        static let year = UIFont.systemFont(ofSize: 22, weight: .medium)
        static let date = UIFont.systemFont(ofSize: 58, weight: .bold)
        static let weekday = UIFont.systemFont(ofSize: 28, weight: .medium)
        static let meta = UIFont.systemFont(ofSize: 25)
        static let time = UIFont.systemFont(ofSize: 27, weight: .semibold)
        static let loc = UIFont.systemFont(ofSize: 23)
        static let title = UIFont.systemFont(ofSize: 38, weight: .bold)
        static let heading = UIFont.systemFont(ofSize: 32, weight: .semibold)
        static let body = UIFont.systemFont(ofSize: 29)
        static let quote = UIFont.systemFont(ofSize: 27)
        static let item = UIFont.systemFont(ofSize: 29)
        static let footer = UIFont.systemFont(ofSize: 22, weight: .medium)
    }

    private enum LH {
        static let title = 54.0
        static let heading = 46.0
        static let body = 48.0
        static let quote = 44.0
        static let item = 46.0
        static let footer = 30.0
    }

    // MARK: - 配色

    private struct Palette {
        var text: UIColor
        var sub: UIColor
        var faint: UIColor
        var accent: UIColor
        var bgTop: UIColor
        var bgBottom: UIColor
        var glowStrong: UIColor
        var glowSoft: UIColor
        var card: UIColor
        var cardBorder: UIColor
        var cardShadow: UIColor
        var quoteBg: UIColor

        /// 与 `Theme.seed`（#2563EB）同源：浅色底用标准品牌色，深色底提亮一档。
        static func light() -> Palette {
            Palette(text: UIColor(hex: 0x15181D),
                    sub: UIColor(hex: 0x5B6472),
                    faint: UIColor(hex: 0x98A1B0),
                    accent: UIColor(hex: 0x2563EB),
                    bgTop: UIColor(hex: 0xF8F9FC),
                    bgBottom: UIColor(hex: 0xEDF0F7),
                    glowStrong: UIColor(hex: 0x2563EB),
                    glowSoft: UIColor(hex: 0x7C5CFF),
                    card: UIColor(hex: 0xFFFFFF),
                    cardBorder: UIColor(hex: 0x15181D).withAlphaComponent(0.06),
                    cardShadow: UIColor(hex: 0x15181D).withAlphaComponent(0.08),
                    quoteBg: UIColor(hex: 0x2563EB).withAlphaComponent(0.07))
        }

        static func dark() -> Palette {
            Palette(text: UIColor(hex: 0xECEDF1),
                    sub: UIColor(hex: 0xA7AEBB),
                    faint: UIColor(hex: 0x6E7683),
                    accent: UIColor(hex: 0x7C97FF),
                    bgTop: UIColor(hex: 0x0C0F14),
                    bgBottom: UIColor(hex: 0x131722),
                    glowStrong: UIColor(hex: 0x3B6BFF),
                    glowSoft: UIColor(hex: 0x8A5CFF),
                    card: UIColor(hex: 0x1A1F29),
                    cardBorder: UIColor.white.withAlphaComponent(0.07),
                    cardShadow: UIColor.black.withAlphaComponent(0.45),
                    quoteBg: UIColor(hex: 0x7C97FF).withAlphaComponent(0.14))
        }
    }

    // MARK: - 绘制指令
    //
    // 排版阶段只产出指令（颜色一起定好），绘制阶段照着执行 —— 两边不会再各自量一遍文字。

    private enum Op {
        case fillRounded(CGRect, radius: CGFloat, color: UIColor)
        case card(CGRect, radius: CGFloat, fill: UIColor, border: UIColor, shadow: UIColor)
        case text(String, CGRect, font: UIFont, lineHeight: Double, color: UIColor, align: NSTextAlignment)
        case bar(CGRect, radius: CGFloat, color: UIColor)
        case dot(CGPoint, radius: CGFloat, color: UIColor)
        case image(String, CGRect, radius: CGFloat)
        case checkbox(CGRect, checked: Bool, fill: UIColor, border: UIColor, mark: UIColor)
    }

    private struct Page {
        var height: Double
        var ops: [Op]
    }

    // MARK: - 对外入口

    /// `showTime == false`（`auto_time` 关闭）时隐藏头部起始行与每条记录的时间 —— 只影响
    /// **显示**：`ShareBlock.time` 仍照常传入（数据层与备份格式不受影响）。
    static func render(dayKey: String, blocks: [ShareBlock], isDark: Bool, showTime: Bool = true) -> UIImage? {
        let date = DateUtil.parseDayKey(dayKey) ?? Date()
        let palette = isDark ? Palette.dark() : Palette.light()
        let page = makePage(date: date, dayKey: dayKey, blocks: blocks, showTime: showTime, palette: palette)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: page.height), format: format)
        return renderer.image { ctx in
            drawBackground(ctx.cgContext, height: page.height, palette: palette)
            for op in page.ops {
                draw(op, in: ctx.cgContext, palette: palette)
            }
        }
    }

    // MARK: - 排版

    private static func makePage(date: Date, dayKey: String, blocks: [ShareBlock],
                                 showTime: Bool, palette: Palette) -> Page {
        var ops: [Op] = []
        var y = M.top

        // 品牌行：左边品牌点 + 名字，右边年份。
        let brand = L10n.str("EntryAbility_label")
        ops.append(.dot(CGPoint(x: M.margin + 7, y: y + 17), radius: 7, color: palette.accent))
        ops.append(.text(brand, CGRect(x: M.margin + 26, y: y, width: M.content - 140, height: M.brandH),
                         font: F.brand, lineHeight: M.brandH, color: palette.text, align: .left))
        ops.append(.text(L10n.fmt("date_year", DateUtil.calendar.component(.year, from: date)),
                         CGRect(x: M.margin, y: y + 5, width: M.content, height: 26),
                         font: F.year, lineHeight: 26, color: palette.faint, align: .right))
        y += M.brandH + M.afterBrand

        // 大日期 + 星期（两者基线对齐）。
        let dateText = L10n.dateOnly(date)
        ops.append(.text(dateText, CGRect(x: M.margin, y: y, width: M.content, height: M.dateH),
                         font: F.date, lineHeight: M.dateH, color: palette.text, align: .left))
        let dateWidth = textWidth(dateText, font: F.date)
        let weekday = L10n.weekdayName(DateUtil.calendar.component(.weekday, from: date) - 1)
        // 行盒高 LH 时，第一行基线在盒顶下方 (LH + descender)（descender 为负），
        // 用它把星期压到与大日期同一条基线上。
        let weekdayLH = ceil(F.weekday.lineHeight)
        let dateBaseline = y + M.dateH + F.date.descender
        ops.append(.text(weekday,
                         CGRect(x: M.margin + dateWidth + 16,
                                y: dateBaseline - (weekdayLH + F.weekday.descender),
                                width: max(40, M.content - dateWidth - 16), height: weekdayLH),
                         font: F.weekday, lineHeight: weekdayLH, color: palette.sub, align: .left))
        y += M.dateH + M.afterDate

        // 起始时间 / 地点。
        if let meta = metaLine(blocks: blocks, showTime: showTime) {
            let metaH = textHeight(meta, font: F.meta, width: M.content, lineHeight: M.metaH)
            ops.append(.text(meta, CGRect(x: M.margin, y: y, width: M.content, height: metaH),
                             font: F.meta, lineHeight: M.metaH, color: palette.sub, align: .left))
            y += metaH + M.afterMeta
        } else {
            y += M.afterMeta
        }

        // 品牌色短线。
        ops.append(.fillRounded(CGRect(x: M.margin, y: y, width: M.ruleWidth, height: M.ruleHeight),
                                radius: M.ruleHeight / 2, color: palette.accent))
        y += M.ruleHeight + M.afterRule

        // 每条记录：时间 / 地点行 + 卡片。
        var wroteEntry = false
        for block in blocks {
            let timeText = showTime && block.time > 0 ? L10n.timeOf(block.time) : nil
            let locText = block.loc.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasContent = !block.parts.isEmpty
            guard hasContent || timeText != nil || !locText.isEmpty else { continue }

            if wroteEntry { y += M.betweenEntries }
            wroteEntry = true

            if timeText != nil || !locText.isEmpty {
                var headX = M.margin
                if let timeText {
                    ops.append(.text(timeText, CGRect(x: headX, y: y, width: 160, height: M.entryHeadH),
                                     font: F.time, lineHeight: M.entryHeadH, color: palette.accent, align: .left))
                    headX += textWidth(timeText, font: F.time) + 14
                }
                if !locText.isEmpty, headX < M.margin + M.content - 60 {
                    ops.append(.text(locText,
                                     CGRect(x: headX, y: y + 6,
                                            width: M.margin + M.content - headX, height: 30),
                                     font: F.loc, lineHeight: 30, color: palette.sub, align: .left))
                }
                y += M.entryHeadH + M.afterEntryHead
            }

            // 空片段（只有时间、没有内容）不画空卡片。
            guard hasContent else { continue }
            let cardTop = y
            let cardIndex = ops.count          // 卡片本体要画在这段内容之前
            var contentY = cardTop + M.cardPadV
            let innerWidth = M.content - M.cardPadH * 2
            for (index, part) in block.parts.enumerated() {
                if index > 0 { contentY += gapBefore(part) }
                contentY += appendPart(part, x: M.margin + M.cardPadH, y: contentY,
                                       width: innerWidth, ops: &ops, palette: palette)
            }
            let cardHeight = contentY - cardTop + M.cardPadV
            ops.insert(.card(CGRect(x: M.margin, y: cardTop, width: M.content, height: cardHeight),
                             radius: M.cardRadius, fill: palette.card,
                             border: palette.cardBorder, shadow: palette.cardShadow),
                       at: cardIndex)
            y = cardTop + cardHeight
        }

        // 页脚：细线 + 品牌 + 当天日期。
        y += M.beforeFooter
        ops.append(.fillRounded(CGRect(x: M.margin, y: y, width: M.content, height: 1),
                                radius: 0.5, color: palette.faint.withAlphaComponent(0.35)))
        y += 22
        ops.append(.text("\(L10n.str("EntryAbility_label")) · JustADiary",
                         CGRect(x: M.margin, y: y, width: M.content * 0.6, height: M.footerH),
                         font: F.footer, lineHeight: LH.footer, color: palette.faint, align: .left))
        ops.append(.text(dayKey, CGRect(x: M.margin + M.content * 0.4, y: y,
                                        width: M.content * 0.6, height: M.footerH),
                         font: F.footer, lineHeight: LH.footer, color: palette.faint, align: .right))
        y += M.footerH + M.bottom

        return Page(height: y, ops: ops)
    }

    /// 段与段之间的间距：标题 / 小标题离它上面远一点，离下面的正文近一点。
    private static func gapBefore(_ part: ContentPart) -> Double {
        switch part.style {
        case ContentPartStyle.title, ContentPartStyle.heading: return M.looseGap
        default: return M.partGap
        }
    }

    /// 画一段内容，返回它占的高度。
    private static func appendPart(_ part: ContentPart, x: Double, y: Double, width: Double,
                                   ops: inout [Op], palette: Palette) -> Double {
        let text = ContentFlatten.flattenPart(part)
        switch part.style {
        case ContentPartStyle.title:
            let h = textHeight(text, font: F.title, width: width, lineHeight: LH.title)
            ops.append(.text(text, CGRect(x: x, y: y, width: width, height: h),
                             font: F.title, lineHeight: LH.title, color: palette.text, align: .left))
            return h
        case ContentPartStyle.heading:
            let h = textHeight(text, font: F.heading, width: width, lineHeight: LH.heading)
            ops.append(.text(text, CGRect(x: x, y: y, width: width, height: h),
                             font: F.heading, lineHeight: LH.heading, color: palette.text, align: .left))
            return h
        case ContentPartStyle.quote:
            let padV = 22.0
            let textX = x + 26.0
            let textW = width - 46.0
            let textH = textHeight(text, font: F.quote, width: textW, lineHeight: LH.quote)
            let boxH = textH + padV * 2
            ops.append(.fillRounded(CGRect(x: x, y: y, width: width, height: boxH),
                                    radius: 16, color: palette.quoteBg))
            ops.append(.bar(CGRect(x: x, y: y + 10, width: 5, height: boxH - 20),
                            radius: 2.5, color: palette.accent))
            ops.append(.text(text, CGRect(x: textX, y: y + padV, width: textW, height: textH),
                             font: F.quote, lineHeight: LH.quote, color: palette.text, align: .left))
            return boxH
        case ContentPartStyle.list:
            return appendItems(part.items ?? [], done: nil, x: x, y: y, width: width,
                               ops: &ops, palette: palette)
        case ContentPartStyle.todo:
            let items = part.items ?? []
            let done = part.done ?? Array(repeating: false, count: items.count)
            return appendItems(items, done: done, x: x, y: y, width: width,
                               ops: &ops, palette: palette)
        case ContentPartStyle.image:
            let boxH = imageHeight(part, width: width)
            if let src = part.src {
                ops.append(.image(src, CGRect(x: x, y: y, width: width, height: boxH), radius: 20))
            }
            return boxH
        default:
            let h = textHeight(text, font: F.body, width: width, lineHeight: LH.body)
            ops.append(.text(text, CGRect(x: x, y: y, width: width, height: h),
                             font: F.body, lineHeight: LH.body, color: palette.text, align: .left))
            return h
        }
    }

    private static func appendItems(_ items: [String], done: [Bool]?, x: Double, y: Double, width: Double,
                                    ops: inout [Op], palette: Palette) -> Double {
        var cursor = y
        let markerW = done == nil ? 30.0 : 48.0
        let textW = width - markerW
        for (i, item) in items.enumerated() {
            let isDone = done?.indices.contains(i) == true ? (done?[i] ?? false) : false
            let h = textHeight(item, font: F.item, width: textW, lineHeight: LH.item)
            if done == nil {
                ops.append(.dot(CGPoint(x: x + 9, y: cursor + LH.item / 2 - 3), radius: 5.5, color: palette.accent))
            } else {
                ops.append(.checkbox(CGRect(x: x, y: cursor + 8, width: 30, height: 30), checked: isDone,
                                     fill: palette.accent, border: palette.faint, mark: .white))
            }
            ops.append(.text(item, CGRect(x: x + markerW, y: cursor, width: textW, height: h),
                             font: F.item, lineHeight: LH.item,
                             color: isDone ? palette.sub : palette.text, align: .left))
            cursor += h + 16
        }
        return max(0, cursor - y - 16)
    }

    // MARK: - 文字量算

    private static func attributes(_ font: UIFont, lineHeight: Double, color: UIColor = .black,
                                   align: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.alignment = align
        style.lineBreakMode = .byWordWrapping
        return [.font: font, .paragraphStyle: style, .foregroundColor: color]
    }

    private static func textHeight(_ text: String, font: UIFont, width: Double, lineHeight: Double) -> Double {
        guard !text.isEmpty, width > 0 else { return lineHeight }
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(font, lineHeight: lineHeight), context: nil)
        return max(lineHeight, ceil(rect.height))
    }

    private static func textWidth(_ text: String, font: UIFont) -> Double {
        Double((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func imageHeight(_ part: ContentPart, width: Double) -> Double {
        let w = part.w ?? 0
        let h = part.h ?? 0
        let ratio: Double
        if w > 0, h > 0 {
            ratio = Double(h) / Double(w)
        } else if let img = loadImage(part.src), img.size.width > 0 {
            ratio = Double(img.size.height / img.size.width)
        } else {
            ratio = 0.75
        }
        return max(120, width * ratio)
    }

    private static func loadImage(_ src: String?) -> UIImage? {
        guard let src else { return nil }
        return UIImage(contentsOfFile: ImagePathUtil.resolveImagePath(src))
    }

    /// 头部第二行：这一天的开始时间。
    ///
    /// 只放时间，不放地点 —— 地点就在下面第一条记录的时间行里，重复一遍反而更乱；
    /// `auto_time` 关闭时这一行整块不画。
    private static func metaLine(blocks: [ShareBlock], showTime: Bool) -> String? {
        guard showTime, let first = blocks.first, first.time > 0 else { return nil }
        return L10n.fmt("read_start_time", L10n.timeOf(first.time))
    }

    // MARK: - 绘制

    private static func draw(_ op: Op, in c: CGContext, palette: Palette) {
        switch op {
        case let .fillRounded(rect, radius, color):
            c.setFillColor(color.cgColor)
            UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
        case let .card(rect, radius, fill, border, shadow):
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: 6), blur: 26, color: shadow.cgColor)
            c.setFillColor(fill.cgColor)
            UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
            c.restoreGState()
            c.setStrokeColor(border.cgColor)
            c.setLineWidth(2)
            UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: radius - 1).stroke()
        case let .text(text, rect, font, lineHeight, color, align):
            (text as NSString).draw(with: rect,
                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                    attributes: attributes(font, lineHeight: lineHeight, color: color, align: align),
                                    context: nil)
        case let .bar(rect, radius, color):
            c.setFillColor(color.cgColor)
            UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
        case let .dot(center, radius, color):
            c.setFillColor(color.cgColor)
            c.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                     width: radius * 2, height: radius * 2))
        case let .image(src, rect, radius):
            guard let img = loadImage(src) else {
                c.setFillColor(palette.quoteBg.cgColor)
                UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
                return
            }
            c.saveGState()
            UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
            let scale = max(rect.width / max(1, img.size.width), rect.height / max(1, img.size.height))
            let drawSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            img.draw(in: CGRect(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2,
                                width: drawSize.width, height: drawSize.height))
            c.restoreGState()
        case let .checkbox(rect, checked, fill, border, mark):
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
            if checked {
                c.setFillColor(fill.cgColor)
                path.fill()
                let check = UIBezierPath()
                check.move(to: CGPoint(x: rect.minX + 8, y: rect.midY + 1))
                check.addLine(to: CGPoint(x: rect.minX + 13, y: rect.maxY - 8))
                check.addLine(to: CGPoint(x: rect.maxX - 7, y: rect.minY + 8))
                check.lineWidth = 3.4
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                c.setStrokeColor(mark.cgColor)
                check.stroke()
            } else {
                c.setStrokeColor(border.cgColor)
                path.lineWidth = 2
                path.stroke()
            }
        }
    }

    private static func drawBackground(_ c: CGContext, height: Double, palette: Palette) {
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [palette.bgTop.cgColor, palette.bgBottom.cgColor] as CFArray,
                                  locations: [0, 1])!
        c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        // 一层品牌色晕染：只让纯色背景有点呼吸感，不参与构图。
        drawGlow(c, center: CGPoint(x: width * 0.94, y: -80), radius: 430,
                 color: palette.glowStrong, alpha: 0.10)
        drawGlow(c, center: CGPoint(x: width * 0.02, y: height * 0.44), radius: 380,
                 color: palette.glowSoft, alpha: 0.06)
    }

    private static func drawGlow(_ c: CGContext, center: CGPoint, radius: Double,
                                 color: UIColor, alpha: Double) {
        let colors = [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        c.saveGState()
        c.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2))
        c.clip()
        c.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                             endCenter: center, endRadius: radius, options: [])
        c.restoreGState()
    }
}
