import Foundation
import Testing
@testable import MarfaMac

/// Where an item opens (Settings > General > Open Items), and what the modal does with the window around it.
struct ItemOpeningTests {
    // MARK: The row menu

    @Test func theRowMenuOfDeletedItemsRecoversInsteadOfOrganizing() {
        let entries = RowMenuEntry.entries(opening: .modal, inBin: true)
        #expect(entries.contains(.recover) && !entries.contains(.favorite) && !entries.contains(.tag))
        #expect(entries.contains(.copyLink))
        #expect(entries.last == .delete)
    }
}
