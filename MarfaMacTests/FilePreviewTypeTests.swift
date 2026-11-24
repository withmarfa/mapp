import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

struct QuickLookFileTests {
    @Test func aTitleIsMadeSafeAsAFileName() {
        #expect(QuickLookFile.name(for: "a/b:c.txt", type: .plainText) == "a-b-c.txt")
        #expect(QuickLookFile.name(for: "..hidden", type: .plainText) == "hidden.txt")
        #expect(!QuickLookFile.name(for: "   ", type: .plainText).isEmpty)
    }

    @Test func theCopyHoldsTheSameBytesUnderTheNewNameAndGoesWhenRemoved() throws {
        let source = URL.temporaryDirectory.appending(path: "QuickLookFileTests-\(UUID().uuidString)")
        try Data("Milk".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let file = try #require(QuickLookFile.copy(of: source, titled: "Shopping list", as: .plainText))
        #expect(file.url.lastPathComponent == "Shopping list.txt")
        #expect(try Data(contentsOf: file.url) == Data("Milk".utf8))
        try Data("Eggs".utf8).write(to: file.url)
        #expect(try Data(contentsOf: source) == Data("Milk".utf8), "a change to the copy leaves the kept bytes alone")
        file.remove()
        #expect(!FileManager.default.fileExists(atPath: file.folder.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }
}
