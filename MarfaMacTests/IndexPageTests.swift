import Foundation
import Testing
@testable import MarfaMac

/// The Items page's New row (which types it holds, in what order) and what an index page shows of its tools and filters.
@MainActor
@Suite(.hangLimit) struct IndexPageTests {
    private func types(_ ids: String...) -> [ItemTypeOption] {
        ids.map { ItemTypeOption(id: TypeID($0), label: $0, icon: nil) }
    }

    private var offered: [ItemTypeOption] {
        types("core.note", "core.task", "core.bookmark", "core.event", "core.entity.person", "core.entity.place", "core.table", "core.file")
    }

    // MARK: New row

    @Test func aKeptListIsShownInItsOrderAndAnEmptyOneStaysEmpty() {
        #expect(NewRowTypes.shown(offered, kept: "core.event,core.note").map(\.id.rawValue) == ["core.event", "core.note"])
        #expect(NewRowTypes.shown(offered, kept: "").isEmpty)
        // A type the library no longer has, and a repeat, are skipped.
        #expect(NewRowTypes.shown(offered, kept: "gone.type,core.note,core.note").map(\.id.rawValue) == ["core.note"])
    }

    @Test func tickingAddsAtTheEndAndUntickingRemoves() {
        let row = NewRowTypes.shown(offered, kept: "core.note,core.task")
        #expect(NewRowTypes.toggled("core.event", row: row) == "core.note,core.task,core.event")
        #expect(NewRowTypes.toggled("core.note", row: row) == "core.task")
    }

    @Test func aFirstChangeKeepsTheStartingSevenLessWhatItRemoves() {
        let row = NewRowTypes.shown(offered, kept: nil)
        #expect(NewRowTypes.toggled("core.task", row: row) == "core.note,core.table,core.bookmark,core.event,core.entity.person,core.entity.place")
    }

    @Test func draggingMovesTheEntryToTheDropPlace() {
        let row = NewRowTypes.shown(offered, kept: "core.note,core.task,core.event")
        #expect(NewRowTypes.moved(row, from: IndexSet(integer: 0), to: 3) == "core.task,core.event,core.note")
        #expect(NewRowTypes.moved(row, from: IndexSet(integer: 2), to: 0) == "core.event,core.note,core.task")
    }

    @Test func theQuickAddTilesAreOffUntilTheSettingIsTurnedOn() throws {
        let suite = "IndexPageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!defaults.bool(forKey: ListKey.showsQuickAdd))
        defaults.set(true, forKey: ListKey.showsQuickAdd)
        #expect(defaults.bool(forKey: ListKey.showsQuickAdd))
        MacSettings.reset(in: defaults)
        #expect(!defaults.bool(forKey: ListKey.showsQuickAdd))
    }

    @Test func theQuickAddSettingSyncsWithTheListsField() {
        #expect(PreferencesMap.syncedKeys.contains(ListKey.showsQuickAdd))
        #expect(!PreferencesMap.staysOnMac.contains(ListKey.showsQuickAdd))
        #expect(MacSettings.keys.contains(ListKey.showsQuickAdd))
    }

}
