import Foundation
import Testing
@testable import MAPP

struct PlainTextFileTests {
    @Test func emptyTextIsAReadableEmptyPage() {
        #expect(PlainTextFile.decode(Data()) == .text(""))
    }

    @Test func textStaysLiteralIncludingWhitespaceAndUnicode() {
        let text = "# Not a heading\r\n\t* Not a list *  \r\n\r\n[not a link](https://example.com)\n<em>Not HTML</em>\nCafé 日本語 👋🏽\n"
        #expect(PlainTextFile.decode(Data(text.utf8)) == .text(text))
    }

    @Test func aLongUnbrokenLineIsNotTruncated() {
        let text = String(repeating: "abcdef", count: 10_000)
        #expect(PlainTextFile.decode(Data(text.utf8)) == .text(text))
    }

    @Test func unicodeSignaturesAreNotDisplayed() throws {
        let text = "Milk\r\n日本語 🐈\n"
        for (encoding, prefix) in [
            (String.Encoding.utf8, [0xEF, 0xBB, 0xBF]),
            (.utf16LittleEndian, [0xFF, 0xFE]), (.utf16BigEndian, [0xFE, 0xFF]),
            (.utf32LittleEndian, [0xFF, 0xFE, 0x00, 0x00]), (.utf32BigEndian, [0x00, 0x00, 0xFE, 0xFF])
        ] {
            let data = Data(prefix.map(UInt8.init)) + (try #require(text.data(using: encoding)))
            #expect(PlainTextFile.decode(data) == .text(text))
        }
    }

    @Test func invalidEncodingAndBinaryContentStayWithTheSystemPreview() {
        for data in [Data([0xFF, 0xAB]), Data([0xC3, 0x28]), Data([0xFF, 0xFE, 0x00]), Data("abc\0def".utf8)] {
            #expect(PlainTextFile.decode(data) == .unsupported)
        }
    }

    @Test func aReadFailureIsNotAnEmptyDocument() {
        let missing = URL.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(PlainTextFile.read(missing) == .unavailable)
    }

    @Test func readingPreservesTheFileAndNeverReturnsATruncatedPage() throws {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("# Literal\r\n  spaces\r\n".utf8)
        try original.write(to: url)
        #expect(PlainTextFile.read(url) == .text("# Literal\r\n  spaces\r\n"))
        #expect(try Data(contentsOf: url) == original)
        let large = Data(repeating: 65, count: PlainTextFile.byteLimit + 1)
        try large.write(to: url)
        #expect(PlainTextFile.read(url) == .unsupported)
        #expect(try Data(contentsOf: url) == large)
    }
}

struct PlainTextFilePageTests {
    @Test func longTextLeavesSwiftUIsTextForAViewThatLaysOutOnlyWhatShows() {
        #expect(!PlainTextFilePage.isLarge(String(repeating: "a", count: PlainTextFilePage.largeTextBytes)))
        #expect(PlainTextFilePage.isLarge(String(repeating: "a", count: PlainTextFilePage.largeTextBytes + 1)))
        #expect(PlainTextFilePage.isLarge(String(repeating: "é", count: PlainTextFilePage.largeTextBytes / 2 + 1)))
    }
}
