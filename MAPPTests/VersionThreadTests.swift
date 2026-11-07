import Foundation
import Testing
@testable import MAPP

/// A version of an item as the history keeps it.
private func version(
    _ number: Int, body: String? = "Text", title: String? = "Title", type: TypeID = TypeChangeFixture.note,
    extra: [String: PropertyValue] = [:], replaced: Date? = nil, writer: ItemSnapshot.Writer? = nil
) -> ItemSnapshot {
    var properties = extra
    if let body { properties["body"] = .string(body) }
    if let title { properties["title"] = .string(title) }
    return ItemSnapshot(id: "v\(number)", version: number, type: type, properties: properties, replaced: replaced, writer: writer)
}

private func item(
    version: Int64, title: String = "Title", type: TypeID = TypeChangeFixture.note, created: Date, modified: Date,
    extra: [Property] = []
) -> Item {
    Item(
        id: ItemID("launch"), type: type, title: title, titleRule: .property("title"),
        properties: [Property(key: "title", value: .string(title))] + extra, version: ItemVersion(version), created: created,
        modified: modified)
}

private func calendar(_ identifier: String = "UTC", firstWeekday: Int = 1) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: identifier)!
    calendar.firstWeekday = firstWeekday
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, in calendar: Calendar = calendar()) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private let english = Locale(identifier: "en_US")

/// How the thread is put together from the versions the server kept and the item as it stands.
@Suite struct VersionThreadTests {
    private let catalogue = TypeChangeFixture.catalogue

    @Test func theThreadIsNewestFirstAndEachVersionIsSavedWhenItsPredecessorWasReplaced() {
        let created = date(2026, 10, 1), second = date(2026, 10, 5), third = date(2026, 10, 9)
        let current = item(version: 3, created: created, modified: third)
        let entries = VersionThread.entries(
            snapshots: [version(2, replaced: third), version(1, replaced: second)], current: current, currentText: "Now", in: catalogue)
        #expect(entries.map(\.version) == [3, 2, 1])
        #expect(entries.map(\.id) == ["current", "v2", "v1"])
        #expect(entries.map(\.written) == [third, second, created])
        #expect(entries.allSatisfy { !$0.writtenIsApproximate })
        #expect(entries.first?.isCurrent == true)
        // Nothing records who wrote the version the item holds.
        #expect(entries.first?.writer == nil)
    }

    @Test func aVersionAfterAThinnedGapIsSavedAtAboutTheNearestTimeTheHistoryGives() {
        let created = date(2026, 10, 1), later = date(2026, 10, 20)
        let current = item(version: 9, created: created, modified: later)
        let entries = VersionThread.entries(
            snapshots: [version(3, replaced: date(2026, 10, 7)), version(7, replaced: date(2026, 10, 12))],
            current: current, currentText: nil, in: catalogue)
        let byVersion = Dictionary(uniqueKeysWithValues: entries.map { ($0.version, $0) })
        // Version 7 follows version 3 with versions between that the server dropped.
        #expect(byVersion[7]?.written == date(2026, 10, 7))
        #expect(byVersion[7]?.writtenIsApproximate == true)
        // The oldest version read is not the first, so there is no creation time to give it.
        #expect(byVersion[3]?.writtenIsApproximate == true)
        #expect(byVersion[9]?.writtenIsApproximate == false)
    }

    @Test func aVersionWhoseSuccessorHasNoTimeIsNotGivenOne() {
        let current = item(version: 2, created: date(2026, 10, 1), modified: date(2026, 10, 2))
        let entries = VersionThread.entries(
            snapshots: [version(1), version(2)], current: current, currentText: nil, in: catalogue)
        let two = entries.first { $0.id == "v2" }
        #expect(two?.written == nil)
        #expect(two?.writtenIsApproximate == false)
    }

    @Test func theWriterOfAVersionStaysWithIt() {
        let writer = ItemSnapshot.Writer(kind: .key, name: "Raycast")
        let current = item(version: 2, created: date(2026, 10, 1), modified: date(2026, 10, 2))
        let entries = VersionThread.entries(snapshots: [version(1, writer: writer)], current: current, currentText: nil, in: catalogue)
        #expect(entries.last?.writer == writer)
        #expect(writer.displayName == "Raycast")
        #expect(ItemSnapshot.Writer(kind: .browser, name: "").displayName == String(localized: "Browser"))
    }

    // MARK: Blocks

    private let ids = ["a", "b", "c", "d", "e", "f"]

    private func blocks(_ dates: [Date?], now: Date, calendar: Calendar) -> [(VersionBlockKind, [Int])] {
        VersionBlocks.group(Array(dates.enumerated()), date: { $0.element }, now: now, calendar: calendar)
            .map { ($0.kind, $0.elements.map(\.offset)) }
    }

    @Test func versionsFallInThisWeekLastWeekAndThenTheirMonths() {
        let c = calendar()
        let now = date(2026, 11, 7, 12, in: c)
        let result = blocks(
            [date(2026, 11, 7, 9, in: c), date(2026, 11, 2, in: c), date(2026, 10, 28, in: c), date(2026, 10, 20, in: c),
             date(2026, 10, 3, in: c), date(2025, 12, 31, in: c)],
            now: now, calendar: c)
        #expect(result.map(\.0) == [.thisWeek, .lastWeek, .month(year: 2026, month: 10), .month(year: 2025, month: 12)])
        #expect(result.map(\.1) == [[0, 1], [2], [3, 4], [5]])
    }

    @Test func theFirstDayOfTheWeekIsThePersonsOwn() {
        // Sunday 1 November is the first day of this week for a Sunday start and the last of the one before for a Monday start.
        let sunday = date(2026, 11, 1, 10)
        let now = date(2026, 11, 7, 12)
        #expect(blocks([sunday], now: now, calendar: calendar(firstWeekday: 1)).map(\.0) == [.thisWeek])
        #expect(blocks([sunday], now: now, calendar: calendar(firstWeekday: 2)).map(\.0) == [.lastWeek])
    }

    @Test func aBlockEndsAtMidnightAndTheNextDayStartsAgain() {
        let c = calendar(firstWeekday: 2)
        // Sunday night is the end of the week before Monday begins the next.
        let sunday = date(2026, 11, 8, 23, 59, in: c)
        let monday = date(2026, 11, 9, 0, 1, in: c)
        #expect(blocks([sunday], now: sunday, calendar: c).map(\.0) == [.thisWeek])
        #expect(blocks([sunday], now: monday, calendar: c).map(\.0) == [.lastWeek])
        #expect(blocks([date(2026, 11, 2, 0, 0, in: c)], now: monday, calendar: c).map(\.0) == [.lastWeek])
    }

    @Test func theSameInstantFallsInTheBlockOfThePersonsTimeZone() {
        let instant = Date(timeIntervalSince1970: 1_793_493_000) // 1 November 2026, 00:30 UTC
        let now = date(2026, 11, 7, 12)
        // In Los Angeles it is still the evening of Saturday 31 October, in the week before.
        #expect(blocks([instant], now: now, calendar: calendar("UTC")).map(\.0) == [.thisWeek])
        #expect(blocks([instant], now: now, calendar: calendar("America/Los_Angeles")).map(\.0) == [.lastWeek])
    }

    @Test func aVersionWithNoDateStaysWithTheOneBeforeAndOneFromTheFutureIsThisWeek() {
        let c = calendar()
        let now = date(2026, 11, 7, 12, in: c)
        let result = blocks([date(2026, 11, 20, in: c), nil, date(2026, 9, 3, in: c), nil], now: now, calendar: c)
        #expect(result.map(\.0) == [.thisWeek, .month(year: 2026, month: 9)])
        #expect(result.map(\.1) == [[0, 1], [2, 3]])
    }

    @Test func monthsNameTheYearOnlyWhenItIsNotThisOne() {
        let c = calendar()
        let now = date(2026, 11, 7, in: c)
        #expect(VersionBlocks.title(of: .month(year: 2026, month: 10), now: now, calendar: c, locale: english) == "October")
        #expect(VersionBlocks.title(of: .month(year: 2025, month: 12), now: now, calendar: c, locale: english) == "December 2025")
        #expect(VersionBlocks.title(of: .thisWeek, now: now, calendar: c, locale: english) == String(localized: "This Week"))
        #expect(VersionBlocks.title(of: .lastWeek, now: now, calendar: c, locale: english) == String(localized: "Last Week"))
    }

    @Test func aVersionsTimeIsThePersonsDayAndClockTime() {
        let c = calendar()
        let now = date(2026, 11, 7, 15, in: c)
        let today = VersionBlocks.when(date(2026, 11, 7, 9, 12, in: c), format: .automatic, now: now, calendar: c, locale: english)
        #expect(today == "\(String(localized: "Today")), 9:12\u{202F}AM")
        // A format that spells the date out is used whole.
        let long = VersionBlocks.when(date(2026, 10, 29, 15, 15, in: c), format: .long, now: now, calendar: c, locale: english)
        #expect(long.contains("2026"))
    }

    @Test func theListGroupsAndSaysWhetherTheHistoryWasReadToItsEnd() {
        let c = calendar()
        let current = item(version: 3, created: date(2026, 10, 1, in: c), modified: date(2026, 11, 6, in: c))
        let snapshots = [version(2, replaced: date(2026, 11, 6, in: c)), version(1, replaced: date(2026, 10, 3, in: c))]
        let whole = VersionList(snapshots: snapshots, current: current, currentText: "Now", isComplete: true, in: catalogue)
        #expect(whole.blocks(now: date(2026, 11, 7, in: c), calendar: c).map(\.kind) == [.thisWeek, .month(year: 2026, month: 10)])
        // The item now is compared with the version just before it only once that version is known to be the one before.
        #expect(whole.older(than: whole.entries[0])?.id == "v2")
        let partial = VersionList(snapshots: snapshots, current: current, currentText: "Now", isComplete: false, in: catalogue)
        #expect(partial.older(than: partial.entries[0]) == nil)
        #expect(partial.older(than: partial.entries[1])?.id == "v1")
        #expect(partial.older(than: partial.entries[2]) == nil)
    }

    @Test func theArrowKeysMoveOneVersionAndStopAtTheEnds() {
        let current = item(version: 3, created: date(2026, 10, 1), modified: date(2026, 11, 6))
        let list = VersionList(snapshots: [version(1), version(2)], current: current, currentText: nil, isComplete: true, in: catalogue)
        #expect(list.neighbour(of: "current", step: 1)?.id == "v2")
        #expect(list.neighbour(of: "v2", step: -1)?.id == "current")
        #expect(list.neighbour(of: "current", step: -1) == nil)
        #expect(list.neighbour(of: "v1", step: 1) == nil)
        #expect(list.neighbour(of: nil, step: 1)?.id == "current")
    }

    // MARK: What a version changed

    private func content(
        _ version: ItemSnapshot, current: Bool = false
    ) -> VersionContent { version.content(in: catalogue) }

    @Test func aChangeIsPutInAWordOrTwo() {
        let task = TypeChangeFixture.task
        let before = content(version(1, body: "One", title: "Plan", type: task, extra: ["status": .string("pending")]))
        func summary(_ after: ItemSnapshot, creation: Bool = false) -> String {
            VersionDelta.between(before, content(after), in: catalogue).summary(isCreation: creation)
        }
        #expect(summary(version(2, body: "Two", title: "Plan", type: task, extra: ["status": .string("pending")])) == String(localized: "\(String(localized: "Text")) changed"))
        #expect(summary(version(2, body: "One", title: "Plan", type: task, extra: ["status": .string("done")])) == String(localized: "Status set to Done"))
        #expect(summary(version(2, body: "One", title: "Plan", type: task)) == String(localized: "Status cleared"))
        #expect(summary(version(2, body: "One", title: "Plan", type: task, extra: ["status": .string("pending")])) == String(localized: "Changed"))
        #expect(summary(version(1, body: "One"), creation: true) == String(localized: "Created"))
    }

    @Test func severalChangesAreListedAndManyAreCounted() {
        let task = TypeChangeFixture.task
        let before = content(version(1, body: "One", title: "A", type: task, extra: ["status": .string("pending"), "priority": .number(1)]))
        let two = VersionDelta.between(before, content(version(2, body: "Two", title: "B", type: task, extra: ["status": .string("pending"), "priority": .number(1)])), in: catalogue)
        #expect(two.titleChanged && two.textChanged && two.fields.isEmpty)
        #expect(two.summary(isCreation: false).contains(String(localized: "Title")))
        #expect(two.summary(isCreation: false).contains(String(localized: "Text")))
        let many = VersionDelta.between(before, content(version(2, body: "Two", title: "B", type: task, extra: ["status": .string("done"), "priority": .number(2)])), in: catalogue)
        #expect(many.summary(isCreation: false) == String(localized: "\(4) things changed"))
    }

    @Test func aTypeChangeIsOneOfTheChanges() {
        let before = content(version(1))
        let after = content(version(2, type: TypeChangeFixture.task))
        let delta = VersionDelta.between(before, after, in: catalogue)
        #expect(delta.typeChanged)
        #expect(!delta.isEmpty)
    }

    @Test func aTypeWithNoTextIsNeverReportedAsChangingIt() {
        let entity = TypeChangeFixture.entity
        let before = content(version(1, body: nil, title: nil, type: entity, extra: ["name": .string("Ada")]))
        let after = content(version(2, body: nil, title: nil, type: entity, extra: ["name": .string("Grace")]))
        let delta = VersionDelta.between(before, after, in: catalogue)
        #expect(!delta.textChanged)
        // The field that titles the type is the title, not a field of its own.
        #expect(delta.titleChanged)
        #expect(delta.fields.isEmpty)
    }

    @Test func anOldestVersionOfTheThreadIsCreatedOnlyWhenItIsTheFirst() {
        let current = item(version: 5, created: date(2026, 10, 1), modified: date(2026, 11, 6))
        let list = VersionList(snapshots: [version(1), version(4, body: "Four")], current: current, currentText: "Now", isComplete: true, in: catalogue)
        #expect(list.summary(of: list.entry("v1")!, in: catalogue) == String(localized: "Created"))
        #expect(list.summary(of: list.entry("v4")!, in: catalogue) == String(localized: "\(String(localized: "Text")) changed"))
    }

    // MARK: Facts

    @Test func theFactsSayWhoWroteTheVersionWhatItChangedAndWhatChangedSince() {
        let writer = ItemSnapshot.Writer(kind: .app, name: "MAPP")
        let current = item(version: 4, title: "Plan now", created: date(2026, 10, 1), modified: date(2026, 11, 6))
        let list = VersionList(
            snapshots: [
                version(1, body: "one two three", title: "Plan", replaced: date(2026, 10, 2)),
                version(2, body: "one two four", title: "Plan", replaced: date(2026, 10, 3), writer: writer),
                version(3, body: "one two four", title: "Plan now", replaced: date(2026, 11, 6)),
            ],
            current: current, currentText: "one five four", isComplete: true, in: catalogue)
        let entry = list.entry("v2")!
        let facts = VersionFacts.make(for: entry, after: list.older(than: entry), current: list.current!, in: catalogue, dateFormat: .automatic)
        #expect(facts.writtenBy == "MAPP")
        #expect(facts.version == 2 && facts.latest == 4)
        #expect(facts.saved == date(2026, 10, 2))
        #expect(!facts.savedIsApproximate)
        #expect(facts.changedHere.map(\.id) == ["#text"])
        // The title and the text changed since, and nothing else the history keeps.
        #expect(facts.changedSince.map(\.id) == ["#title", "#text"])
    }

    @Test func theItemAsItIsHasNothingChangedSinceAndNoKnownWriter() {
        let current = item(version: 2, created: date(2026, 10, 1), modified: date(2026, 11, 6))
        let list = VersionList(snapshots: [version(1, replaced: date(2026, 11, 6))], current: current, currentText: "Text", isComplete: true, in: catalogue)
        let facts = VersionFacts.make(for: list.current!, after: list.older(than: list.current!), current: list.current!, in: catalogue, dateFormat: .automatic)
        #expect(facts.isCurrent)
        #expect(facts.writtenBy == nil)
        #expect(facts.changedSince.isEmpty)
    }

    @Test func aFieldsValueIsShownAsThePersonReadsIt() {
        let task = TypeChangeFixture.task
        let current = item(version: 2, type: task, created: date(2026, 10, 1), modified: date(2026, 11, 6), extra: [Property(key: "status", value: .string("done"))])
        let list = VersionList(
            snapshots: [version(1, body: "Text", title: "Title", type: task, extra: ["status": .string("pending")], replaced: date(2026, 11, 6))],
            current: current, currentText: "Text", isComplete: true, in: catalogue)
        let entry = list.entry("v1")!
        let facts = VersionFacts.make(for: entry, after: nil, current: list.current!, in: catalogue, dateFormat: .automatic)
        #expect(facts.changedSince.map(\.label) == ["Status"])
        #expect(facts.changedSince.map(\.value) == [ItemTypeInfo.Field.label(ofOption: "done")])
    }

    @Test func aVersionsPinsAreOnlyThoseItHolds() {
        let task = TypeChangeFixture.task
        let content = version(1, body: "Text", title: "Title", type: task, extra: ["status": .string("done")]).content(in: catalogue)
        let placement = PagePlacements().placement(of: task, in: catalogue)
        let rows = content.pins(saved: date(2026, 10, 2), placement: placement, in: catalogue, format: .automatic)
        // The tags, the parent and the source are not kept with a version, so they are never shown from the item as it is now.
        #expect(rows.allSatisfy { ![PagePlacement.tags, PagePlacement.source, PagePlacement.linkedFrom, PagePlacement.parent].contains($0.id) })
    }

    @Test func noFactShowsAPluralAsItsMarkup() {
        for (added, removed) in [(0, 0), (1, 0), (0, 1), (1, 1), (3, 2)] {
            #expect(!VersionFacts.describe(additions: added, removals: removed).contains("^["))
        }
        #expect(VersionFacts.describe(additions: 1, removals: 0) == "1 addition")
        #expect(VersionFacts.describe(additions: 3, removals: 0) == "3 additions")
        #expect(VersionFacts.describe(additions: 1, removals: 2) == "1 addition, 2 removals")

        let current = item(version: 4, created: date(2026, 10, 1), modified: date(2026, 11, 6))
        let list = VersionList(
            snapshots: [
                version(1, body: "one two three", title: "Plan", replaced: date(2026, 10, 2)),
                version(2, body: "one two four", title: "Plan", replaced: date(2026, 10, 3)),
                version(3, body: "one two four", title: "Plan", replaced: date(2026, 11, 6)),
            ],
            current: current, currentText: "one five four", isComplete: true, in: catalogue)
        for entry in list.entries {
            let facts = VersionFacts.make(for: entry, after: list.older(than: entry), current: list.current!, in: catalogue, dateFormat: .automatic)
            for row in facts.changedHere + facts.changedSince { #expect(!row.value.contains("^["), "\(row.label): \(row.value)") }
        }
        let first = list.entry("v2")!
        let facts = VersionFacts.make(for: first, after: list.older(than: first), current: list.current!, in: catalogue, dateFormat: .automatic)
        #expect(facts.changedHere.first?.value == "1 addition, 1 removal")
        #expect(facts.changedSince.first(where: { $0.id == "#text" })?.value == "1 change")
    }

    @Test func aPluralReadsAsAWordInTheModelsOwnStrings() {
        #expect(AttributedString(localized: "^[\(1) version](inflect: true)").text == "1 version")
        #expect(AttributedString(localized: "^[\(3) version](inflect: true)").text == "3 versions")
    }
}

/// The words that differ between two versions of a text, and the page they are read on.
@Suite struct VersionDiffTests {
    private func joined(_ pieces: [DiffPiece], skipping skipped: DiffChange) -> String {
        pieces.filter { $0.change != skipped }.map(\.text).joined()
    }

    @Test func aChangedWordIsRemovedAndAddedWhereItStood() {
        let pieces = WordDiff.pieces(from: "the cat sat down", to: "the dog sat down")
        #expect(pieces.map(\.change) == [.same, .removed, .added, .same])
        #expect(pieces.first { $0.change == .removed }?.text == "cat")
        #expect(pieces.first { $0.change == .added }?.text == "dog")
        #expect(joined(pieces, skipping: .removed) == "the dog sat down")
        #expect(joined(pieces, skipping: .added) == "the cat sat down")
        #expect(WordDiff.changes(pieces) == 1)
        let counts = WordDiff.counts(pieces)
        #expect(counts.added == 1 && counts.removed == 1)
    }

    @Test func identicalTextIsOnePieceAndEmptyTextIsNone() {
        #expect(WordDiff.pieces(from: "same", to: "same") == [DiffPiece(text: "same", change: .same)])
        #expect(WordDiff.pieces(from: "", to: "").isEmpty)
        let fresh = WordDiff.pieces(from: "", to: "new text")
        #expect(fresh.filter { $0.change == .added }.map(\.text) == ["new text"])
    }

    @Test func textAddedAtTheEndsAndRemovedWholeIsTold() {
        let grown = WordDiff.pieces(from: "middle", to: "start middle end")
        #expect(joined(grown, skipping: .removed) == "start middle end")
        #expect(WordDiff.counts(grown).removed == 0)
        let gone = WordDiff.pieces(from: "start middle end", to: "")
        #expect(joined(gone, skipping: .added) == "start middle end")
        #expect(gone.allSatisfy { $0.change == .removed })
    }

    @Test func spacesAloneAreNotCountedAsChanges() {
        let pieces = WordDiff.pieces(from: "a b", to: "a  b")
        #expect(WordDiff.changes(pieces) == 0)
        #expect(WordDiff.counts(pieces) == (added: 0, removed: 0))
    }

    @Test func aVeryLongTextIsComparedByLinesAndStillJoinsBackToBothVersions() {
        let old = (0..<3_000).map { "line \($0) with some words in it" }.joined(separator: "\n")
        var lines = old.components(separatedBy: "\n")
        lines[1_500] = "a different line"
        let new = lines.joined(separator: "\n")
        // More pairs of words than the exact comparison attempts.
        #expect(old.split(separator: " ").count * new.split(separator: " ").count > 4_000_000)
        let pieces = WordDiff.pieces(from: old, to: new)
        #expect(joined(pieces, skipping: .removed) == new)
        #expect(joined(pieces, skipping: .added) == old)
        #expect(WordDiff.changes(pieces) == 1)
    }

    @Test func aPageReadsLinesAndTheirKinds() {
        let text = "# Plan\n- one\n  - nested\n1. first\n> quoted\n---\n\nplain **bold** and `code`\n"
        let lines = ReadableText.lines([DiffPiece(text: text, change: .same)])
        #expect(lines.map(\.kind) == [
            .heading(level: 1), .bullet(depth: 0, number: nil), .bullet(depth: 1, number: nil), .bullet(depth: 0, number: 1),
            .quote, .rule, .blank, .paragraph,
        ])
        #expect(lines[0].spans.map(\.text) == ["Plan"])
        let last = lines[7].spans
        #expect(last.map(\.text) == ["plain ", "bold", " and ", "code"])
        #expect(last[1].bold && last[3].code)
    }

    @Test func aMarkWithNoPartnerStaysAsTyped() {
        let lines = ReadableText.lines([DiffPiece(text: "2 * 3 and **open", change: .same)])
        #expect(lines.first?.spans.map(\.text).joined() == "2 * 3 and **open")
        let emphasis = ReadableText.lines([DiffPiece(text: "an *italic* and _also_ with snake_case", change: .same)])
        #expect(emphasis.first?.spans.map(\.text) == ["an ", "italic", " and ", "also", " with snake_case"])
        #expect(emphasis.first?.spans[1].italic == true && emphasis.first?.spans[3].italic == true)
    }

    @Test func addedAndRemovedWordsKeepTheirMarksThroughTheReading() {
        let pieces = WordDiff.pieces(from: "# Old title\nkeep this", to: "# New title\nkeep this")
        let lines = ReadableText.lines(pieces).filter { $0.kind != .blank }
        let marks = lines.flatMap(\.spans).filter { $0.change != .same }
        #expect(marks.contains { $0.change == .removed && $0.text.contains("Old") })
        #expect(marks.contains { $0.change == .added && $0.text.contains("New") })
        #expect(lines.last?.spans.allSatisfy { $0.change == .same } == true)
    }

    @Test func aTableIsReadAsRowsOfCells() {
        let text = "Before\n\n| Thing | Value |\n|:--|--:|\n| **Cat** | 3 |\n| Dog | `a|b` |\n\nAfter"
        let lines = ReadableText.lines([DiffPiece(text: text, change: .same)])
        guard case .table(let table)? = lines.first(where: { if case .table = $0.kind { true } else { false } })?.kind else {
            Issue.record("no table read")
            return
        }
        #expect(table.alignments == [.leading, .trailing])
        #expect(table.header.map { $0.map(\.text).joined() } == ["Thing", "Value"])
        #expect(table.rows.count == 2)
        #expect(table.rows[0][0].first?.bold == true && table.rows[0][0].first?.text == "Cat")
        #expect(table.rows[1][1].map(\.text).joined() == "a|b", "a bar inside code is not a cell edge")
        #expect(lines.map(\.kind).filter { $0 == .paragraph }.count == 2, "the lines around the table stay as they were")
        #expect(!lines.contains { $0.spans.contains { $0.text.contains("|") } })
    }

    @Test func aLineWithABarAndNoSeparatorIsNotATable() {
        let lines = ReadableText.lines([DiffPiece(text: "a | b\nplain\n", change: .same)])
        #expect(lines.map(\.kind) == [.paragraph, .paragraph])
        let single = ReadableText.lines([DiffPiece(text: "Title |\n---\n", change: .same)])
        #expect(!single.contains { if case .table = $0.kind { true } else { false } })
    }

    @Test func aTableRowChangedInTheVersionKeepsItsMarksInItsCells() {
        let pieces = WordDiff.pieces(from: "| A | B |\n|---|---|\n| one | two |\n", to: "| A | B |\n|---|---|\n| one | three |\n")
        let lines = ReadableText.lines(pieces)
        guard case .table(let table)? = lines.first?.kind else {
            Issue.record("no table read")
            return
        }
        let cells = table.rows.flatMap { $0 }.flatMap { $0 }
        #expect(cells.contains { $0.change == .removed && $0.text == "two" })
        #expect(cells.contains { $0.change == .added && $0.text == "three" })
    }

    @Test func aWikiLinkShowsItsLabelAndIsNotFollowed() {
        let lines = ReadableText.lines([DiffPiece(text: "See [[Plan]] and [[abc-123|the plan]] or [[open", change: .same)])
        let spans = lines[0].spans
        #expect(spans.map(\.text) == ["See ", "Plan", " and ", "the plan", " or [[open"])
        #expect(spans.map(\.wikiLink) == [false, true, false, true, false])
        #expect(spans.allSatisfy { $0.link == nil })
    }

    @Test func aWikiLinkKeepsTheMarksOfWhatItShows() {
        let pieces = WordDiff.pieces(from: "Read [[Old]] now", to: "Read [[New]] now")
        let spans = ReadableText.lines(pieces).flatMap(\.spans)
        #expect(spans.contains { $0.wikiLink && $0.change == .added && $0.text == "New" })
        #expect(spans.contains { $0.wikiLink && $0.change == .removed && $0.text == "Old" })
        #expect(!spans.contains { $0.text.contains("[") || $0.text.contains("]") })
    }

    @Test func aRemovedLineIsRecognisedAsAWholeLineGone() {
        let pieces = WordDiff.pieces(from: "one\ntwo\nthree", to: "one\nthree")
        let lines = ReadableText.lines(pieces)
        #expect(lines.filter(\.isRemoved).count == 1)
        #expect(lines.filter(\.isRemoved).first?.spans.map(\.text).joined() == "two")
    }
}
