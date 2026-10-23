import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

struct FilePreviewTypeTests {
    private let hashed = URL(filePath: "/cache/" + String(repeating: "ab", count: 32))

    @Test func aFileKeptUnderItsHashIsShownByTheTypeTheLibrarySays() {
        #expect(FileItemContent.type(of: hashed, contentType: .pdf) == .pdf)
        #expect(FileItemContent.type(of: hashed, contentType: .png).conforms(to: .image))
        #expect(FileItemContent.type(of: hashed, contentType: .plainText) == .plainText)
    }

    @Test func aFileWithNoKnownTypeIsShownByItsName() {
        #expect(FileItemContent.type(of: URL(filePath: "/folder/Brief.pdf"), contentType: nil) == .pdf)
        #expect(FileItemContent.type(of: URL(filePath: "/folder/Brief.pdf"), contentType: .data) == .pdf)
        #expect(FileItemContent.type(of: hashed, contentType: nil) == .data)
    }

    @Test func theTypeTheLibrarySaysWinsOverTheName() {
        #expect(FileItemContent.type(of: URL(filePath: "/folder/scan.bin"), contentType: .pdf) == .pdf)
    }
}

struct QuickLookFileTests {
    @Test func aTitleWithoutAnExtensionGetsOneThatFitsTheType() {
        #expect(QuickLookFile.name(for: "Shopping list", type: .plainText) == "Shopping list.txt")
        #expect(QuickLookFile.name(for: "Brief", type: .pdf) == "Brief.pdf")
    }

    @Test func aTitleWithAFittingExtensionIsKept() {
        #expect(QuickLookFile.name(for: "Shopping list.txt", type: .plainText) == "Shopping list.txt")
        #expect(QuickLookFile.name(for: "photo.jpeg", type: .jpeg) == "photo.jpeg")
    }

    @Test func anUnknownTypeLeavesTheTitleAlone() {
        #expect(QuickLookFile.name(for: "Archive", type: .data) == "Archive")
    }

    @Test func aTitleIsMadeSafeAsAFileName() {
        #expect(QuickLookFile.name(for: "a/b:c.txt", type: .plainText) == "a-b-c.txt")
        #expect(QuickLookFile.name(for: "..hidden", type: .plainText) == "hidden.txt")
        #expect(!QuickLookFile.name(for: "   ", type: .plainText).isEmpty)
    }

    @Test func theLinkHoldsTheSameBytesUnderTheNewNameAndGoesWhenRemoved() throws {
        let source = URL.temporaryDirectory.appending(path: "QuickLookFileTests-\(UUID().uuidString)")
        try Data("Milk".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let file = try #require(QuickLookFile.link(to: source, titled: "Shopping list", as: .plainText))
        #expect(file.url.lastPathComponent == "Shopping list.txt")
        #expect(try Data(contentsOf: file.url) == Data("Milk".utf8))
        file.remove()
        #expect(!FileManager.default.fileExists(atPath: file.folder.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }
}
