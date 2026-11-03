import Foundation
import Testing
@testable import MAPP

struct TitleLinesTests {
    private func defaults() throws -> UserDefaults {
        let name = "TitleLinesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theChoicesAreTwoToFiveAndTwoIsTheStandard() {
        #expect(TitleLines.choices == [2, 3, 4, 5])
        #expect(TitleLines.standard == 2)
    }

    @Test func aStoredValueIsKeptOrBroughtIntoRange() throws {
        let defaults = try defaults()
        #expect(TitleLines.stored(in: defaults) == 2, "nothing stored")
        for lines in TitleLines.choices {
            defaults.set(lines, forKey: PageKey.titleLines)
            #expect(TitleLines.stored(in: defaults) == lines)
        }
        for (value, expected) in [(0, 2), (1, 2), (-4, 2), (6, 5), (400, 5)] {
            defaults.set(value, forKey: PageKey.titleLines)
            #expect(TitleLines.stored(in: defaults) == expected, "\(value)")
        }
        defaults.set("three", forKey: PageKey.titleLines)
        #expect(TitleLines.stored(in: defaults) == 2, "not a number")
    }

    @Test func theSettingIsResetWithTheOtherPageSettings() {
        #expect(PageKey.all.contains(PageKey.titleLines))
    }

    @Test func theHeaderCarriesTheSettingToThePage() throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("A very long title", modified: Date(timeIntervalSince1970: 1_800_000_000))])
        let id = library.items[0].id
        for lines in TitleLines.choices {
            let header = try #require(ItemPageHeader.header(of: id, in: library, drafts: DetailsPresentation(), titleLines: lines))
            #expect(header.titleLines == lines)
            let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(header)) as? [String: Any])
            #expect(json["titleLines"] as? Int == lines)
        }
    }
}
