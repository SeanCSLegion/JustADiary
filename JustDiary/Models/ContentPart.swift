import Foundation

struct TextRun: Codable, Equatable {
    var text: String
    var bold: Bool?
    var italic: Bool?
    var strike: Bool?
    var underline: Bool?
    var size: Double?
}

nonisolated struct ContentPart: Codable, Equatable {
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

nonisolated enum ContentFlatten {
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

nonisolated enum ImagePathUtil {
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


