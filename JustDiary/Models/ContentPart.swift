import Foundation

// MARK: - Inline character styles
//
// A run deliberately has no font size. Its paragraph's size comes from the
// block's `style` and follows the system text-size setting (see
// `docs/editor-typography.md`), so a stored size could only ever describe a size
// the editor is unable to author or edit. Version 1 of the format did store one;
// it is dropped on read.

nonisolated struct TextRun: Codable, Equatable {
    var text: String
    var bold: Bool?
    var italic: Bool?
    var strike: Bool?
    var underline: Bool?

    enum CodingKeys: String, CodingKey {
        case text, bold, italic, strike, underline
    }

    init(text: String, bold: Bool? = nil, italic: Bool? = nil,
         strike: Bool? = nil, underline: Bool? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.strike = strike
        self.underline = underline
    }

    /// Unknown keys — including the `size` v1 wrote — are ignored rather than
    /// rejected, so an old backup still decodes. A flag that is present but
    /// `false` is read as "not set": the two mean the same thing, and `nil` is
    /// the canonical form the encoder writes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        bold = try Self.flag(c, .bold)
        italic = try Self.flag(c, .italic)
        strike = try Self.flag(c, .strike)
        underline = try Self.flag(c, .underline)
    }

    /// Only flags that are actually on are stored; `"bold": false` is noise.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        if bold == true { try c.encode(true, forKey: .bold) }
        if italic == true { try c.encode(true, forKey: .italic) }
        if strike == true { try c.encode(true, forKey: .strike) }
        if underline == true { try c.encode(true, forKey: .underline) }
    }

    private static func flag(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Bool? {
        try c.decodeIfPresent(Bool.self, forKey: key) == true ? true : nil
    }
}

/// One paragraph-level piece of a diary entry: a styled line, a list, a to-do
/// list or an image.
nonisolated struct ContentPart: Codable, Equatable {
    /// One of `ContentPartStyle`.
    var style: String
    /// Plain text, used when the paragraph has no inline styling. The editor
    /// authors `runs`; `text` is the compact form kept for hand-written and
    /// imported content.
    var text: String?
    var items: [String]?
    var done: [Bool]?
    var src: String?
    var runs: [TextRun]?
    var w: Double?
    var h: Double?
    var align: String?

    enum CodingKeys: String, CodingKey {
        case style, text, items, done, src, runs, w, h, align
    }

    /// v1 wrote the block style under `type`.
    private enum LegacyCodingKeys: String, CodingKey {
        case type
    }

    init(style: String, text: String? = nil, items: [String]? = nil, done: [Bool]? = nil,
         src: String? = nil, runs: [TextRun]? = nil, w: Double? = nil, h: Double? = nil,
         align: String? = nil) {
        self.style = style
        self.text = text
        self.items = items
        self.done = done
        self.src = src
        self.runs = runs
        self.w = w
        self.h = h
        self.align = align
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let modern = try c.decodeIfPresent(String.self, forKey: .style)
        let legacy = modern == nil
            ? try decoder.container(keyedBy: LegacyCodingKeys.self).decodeIfPresent(String.self, forKey: .type)
            : nil
        style = ContentPartStyle.normalized(modern ?? legacy ?? ContentPartStyle.body)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        items = try c.decodeIfPresent([String].self, forKey: .items)
        done = try c.decodeIfPresent([Bool].self, forKey: .done)
        src = try c.decodeIfPresent(String.self, forKey: .src)
        runs = try c.decodeIfPresent([TextRun].self, forKey: .runs)
        w = try c.decodeIfPresent(Double.self, forKey: .w)
        h = try c.decodeIfPresent(Double.self, forKey: .h)
        align = try c.decodeIfPresent(String.self, forKey: .align)
    }
}

/// The block styles a stored part can have.
///
/// These are the *only* thing that decides how big a paragraph is drawn: the
/// point size lives in `EditorBlockStyle` and follows the system text-size
/// setting. Values are persisted, so they are stable strings rather than enum
/// cases (an unknown value must decode, not throw).
nonisolated enum ContentPartStyle {
    static let title = "title"
    static let heading = "heading"
    static let body = "body"
    static let list = "list"
    static let todo = "todo"
    static let quote = "quote"
    static let image = "image"

    /// Style names written by v1 of the format, which spelled them after HTML.
    /// Kept so an old backup imports unchanged.
    private static let legacyNames: [String: String] = [
        "h1": title,
        "h2": heading,
        "p": body,
        "ul": list,
        "img": image
    ]

    static func normalized(_ raw: String) -> String {
        legacyNames[raw] ?? raw
    }
}

/// The value stored in `edit_block.content_json`.
///
/// v1 was a bare `[ContentPart]` array whose runs carried a font size and whose
/// style names came from HTML; v2 is this envelope. `parseContent` still decodes
/// v1 so nothing has to be migrated before old data can be read, but everything
/// written from now on is v2 (see `ContentFlatten.serializeContent`).
nonisolated struct ContentDocument: Codable, Equatable {
    /// Bumped whenever the meaning of `parts` changes.
    static let currentVersion = 2

    var v: Int
    var parts: [ContentPart]

    init(parts: [ContentPart]) {
        self.v = Self.currentVersion
        self.parts = parts
    }
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
        parseContent(json).map(flattenPart).joined()
    }

    /// Decodes `content_json`, accepting both format versions.
    static func parseContent(_ json: String) -> [ContentPart] {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(ContentDocument.self, from: data) {
            return document.parts
        }
        // v1: a bare array. `ContentPart` maps the legacy `type` key and style
        // names and drops the per-run font size.
        return (try? decoder.decode([ContentPart].self, from: data)) ?? []
    }

    /// Encodes in the current format. Anything that passes through here — an
    /// edit, an import, the one-time migration — is upgraded to v2.
    static func serializeContent(_ parts: [ContentPart]) -> String {
        let encoder = JSONEncoder()
        // Deterministic and readable storage: a fixed key order, and image paths
        // not escaped as `images\/x.jpg`.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(ContentDocument(parts: parts)) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
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

    /// Rewrites stored content in the current format with image paths
    /// normalized (`"x.jpg"` → `"images/x.jpg"`).
    ///
    /// Always re-encodes, which is what makes it double as the v1 → v2 upgrade
    /// for the three paths that call it: saving an edit, importing a backup and
    /// the one-time migration on launch.
    static func normalizeContent(_ json: String) -> String {
        var parts = ContentFlatten.parseContent(json)
        for i in parts.indices {
            if let src = parts[i].src {
                parts[i].src = normalizeSrcKey(src)
            }
        }
        return ContentFlatten.serializeContent(parts)
    }

    static func resolveImagePath(_ src: String) -> String {
        let key = normalizeSrcKey(src)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(key).path
    }

    static func collectImageSrcs(_ json: String) -> [String] {
        ContentFlatten.parseContent(json).compactMap { $0.src }
    }
}
