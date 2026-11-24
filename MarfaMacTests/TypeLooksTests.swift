import Foundation
import Testing
@testable import MarfaMac

/// How a type's look is worked out from what was chosen and its parents, and how the choices are kept per server, set
/// aside when unreadable, exported and imported.
@MainActor
struct TypeLooksTests {
    private let catalogue = LookFixture.catalogue()
    private let one = "marfa:http://one.test"
    private let two = "marfa:http://two.test"

    private func store(_ name: String, sink: RecordingSink = RecordingSink()) -> (store: TypeLooks, defaults: UserDefaults) {
        let defaults = ThrowawayDefaults.make("TypeLooksTests.\(name)")
        return (TypeLooks(defaults: defaults, reporting: Reporting(sink: sink)), defaults)
    }

    private func reopen(_ defaults: UserDefaults, sink: RecordingSink = RecordingSink()) -> TypeLooks {
        TypeLooks(defaults: defaults, reporting: Reporting(sink: sink))
    }

    private func note(_ id: String, parent: String? = nil, _ fields: [ItemTypeInfo.Field] = []) -> LookFixture.Spec {
        LookFixture.make(id, parent: parent, fields)
    }

    private func file(_ looks: [String: TypeLook]) -> LooksFile {
        LooksFile(looks: Dictionary(uniqueKeysWithValues: looks.map { (TypeID($0.key), $0.value) }))
    }

    private let chosenLook = TypeLook(date: .created, secondary: [], facts: [])

    // MARK: Choices that no longer fit

    @Test func manyTypesResolveInOnePass() {
        var specs = [note("root")]
        for index in 0..<600 { specs.append(note("t\(index)", parent: index < 3 ? "root" : "t\(index % 3)")) }
        let catalogue = LookFixture.catalogue(specs)
        let looks = catalogue.looks(choices: [TypeID("root"): TypeLookChoice(date: .created)])
        #expect(looks.count == 601)
        #expect(looks.values.allSatisfy { $0.date == .created })
    }

    // MARK: Per server

    @Test func twoServersWithOneTypeIdentifierKeepSeparateLooks() {
        let (store, defaults) = store("servers")
        store.importLooks(file(["core.note": chosenLook]), into: one, in: catalogue)
        #expect(store.looks(in: catalogue, library: one)[TypeID("core.note")] == chosenLook)
        #expect(store.looks(in: catalogue, library: two)[TypeID("core.note")]?.date == .edited)
        let again = reopen(defaults)
        #expect(again.choices(for: one)[TypeID("core.note")] == TypeLookChoice(chosenLook))
        #expect(again.choices(for: two).isEmpty)
    }

    @Test func aStoreFindsWhatWasChosenAgain() {
        let (store, defaults) = store("persist")
        store.importLooks(file(["core.task": TypeLook(date: .created, secondary: [], facts: [.tags])]), into: one, in: catalogue)
        #expect(reopen(defaults).looks(in: catalogue, library: one)[TypeID("aic.ticket.task")]?.facts == [.tags])
    }

    @Test func aTypeNobodyChoseForIsDerivedAndNothingIsStoredForIt() {
        let (store, defaults) = store("derived")
        #expect(store.looks(in: catalogue, library: one).count == catalogue.itemTypes.count)
        #expect(defaults.data(forKey: TypeLooks.defaultsKey) == nil)
    }

    // MARK: Unreadable storage

    @Test func aLookThatCannotBeReadIsSetAsideAndTheRestKept() throws {
        let sink = RecordingSink()
        let name = "unreadable"
        let defaults = ThrowawayDefaults.make("TypeLooksTests.\(name)")
        let stored: [String: Any] = [one: ["a": ["date": "bogus"], "b": ["date": "created"]], two: "not an object"]
        defaults.set(try JSONSerialization.data(withJSONObject: stored), forKey: TypeLooks.defaultsKey)

        let store = TypeLooks(defaults: defaults, reporting: Reporting(sink: sink))
        #expect(store.choices(for: one) == [TypeID("b"): TypeLookChoice(date: .created)])
        let aside = try #require(defaults.array(forKey: TypeLooks.setAsideKey) as? [Data])
        #expect(aside.count == 1)
        let kept = try #require(JSONSerialization.jsonObject(with: aside[0]) as? NSDictionary)
        #expect(kept == [one: ["a": ["date": "bogus"]], two: "not an object"] as NSDictionary)
        #expect(sink.errors.map(\.type) == ["type_looks_unreadable"])

        // What was readable was saved again, so the next launch sets nothing more aside.
        let next = RecordingSink()
        #expect(reopen(defaults, sink: next).choices(for: one)[TypeID("b")] == TypeLookChoice(date: .created))
        #expect((defaults.array(forKey: TypeLooks.setAsideKey) as? [Data])?.count == 1)
        #expect(next.errors.isEmpty)
    }

    @Test func storedTextThatIsNotLooksAtAllIsSetAsideWholeAfterEarlierOnes() throws {
        let sink = RecordingSink()
        let name = "whole"
        let defaults = ThrowawayDefaults.make("TypeLooksTests.\(name)")
        let earlier = Data("set aside before".utf8)
        let text = Data("not json".utf8)
        defaults.set([earlier], forKey: TypeLooks.setAsideKey)
        defaults.set(text, forKey: TypeLooks.defaultsKey)
        let store = TypeLooks(defaults: defaults, reporting: Reporting(sink: sink))
        #expect(store.choices(for: one).isEmpty)
        #expect(defaults.array(forKey: TypeLooks.setAsideKey) as? [Data] == [earlier, text])
        #expect(sink.errors.map(\.type) == ["type_looks_unreadable"])
    }

    // MARK: The file

    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test(arguments: [
        "",
        "not json",
        "[]",
        "{}",
        #"{"format":"marfa-mac-looks","version":1}"#,
        #"{"format":"other","version":1,"looks":{}}"#,
        #"{"format":"marfa-mac-looks","version":2,"looks":{}}"#,
        #"{"format":"marfa-mac-looks","version":1,"looks":{"a":{"date":"tomorrow","secondary":[],"facts":[]}}}"#,
        #"{"format":"marfa-mac-looks","version":1,"looks":{"a":{"date":"none","secondary":["bold"],"facts":[]}}}"#,
        #"{"format":"marfa-mac-looks","version":1,"looks":{"a":{"date":"none","secondary":["time:"],"facts":[]}}}"#,
        #"{"format":"marfa-mac-looks","version":1,"looks":{"a":{"date":"none","secondary":[],"facts":["time:starts_at"]}}}"#,
        #"{"format":"marfa-mac-looks","version":1,"looks":{"a":{"date":"none","secondary":[]}}}"#,
    ])
    func aFileOfAnotherShapeIsNotRead(text: String) {
        #expect(LooksFile.read(data(text)) == nil)
    }

    private func temporaryFile(_ contents: Data? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "looks-\(UUID().uuidString).json")
        if let contents { try contents.write(to: url) }
        return url
    }

    @Test func aFileOfTheWrongShapeIsRefusedAndNothingIsWritten() throws {
        let (store, defaults) = store("refused")
        for text in ["not json", #"{"format":"marfa-mac-looks","version":9,"looks":{}}"#] {
            let url = try temporaryFile(Data(text.utf8))
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(throws: LooksFileError.notALooksFile) { try store.importLooks(from: url, into: one, in: catalogue) }
        }
        #expect(store.choices(for: one).isEmpty)
        #expect(defaults.data(forKey: TypeLooks.defaultsKey) == nil)
    }

    @Test func aLibraryWhoseCatalogueHasNotLoadedIsRefusedAndNothingIsWritten() throws {
        let (store, defaults) = store("unloaded")
        let url = try temporaryFile(try file(["core.note": chosenLook]).encoded())
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: LooksFileError.notLoaded) { try store.importLooks(from: url, into: one, in: Catalogue()) }
        #expect(store.choices(for: one).isEmpty)
        #expect(defaults.data(forKey: TypeLooks.defaultsKey) == nil)
        try store.importLooks(from: url, into: one, in: catalogue)
        #expect(store.choices(for: one)[TypeID("core.note")] != nil, "the same file is kept once the catalogue has loaded")
    }

    @Test func aFileThatCannotBeReadIsRefused() throws {
        let (store, defaults) = store("missing")
        let missing = try temporaryFile()
        #expect(throws: LooksFileError.unreadable) { try store.importLooks(from: missing, into: one, in: catalogue) }
        #expect(defaults.data(forKey: TypeLooks.defaultsKey) == nil)
    }

    @Test func aFileThatCannotBeWrittenIsToldSo() throws {
        let (store, _) = store("unwritable")
        let nowhere = FileManager.default.temporaryDirectory.appending(path: "no-\(UUID().uuidString)/looks.json")
        #expect(throws: LooksFileError.unwritable) { try store.exportLooks(to: nowhere, in: catalogue, library: one) }
    }

    @Test func looksForTypesTheServerLacksAreKeptAndUsedWhenTheTypeAppears() throws {
        let (store, _) = store("lacking")
        let url = try temporaryFile(try file(["acme.invoice": chosenLook, "core.note": chosenLook]).encoded())
        defer { try? FileManager.default.removeItem(at: url) }
        try store.importLooks(from: url, into: one, in: catalogue)
        #expect(store.choices(for: one)[TypeID("acme.invoice")] == TypeLookChoice(chosenLook))

        // They go out again with the rest, so nothing is lost by moving between servers.
        #expect(store.file(in: catalogue, library: one).looks["acme.invoice"] == chosenLook)
        let later = LookFixture.catalogue(LookFixture.specs + [LookFixture.make("acme.invoice", [LookFixture.field("body")])])
        #expect(store.looks(in: later, library: one)[TypeID("acme.invoice")] == chosenLook)
    }

    @Test func importLeavesTheChoicesOfOtherTypesAlone() {
        let (store, _) = store("others")
        store.importLooks(file(["core.note": chosenLook]), into: one, in: catalogue)
        store.importLooks(file(["core.message": chosenLook]), into: one, in: catalogue)
        #expect(Set(store.choices(for: one).keys) == [TypeID("core.note"), TypeID("core.message")])
    }

    @Test func exportThenImportGivesTheSameLooks() throws {
        let (first, _) = store("exported")
        let (second, _) = store("imported")
        first.importLooks(file(["core.task": chosenLook, "acme.gone": chosenLook]), into: one, in: catalogue)
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try first.exportLooks(to: url, in: catalogue, library: one)
        try second.importLooks(from: url, into: two, in: catalogue)

        #expect(second.looks(in: catalogue, library: two) == first.looks(in: catalogue, library: one))
        #expect(second.file(in: catalogue, library: two) == first.file(in: catalogue, library: one))
        #expect(second.choices(for: two)[TypeID("acme.gone")] == TypeLookChoice(chosenLook))
        #expect(try Data(contentsOf: url) == first.file(in: catalogue, library: one).encoded(), "an export is the same text each time")
    }

    // MARK: Import keeps only what differs

    @Test func importingYourOwnExportStoresNoChoices() throws {
        let (store, defaults) = store("own")
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try store.exportLooks(to: url, in: catalogue, library: one)
        try store.importLooks(from: url, into: one, in: catalogue)
        #expect(store.choices(for: one).isEmpty)
        #expect(defaults.data(forKey: TypeLooks.defaultsKey) == nil, "nothing was written")
    }

    @Test func importingYourOwnExportLeavesWhatWasChosenAsItWas() throws {
        let (store, defaults) = store("keeps")
        store.importLooks(file(["core.task": chosenLook, "acme.gone": chosenLook]), into: one, in: catalogue)
        store.importLooks(file(["core.note": TypeLook(date: .created, secondary: [.opening], facts: [.tags])]), into: one, in: catalogue)
        let before = store.choices(for: one)
        #expect(before[TypeID("core.note")] == TypeLookChoice(date: .created), "only the date differs from the preset")
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try store.exportLooks(to: url, in: catalogue, library: one)
        try store.importLooks(from: url, into: one, in: catalogue)
        #expect(store.choices(for: one) == before)
        #expect(reopen(defaults).choices(for: one) == before)
    }

    @Test func aFileWithOneChangedPlaceStoresExactlyThatPlace() {
        let (store, _) = store("one")
        var looks = store.file(in: catalogue, library: one).looks
        looks["core.message"]?.secondary = []
        store.importLooks(file(looks), into: one, in: catalogue)
        #expect(store.choices(for: one) == [TypeID("core.message"): TypeLookChoice(secondary: [])])
        #expect(store.looks(in: catalogue, library: one)[TypeID("core.message")]?.secondary == [])
    }

    @Test func aPlaceBackToWhatTheMacWorksOutClearsItsChoice() {
        let (store, _) = store("cleared")
        store.importLooks(file(["core.message": chosenLook]), into: one, in: catalogue)
        #expect(store.choices(for: one) == [TypeID("core.message"): TypeLookChoice(date: .created, secondary: [])])
        var looks = store.file(in: catalogue, library: one).looks
        looks["core.message"]?.date = .occurred
        store.importLooks(file(looks), into: one, in: catalogue)
        #expect(store.choices(for: one) == [TypeID("core.message"): TypeLookChoice(secondary: [])], "only the date went back")
        looks["core.message"]?.secondary = [.field("from")]
        store.importLooks(file(looks), into: one, in: catalogue)
        #expect(store.choices(for: one).isEmpty)
    }

    @Test func aLaterBetterPresetStillReachesAPlaceNobodyChose() {
        let (store, _) = store("later")
        let status = LookFixture.field("state", LookFixture.status)
        let before = LookFixture.catalogue([note("acme.t", [status])])
        let after = LookFixture.catalogue([note("acme.t", [status, LookFixture.field("project")])])
        var looks = store.file(in: before, library: one).looks
        looks["acme.t"]?.date = .created
        store.importLooks(file(looks), into: one, in: before)
        #expect(store.choices(for: one) == [TypeID("acme.t"): TypeLookChoice(date: .created)])
        #expect(store.looks(in: after, library: one)[TypeID("acme.t")] == TypeLook(
            date: .created, secondary: [.field("project")], facts: []))
    }

    @Test func aFileGivesEveryTypeTheLookItHoldsAndAChildLikeItsParentStoresNothing() {
        let (store, _) = store("whole")
        var looks = catalogue.looks()
        // A file from another Mac whose person chose a date for tasks, which every task-like child shows too.
        for type in ["core.task", "aic.ticket", "aic.ticket.task"] { looks[TypeID(type)]?.date = .created }
        store.importLooks(file(Dictionary(uniqueKeysWithValues: looks.map { ($0.key.rawValue, $0.value) })), into: one, in: catalogue)
        #expect(store.choices(for: one) == [TypeID("core.task"): TypeLookChoice(date: .created)])
        #expect(store.looks(in: catalogue, library: one) == looks)
    }

    @Test func aChildThatDiffersFromItsParentKeepsItsOwnChoice() {
        let (store, _) = store("child")
        var looks = catalogue.looks()
        for type in ["core.task", "aic.ticket"] { looks[TypeID(type)]?.date = .created }
        looks[TypeID("aic.ticket.task")]?.date = .off
        store.importLooks(file(Dictionary(uniqueKeysWithValues: looks.map { ($0.key.rawValue, $0.value) })), into: one, in: catalogue)
        #expect(store.choices(for: one) == [
            TypeID("core.task"): TypeLookChoice(date: .created), TypeID("aic.ticket.task"): TypeLookChoice(date: .off),
        ])
        #expect(store.looks(in: catalogue, library: one) == looks)
    }

    @Test func aParentIsMeasuredBeforeItsChildWhateverTheirIdentifiersSortTo() {
        let (store, _) = store("parentfirst")
        let catalogue = LookFixture.catalogue([note("a.child", parent: "b.parent"), note("b.parent")])
        let preset = LookFixture.look("b.parent", in: catalogue)
        #expect(preset.date == .edited)
        let moved = TypeLook(date: .created, secondary: preset.secondary, facts: preset.facts)
        store.importLooks(file(["a.child": moved, "b.parent": moved]), into: one, in: catalogue)
        #expect(store.choices(for: one) == [TypeID("b.parent"): TypeLookChoice(date: .created)], "the child stores nothing")
    }

    /// Below ten ancestors the old order was right; past ten, types tie on the count and fell back to their names, so a
    /// child whose identifier sorts first was measured against its parent's old look.
    @Test func aParentIsMeasuredBeforeItsChildInAChainDeeperThanTheAncestorLimit() {
        let (store, _) = store("deep")
        // The deeper the type, the earlier its identifier sorts.
        func id(_ depth: Int) -> String { "t\(99 - depth)" }
        let catalogue = LookFixture.catalogue((0...12).map { note(id($0), parent: $0 == 0 ? nil : id($0 - 1)) })
        #expect([10, 11, 12].map { catalogue.ancestors(of: TypeID(id($0))).count } == [10, 10, 10], "these three tie on ancestors")
        #expect(id(12) < id(11) && id(11) < id(10))
        let preset = LookFixture.look(id(10), in: catalogue)
        let moved = TypeLook(date: .created, secondary: preset.secondary, facts: preset.facts)
        store.importLooks(file([id(10): moved, id(11): moved, id(12): moved]), into: one, in: catalogue)
        #expect(store.choices(for: one) == [TypeID(id(10)): TypeLookChoice(date: .created)])
        #expect(store.looks(in: catalogue, library: one)[TypeID(id(12))] == moved)
    }

    @Test func aChildKeepsItsParentsOldLookAsItsOwnChoiceWhenTheParentMoves() {
        let (store, _) = store("oldparent")
        let catalogue = LookFixture.catalogue([note("a.child", parent: "b.parent"), note("b.parent")])
        let old = LookFixture.look("b.parent", in: catalogue)
        let moved = TypeLook(date: .created, secondary: old.secondary, facts: old.facts)
        store.importLooks(file(["b.parent": moved, "a.child": old]), into: one, in: catalogue)
        #expect(store.choices(for: one) == [
            TypeID("b.parent"): TypeLookChoice(date: .created), TypeID("a.child"): TypeLookChoice(date: .edited),
        ])
        #expect(store.looks(in: catalogue, library: one)[TypeID("a.child")] == old)
        #expect(store.looks(in: catalogue, library: one)[TypeID("b.parent")] == moved)
    }

    @Test func importKeepsAnUnknownTypesWholeLookSinceNothingCanBeMeasured() {
        let (store, _) = store("unknown")
        let look = TypeLook(date: .edited, secondary: [.opening], facts: [.tags])
        store.importLooks(file(["acme.later": look]), into: one, in: catalogue)
        #expect(store.choices(for: one) == [TypeID("acme.later"): TypeLookChoice(look)])
    }

    @Test func anExportHoldsEveryTypeOfTheCatalogue() {
        let (store, _) = store("everything")
        let looks = store.file(in: catalogue, library: one).looks
        #expect(Set(looks.keys) == Set(catalogue.itemTypes.keys.map(\.rawValue)))
        #expect(looks["core.task"] == catalogue.looks()[TypeID("core.task")])
    }
}
