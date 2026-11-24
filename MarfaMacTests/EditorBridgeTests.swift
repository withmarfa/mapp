import Foundation
import Testing
@testable import MarfaMac

/// The editor bridge's one list, `editor/bridge-messages.json`, read from the source tree. The page's side reads it in
/// `editor/test/bridge-messages.test.ts`, so a message or a function added, renamed or dropped on one side fails a test.
/// The decoding stays hand-written; these tests only check that it reads what the list says the page sends.
@Suite struct EditorBridgeTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    private static func list() throws -> [String: Any] {
        let data = Data(try source("editor/bridge-messages.json").utf8)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func entries(_ name: String) throws -> [String: [String: Any]] {
        try #require(list()[name] as? [String: [String: Any]])
    }

    /// The names in `case "a", "b":` lines at the indentation of a decoder's own `switch`, between `start` and `end`.
    private static func decoded(in path: String, from start: String, to end: String) throws -> Set<String> {
        let text = try source(path)
        let body = try #require(text.components(separatedBy: start).dropFirst().first?.components(separatedBy: end).first)
        let lines = body.split(separator: "\n").filter { $0.hasPrefix("        case \"") && $0.hasSuffix(":") }
        return Set(lines.flatMap { $0.split(separator: "\"").enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) } })
    }

    /// The page functions a source file names: `call("name"`, `as: "name"` and `window.editor.name(`, the first two
    /// with the name on the next line as well.
    private static func pageFunctions(in text: String) -> Set<String> {
        guard let pattern = try? Regex(#"(?:\bcall\(\s*|\bas:\s*)"(\w+)"|window\.editor\.(\w+)\("#) else { return [] }
        return Set(text.matches(of: pattern).compactMap { ($0.output[1].substring ?? $0.output[2].substring).map(String.init) })
    }

    @Test func aCallWithItsNameOnTheNextLineIsFound() {
        let text = "call(\n    \"split\",\n    in: x)\nrun(as:\n \"merge\")\nwindow.editor.join("
        #expect(Self.pageFunctions(in: text) == ["split", "merge", "join"])
    }

    @Test func everyMessageTheListNamesDecodes() throws {
        let host = try Self.entries("host")
        #expect(!host.isEmpty)
        for (type, fields) in host {
            let body = fields.merging(["type": type]) { _, new in new }
            #expect(EditorMessage(body: body) != nil, "\(type) did not decode")
        }
    }

    @Test func everyMessageTheDecoderReadsIsOnTheList() throws {
        let read = try Self.decoded(in: "MarfaMac/Editor/EditorMessages.swift", from: "init?(body: Any)", to: "\n/// The link a menu")
        #expect(read == Set(try Self.entries("host").keys))
    }

    @Test func theEmbedRequestTheListNamesDecodesAndNeedsEachField() throws {
        let embeds = try Self.entries("embeds")
        #expect(Set(embeds.keys) == ["request"])
        let fields = try #require(embeds["request"])
        #expect(EmbedReference.request(fields) != nil, "the embed request did not decode")
        for key in fields.keys {
            #expect(EmbedReference.request(fields.filter { $0.key != key }) == nil, "\(key) is not required")
        }
    }

    @Test func everyItemRequestTheListNamesDecodes() throws {
        let items = try Self.entries("items")
        #expect(!items.isEmpty)
        for (type, fields) in items {
            #expect(ItemRequest(body: fields.merging(["type": type]) { _, new in new }) != nil, "\(type) did not decode")
        }
        let read = try Self.decoded(in: "MarfaMac/Editor/ItemRequests.swift", from: "init?(body: Any)", to: "\n/// Answers")
        #expect(read == Set(items.keys))
    }

    @Test func everyPictureRequestAndAskTheListNamesDecodes() throws {
        let pictures = try Self.entries("pictures")
        #expect(Set(pictures.keys) == ["load"])
        let asks = try #require(Self.list()["pictureAsks"] as? [String])
        #expect(Set(asks) == Set(PictureAsk.allCases.map(\.rawValue)))
        for ask in asks {
            let body = (pictures["load"] ?? [:]).merging(["type": "load", "ask": ask]) { _, new in new }
            #expect(PictureRequest(body: body)?.ask.rawValue == ask, "\(ask) did not decode")
        }
    }

    @Test func everyPageFunctionTheAppCallsIsOnTheList() throws {
        let editor = Self.root.appending(path: "MarfaMac/Editor")
        let files = try FileManager.default.contentsOfDirectory(at: editor, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        var called: Set<String> = []
        for file in files { called.formUnion(Self.pageFunctions(in: try String(contentsOf: file, encoding: .utf8))) }
        let listed = Set(try #require(Self.list()["pageFunctions"] as? [String]))
        #expect(!called.isEmpty)
        #expect(called.subtracting(listed).isEmpty, "the page does not offer \(called.subtracting(listed).sorted())")
    }
}
