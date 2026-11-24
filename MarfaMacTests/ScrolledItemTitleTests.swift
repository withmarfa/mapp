import Testing
@testable import MarfaMac

struct ScrolledItemTitleTests {
    @Test func theToolbarSettingsAreResetWithTheOtherInterfaceSettings() {
        #expect(InterfaceKey.all.contains(InterfaceKey.showsScrolledTitle))
        #expect(InterfaceKey.all.contains(InterfaceKey.showsPageToolbarBackground))
    }
}
