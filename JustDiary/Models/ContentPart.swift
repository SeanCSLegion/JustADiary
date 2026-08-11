import Foundation

struct TextRun: Codable, Equatable {
    var text: String
    var bold: Bool?
    var italic: Bool?
    var strike: Bool?
    var underline: Bool?
    var size: Double?
}

struct ContentPart: Codable, Equatable {
    var type: String
    var text: String?
    var items: [String]?
    var done: [Bool]?
    var src: String?
    var runs: [TextRun]?
    var w: Double?
    var h: Double?
    var align: String?

    enum CodingKeys: String, CodingKey {
        case type, text, items, done, src, runs, w, h, align
    }

    init(type: String, text: String? = nil, items: [String]? = nil, done: [Bool]? = nil,
         src: String? = nil, runs: [TextRun]? = nil, w: Double? = nil, h: Double? = nil,
         align: String? = nil) {
        self.type = type
        self.text = text
        self.items = items
        self.done = done
        self.src = src
        self.runs = runs
        self.w = w
        self.h = h
        self.align = align
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(items, forKey: .items)
        try container.encodeIfPresent(done, forKey: .done)
        try container.encodeIfPresent(src, forKey: .src)
        try container.encodeIfPresent(runs, forKey: .runs)
        try container.encodeIfPresent(w, forKey: .w)
        try container.encodeIfPresent(h, forKey: .h)
        try container.encodeIfPresent(align, forKey: .align)
    }
}

enum ContentPartType {
    static let paragraph = "p"
    static let h1 = "h1"
    static let h2 = "h2"
    static let list = "ul"
    static let todo = "todo"
    static let quote = "quote"
    static let image = "img"
}

enum ContentFlatten {
    static func flattenPart(_ part: ContentPart) -> String {
        if let runs = part.runs, !runs.isEmpty {
            return runs.map { $0.text }.joined()
        }
        if let text = part.text {
            return text
        }
        if let items = part.items {
            return items.joined()
        }
        return ""
    }

    static func flattenContent(_ json: String) -> String {
        guard !json.isEmpty else { return "" }
        guard let data = json.data(using: .utf8) else { return "" }
        guard let parts = try? JSONDecoder().decode([ContentPart].self, from: data) else { return "" }
        return parts.map(flattenPart).joined()
    }

    static func parseContent(_ json: String) -> [ContentPart] {
        guard !json.isEmpty else { return [] }
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ContentPart].self, from: data)) ?? []
    }

    static func serializeContent(_ parts: [ContentPart]) -> String {
        guard let data = try? JSONEncoder().encode(parts) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

enum ImagePathUtil {
    static func normalizeSrcKey(_ src: String) -> String {
        if src.hasPrefix("images/") {
            return src
        }
        let basename = (src as NSString).lastPathComponent
        return "images/" + basename
    }

    static func normalizeContentImagePaths(_ json: String) -> String {
        var parts = ContentFlatten.parseContent(json)
        var changed = false
        for i in parts.indices {
            if let src = parts[i].src {
                let normalized = normalizeSrcKey(src)
                if normalized != src {
                    parts[i].src = normalized
                    changed = true
                }
            }
        }
        return changed ? ContentFlatten.serializeContent(parts) : json
    }

    static func resolveImagePath(_ src: String) -> String {
        let key = normalizeSrcKey(src)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(key).path
    }

    static func collectImageSrcs(_ json: String) -> [String] {
        return ContentFlatten.parseContent(json).compactMap { $0.src }
    }
}

enum FtsSegment {
    static func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
            || (0x3400...0x4DBF).contains(scalar.value)
            || (0x3000...0x303F).contains(scalar.value)
    }

    static func segment(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var out = ""
        var prev: Character?
        for ch in text {
            if let p = prev, isCJK(p), isCJK(ch) {
                out.append(" ")
            }
            out.append(ch)
            prev = ch
        }
        return out
    }

    static func desegment(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var lastWasCJK = false
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == " " {
                var j = i + 1
                var nextIsCJK = false
                while j < chars.count {
                    let c = chars[j]
                    if c == "<" {
                        while j < chars.count && chars[j] != ">" { j += 1 }
                        j += 1
                        continue
                    }
                    if c != " " {
                        nextIsCJK = isCJK(c)
                        break
                    }
                    j += 1
                }
                if lastWasCJK && nextIsCJK {
                    i += 1
                    continue
                }
                out.append(ch)
                lastWasCJK = false
                i += 1
                continue
            }
            out.append(ch)
            if ch == "<" {
                var end = i
                while end < chars.count && chars[end] != ">" { end += 1 }
                if end < chars.count {
                    out.append(contentsOf: chars[(i + 1)...end])
                    i = end
                }
            } else {
                lastWasCJK = isCJK(ch)
            }
            i += 1
        }
        return out
    }
}

enum SearchUtil {
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
