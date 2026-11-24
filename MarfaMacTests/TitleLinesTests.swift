import Testing
@testable import MarfaMac

struct TitleLinesTests {
    @Test func theSettingIsResetWithTheOtherPageSettings() {
        #expect(PageKey.all.contains(PageKey.titleLines))
    }
}
