import XCTest
import SwiftUI
@testable import JustDiary

/// Guards the on-disk content format (`edit_block.content_json`) and the
/// editor's load → parse invariant.
///
/// The UI tests can only sample the invariant through the real editor; these
/// run the codec itself at every text-size category, which is where a design
/// size drifting into a heading would show up.
final class ContentFormatTests: XCTestCase {

    /// Every persisted part kind, images included.
    private func storedFixture() -> [ContentPart] {
        [
            ContentPart(style: ContentPartStyle.title, runs: [TextRun(text: "标题")]),
            ContentPart(style: ContentPartStyle.heading, runs: [TextRun(text: "小标题")]),
            ContentPart(style: ContentPartStyle.body,
                        runs: [TextRun(text: "正文"), TextRun(text: "加粗", bold: true)],
                        align: "center"),
            ContentPart(style: ContentPartStyle.quote, runs: [TextRun(text: "引用", italic: true)]),
            ContentPart(style: ContentPartStyle.list, items: ["甲", "乙"]),
            ContentPart(style: ContentPartStyle.todo, items: ["做", "没做"], done: [true, false]),
            ContentPart(style: ContentPartStyle.image, src: "images/a.jpg", w: 300, h: 200)
        ]
    }

    /// The subset the editor can round-trip without an image on disk.
    private func editorFixture() -> [ContentPart] {
        [
            ContentPart(style: ContentPartStyle.title, runs: [TextRun(text: "标题")]),
            ContentPart(style: ContentPartStyle.heading, runs: [TextRun(text: "小标题")]),
            ContentPart(style: ContentPartStyle.body,
                        runs: [TextRun(text: "正文"),
                               TextRun(text: "加粗", bold: true),
                               TextRun(text: "斜体", italic: true),
                               TextRun(text: "下划线", underline: true),
                               TextRun(text: "删除线", strike: true)],
                        align: "center"),
            ContentPart(style: ContentPartStyle.quote, runs: [TextRun(text: "引用")]),
            ContentPart(style: ContentPartStyle.list, items: ["甲", "乙"]),
            ContentPart(style: ContentPartStyle.todo, items: ["做", "没做"], done: [true, false])
        ]
    }

    // MARK: - Storage format

    func testSerializedContentIsVersionedAndCarriesNoFontSize() throws {
        let parts = storedFixture()
        let json = ContentFlatten.serializeContent(parts)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])

        XCTAssertEqual(object["v"] as? Int, ContentDocument.currentVersion)
        XCTAssertEqual((object["parts"] as? [Any])?.count, parts.count)
        XCTAssertFalse(json.contains("\"size\""), "a run must not carry a font size any more")
        XCTAssertFalse(json.contains("\"type\""), "v1 wrote the block style under `type`")
        XCTAssertEqual(ContentFlatten.parseContent(json), parts, "round trip")
    }

    func testLegacyV1ContentIsUpgradedOnRead() {
        // Exactly the shape v1 wrote: a bare array, HTML-ish style names under
        // `type`, and a per-run `size`.
        let v1 = """
        [{"type":"h1","runs":[{"text":"标题","size":22,"bold":false}]},
         {"type":"h2","runs":[{"text":"小标题","size":18}]},
         {"type":"p","runs":[{"text":"正文","size":15,"bold":true}],"align":"center"},
         {"type":"quote","text":"引用"},
         {"type":"ul","items":["甲"]},
         {"type":"todo","items":["做"],"done":[true]},
         {"type":"img","src":"a.jpg","w":10,"h":20}]
        """
        let parts = ContentFlatten.parseContent(v1)
        XCTAssertEqual(parts.map(\.style),
                       [ContentPartStyle.title, ContentPartStyle.heading, ContentPartStyle.body,
                        ContentPartStyle.quote, ContentPartStyle.list, ContentPartStyle.todo,
                        ContentPartStyle.image])
        XCTAssertEqual(parts[0].runs?.map(\.text), ["标题"])
        XCTAssertNil(parts[0].runs?.first?.bold, "a legacy `false` reads as 'not set'")
        XCTAssertEqual(parts[2].runs?.first?.bold, true)
        XCTAssertEqual(parts[2].align, "center")
        XCTAssertEqual(parts[6].src, "a.jpg", "decoding alone does not touch paths")

        // Anything that rewrites content — a save, an import, the launch
        // migration — must emit v2, drop the legacy size and normalize the path.
        let upgraded = ImagePathUtil.normalizeContent(v1)
        XCTAssertTrue(upgraded.contains("\"v\":2"))
        XCTAssertFalse(upgraded.contains("\"size\""))
        var expected = parts
        expected[6].src = "images/a.jpg"
        XCTAssertEqual(ContentFlatten.parseContent(upgraded), expected)
    }

    func testOnlySetInlineStylesAreWritten() {
        let json = ContentFlatten.serializeContent([
            ContentPart(style: ContentPartStyle.body, runs: [TextRun(text: "普通"), TextRun(text: "粗", bold: true)])
        ])
        XCTAssertFalse(json.contains("\"bold\":false"), "an unset flag is omitted, not written as false: \(json)")
        XCTAssertEqual(json.components(separatedBy: "\"bold\":true").count, 2,
                       "exactly one run carries the flag: \(json)")
    }

    func testEmptyAndBrokenContentDecodesToNothing() {
        XCTAssertEqual(ContentFlatten.parseContent(""), [])
        XCTAssertEqual(ContentFlatten.parseContent("[]"), [])
        XCTAssertEqual(ContentFlatten.parseContent("null"), [])
        XCTAssertEqual(ContentFlatten.parseContent("{"), [])
    }

    // MARK: - Style mapping

    func testEveryEditorStyleMapsToItsPersistedNameAndBack() {
        for style in EditorBlockStyle.allCases {
            XCTAssertEqual(EditorBlockStyle(partStyle: style.partStyle), style)
        }
        // List, to-do and image have their own persisted names but are drawn with
        // the body attributes; an unknown future style must not crash.
        for other in [ContentPartStyle.list, ContentPartStyle.todo, ContentPartStyle.image, "monospaced"] {
            XCTAssertEqual(EditorBlockStyle(partStyle: other), .body)
        }
    }

    // MARK: - Editor round trip

    func testEditorRoundTripPreservesStylesAtEveryTextSize() {
        let original = editorFixture()
        for typeSize in DynamicTypeSize.allCases {
            let attributed = PartsCodec.attributedString(from: original, imageMaxWidth: 300,
                                                         typeSize: typeSize)
            let parsed = PartsCodec.parts(from: attributed, typeSize: typeSize)

            XCTAssertEqual(parsed.map(\.style), original.map(\.style), "block styles at \(typeSize)")
            XCTAssertEqual(parsed.map(\.align), original.map(\.align), "alignment at \(typeSize)")
            XCTAssertEqual(parsed.map(ContentFlatten.flattenPart),
                           original.map(ContentFlatten.flattenPart), "text at \(typeSize)")
            XCTAssertEqual(parsed.map { $0.runs?.map(\.bold) }, original.map { $0.runs?.map(\.bold) },
                           "bold at \(typeSize)")
            XCTAssertEqual(parsed.map { $0.runs?.map(\.italic) }, original.map { $0.runs?.map(\.italic) },
                           "italic at \(typeSize)")
            XCTAssertEqual(parsed.map { $0.runs?.map(\.underline) }, original.map { $0.runs?.map(\.underline) },
                           "underline at \(typeSize)")
            XCTAssertEqual(parsed.map { $0.runs?.map(\.strike) }, original.map { $0.runs?.map(\.strike) },
                           "strike at \(typeSize)")
        }
    }

    func testEditorRoundTripKeepsTodoStateAndItemGrouping() {
        let original = editorFixture()
        let attributed = PartsCodec.attributedString(from: original, typeSize: .large)
        let parsed = PartsCodec.parts(from: attributed, typeSize: .large)

        let lists = parsed.filter { $0.style == ContentPartStyle.list }
        let todos = parsed.filter { $0.style == ContentPartStyle.todo }
        XCTAssertEqual(lists.count, 1, "consecutive list items stay one part")
        XCTAssertEqual(lists.first?.items, ["甲", "乙"])
        XCTAssertEqual(todos.count, 1, "consecutive to-do items stay one part")
        XCTAssertEqual(todos.first?.items, ["做", "没做"])
        XCTAssertEqual(todos.first?.done, [true, false])
    }

    func testEditorRoundTripPersistsNoFontSize() {
        let attributed = PartsCodec.attributedString(from: editorFixture(), typeSize: .accessibility5)
        let parsed = PartsCodec.parts(from: attributed, typeSize: .accessibility5)
        let json = ContentFlatten.serializeContent(parsed)
        XCTAssertFalse(json.contains("\"size\""),
                       "the drawn size must never reach storage: \(json)")
    }
}
