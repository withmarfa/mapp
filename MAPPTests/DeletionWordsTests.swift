import Testing
@testable import MAPP

/// The delete confirmations' titles and message read as sentences, with the plural worked out and no markup left.
@Suite struct DeletionWordsTests {
    @Test func purgeTitleAgreesWithTheCount() {
        #expect(DeletionWords.purgeTitle(count: 1) == "Delete 1 item immediately?")
        #expect(DeletionWords.purgeTitle(count: 3) == "Delete 3 items immediately?")
    }

    @Test func moveTitleAgreesWithTheCount() {
        #expect(DeletionWords.moveTitle(count: 1) == "Move 1 item to Recently Deleted?")
        #expect(DeletionWords.moveTitle(count: 3) == "Move 3 items to Recently Deleted?")
    }

    @Test func purgeMessageAgreesWithTheCount() {
        #expect(DeletionWords.purgeMessage(count: 1)
            == "It’s already in Recently Deleted. Deleting it now erases it permanently, and you can’t undo it.")
        #expect(DeletionWords.purgeMessage(count: 3)
            == "They’re already in Recently Deleted. Deleting them now erases them permanently, and you can’t undo it.")
    }
}
