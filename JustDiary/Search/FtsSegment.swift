import Foundation

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
