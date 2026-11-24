import Foundation
import Testing
@testable import MarfaMac

struct TitleLinesTests {
    private func defaults() throws -> UserDefaults {
        let name = "TitleLinesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theSettingIsResetWithTheOtherPageSettings() {
        #expect(PageKey.all.contains(PageKey.titleLines))
    }
}
