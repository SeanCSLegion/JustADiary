import Foundation

nonisolated enum SearchUtil {
    static func escapeLikeTerm(_ term: String) -> String {
        var out = ""
        for ch in term {
            if ch == "\\" || ch == "%" || ch == "_" {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }

    struct Seg {
        var text: String
        var hit: Bool
    }

    static func highlightSegments(_ text: String, keyword: String) -> [Seg] {
        let terms = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return [Seg(text: text, hit: false)] }
        let lower = text.lowercased()
        var ranges: [Range<String.Index>] = []
        for term in terms {
            let tl = term.lowercased()
            var searchStart = lower.startIndex
            while let r = lower.range(of: tl, options: [], range: searchStart..<lower.endIndex) {
                ranges.append(r)
                searchStart = r.upperBound
                if searchStart >= lower.endIndex { break }
            }
        }
        guard !ranges.isEmpty else { return [Seg(text: text, hit: false)] }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for r in ranges {
            if let last = merged.last, r.lowerBound <= last.upperBound {
                let upper = r.upperBound > last.upperBound ? r.upperBound : last.upperBound
                merged[merged.count - 1] = last.lowerBound..<upper
            } else {
                merged.append(r)
            }
        }
        var segs: [Seg] = []
        var cursor = text.startIndex
        for r in merged {
            if r.lowerBound > cursor {
                segs.append(Seg(text: String(text[cursor..<r.lowerBound]), hit: false))
            }
            segs.append(Seg(text: String(text[r]), hit: true))
            cursor = r.upperBound
        }
        if cursor < text.endIndex {
            segs.append(Seg(text: String(text[cursor...]), hit: false))
        }
        return segs
    }

    static func highlightSnippet(_ snippet: String) -> [Seg] {
        var segs: [Seg] = []
        var remaining = snippet
        while true {
            guard let open = remaining.range(of: "<hl>") else {
                if !remaining.isEmpty { segs.append(Seg(text: remaining, hit: false)) }
                break
            }
            if open.lowerBound > remaining.startIndex {
                segs.append(Seg(text: String(remaining[remaining.startIndex..<open.lowerBound]), hit: false))
            }
            let afterOpen = remaining[open.upperBound...]
            guard let close = afterOpen.range(of: "</hl>") else {
                segs.append(Seg(text: String(afterOpen), hit: true))
                break
            }
            let hitText = String(afterOpen[afterOpen.startIndex..<close.lowerBound])
            if !hitText.isEmpty { segs.append(Seg(text: hitText, hit: true)) }
            remaining = String(afterOpen[close.upperBound...])
        }
        return segs
    }

    static func buildFallbackSnippet(_ text: String, keyword: String) -> String {
        let terms = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty, !text.isEmpty else { return "" }
        let lower = text.lowercased()
        var firstRange: Range<String.Index>?
        for term in terms {
            if let r = lower.range(of: term.lowercased()) {
                firstRange = r
                break
            }
        }
        guard let fr = firstRange else { return "" }
        let window: Range<String.Index>
        let start = lower.index(fr.lowerBound, offsetBy: -18, limitedBy: lower.startIndex) ?? lower.startIndex
        let end = lower.index(fr.upperBound, offsetBy: 18, limitedBy: lower.endIndex) ?? lower.endIndex
        window = start..<end
        var result = String(text[window])
        if start > lower.startIndex { result = "…" + result }
        if end < lower.endIndex { result = result + "…" }
        for term in terms {
            let pattern = NSRegularExpression.escapedPattern(for: term)
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let ns = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            var rebuilt = ""
            var cursor = 0
            for m in matches {
                if m.range.location > cursor {
                    rebuilt += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                }
                rebuilt += "<hl>" + ns.substring(with: m.range) + "</hl>"
                cursor = m.range.location + m.range.length
            }
            if cursor < ns.length {
                rebuilt += ns.substring(from: cursor)
            }
            result = rebuilt
        }
        return result
    }
}
