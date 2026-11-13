import Foundation
import Testing
@testable import MAPP

/// How a type's look is worked out from what was chosen and its parents, and how the choices are kept per server, set
/// aside when unreadable, exported and imported.
@MainActor
struct TypeLooksTests {
    private let catalogue = LookFixture.catalogue()
    private let one = "marfa:http://one.test"
    private let two = "marfa:http://two.test"

    private func store(_ name: String, sink: RecordingSink = RecordingSink()) -> (store: TypeLooks, defaults: UserDefaults) {
        let suite = "TypeLooksTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (TypeLooks(defaults: defaults, reporting: Reporting(sink: sink)), defaults)
    }

    private func reopen(_ defaults: UserDefaults, sink: RecordingSink = RecordingSink()) -> TypeLooks {
        TypeLooks(defaults: defaults, reporting: Reporting(sink: sink))
    }

    private func clean(_ defaults: UserDefaults, _ name: String) { defaults.removePersistentDomain(forName: "TypeLooksTests.\(name)") }

    private func note(_ id: String, parent: String? = nil, _ fields: [ItemTypeInfo.Field] = []) -> LookFixture.Spec {
        LookFixture.make(id, parent: parent, fields)
    }

    private func file(_ looks: [String: TypeLook]) -> LooksFile {
        LooksFile(looks: Dictionary(uniqueKeysWithValues: looks.map { (TypeID($0.key), $0.value) }))
    }

    private let chosenLook = TypeLook(date: .created, secondary: [], facts: [])

    // MARK: Inheritance

    @Test func aChildTakesItsParentsChosenLookPlaceByPlace() {
        let catalogue = LookFixture.catalogue([note("a"), note("b", parent: "a")])
        let choices: [TypeID: TypeLookChoice] = [
            TypeID("a"): TypeLookChoice(date: .created, facts: []), TypeID("b"): TypeLookChoice(secondary: []),
        ]
        #expect(catalogue.look(of: TypeID("b"), choices: choices) == TypeLook(date: .created, secondary: [], facts: []))
        // A place nobody chose is the type's own preset.
        #expect(catalogue.look(of: TypeID("a"), choices: choices) == TypeLook(date: .created, secondary: [.opening], facts: []))
    }

    @Test func aChildOfAnotherPresetDoesNotTakeItsParentsChoice() {
        let status = LookFixture.status
        let catalogue = LookFixture.catalogue([note("a"), note("b", parent: "a", [LookFixture.field("state", status)])])
        let choices = [TypeID("a"): TypeLookChoice(chosenLook)]
        let child = catalogue.look(of: TypeID("b"), choices: choices)
        #expect(LookPreset.suggested(for: TypeID("b"), in: catalogue) == .task)
        #expect(child == LookPreset.task.look(for: TypeID("b"), in: catalogue))
    }

    @Test func aChildTakesTheNearestAncestorThatChose() {
        let catalogue = LookFixture.catalogue([note("a"), note("b", parent: "a"), note("c", parent: "b")])
        let choices = [
            TypeID("a"): TypeLookChoice(date: .created), TypeID("b"): TypeLookChoice(date: .off),
        ]
        #expect(catalogue.look(of: TypeID("c"), choices: choices).date == .off)
    }

    @Test func aChildWhoseParentIsMissingFromTheCatalogueTakesItsOwnPreset() {
        let catalogue = LookFixture.catalogue([note("orphan", parent: "gone")])
        let choices = [TypeID("gone"): TypeLookChoice(chosenLook)]
        #expect(catalogue.look(of: TypeID("orphan"), choices: choices) == LookPreset.note.look(for: TypeID("orphan"), in: catalogue))
    }

    @Test func aChainAtTheTenAncestorLimitReachesTheRootAndOneBeyondDoesNot() {
        let chain = (0...11).map { note("t\($0)", parent: $0 == 0 ? nil : "t\($0 - 1)") }
        let catalogue = LookFixture.catalogue(chain)
        let choices = [TypeID("t0"): TypeLookChoice(date: .created)]
        #expect(catalogue.ancestors(of: TypeID("t10")).count == 10)
        #expect(catalogue.look(of: TypeID("t10"), choices: choices).date == .created)
        #expect(catalogue.ancestors(of: TypeID("t11")).count == Catalogue.ancestorLimit)
        #expect(catalogue.look(of: TypeID("t11"), choices: choices).date == .edited)
    }

    @Test func aParentLoopEndsTheWalkInsteadOfSpinning() {
        let catalogue = LookFixture.catalogue([note("a", parent: "b"), note("b", parent: "a")])
        #expect(catalogue.ancestors(of: TypeID("a")) == [TypeID("b")])
        #expect(catalogue.look(of: TypeID("a")) == LookPreset.note.look(for: TypeID("a"), in: catalogue))
    }

    @Test func ancestorsAreNearestFirstAndNameAParentTheCatalogueLacks() {
        #expect(catalogue.ancestors(of: TypeID("aic.ticket.task")) == [TypeID("aic.ticket"), TypeID("core.task")])
        #expect(catalogue.ancestors(of: TypeID("core.task")).isEmpty)
        #expect(catalogue.ancestors(of: TypeID("nobody")).isEmpty)
        let orphan = LookFixture.catalogue([note("orphan", parent: "gone")])
        #expect(orphan.ancestors(of: TypeID("orphan")) == [TypeID("gone")])
    }

    // MARK: Choices that no longer fit

    @Test func aChosenFieldTheTypeLacksIsPassedOver() {
        let catalogue = LookFixture.catalogue([note("a")])
        let choices = [TypeID("a"): TypeLookChoice(
            date: .field("nope"), secondary: [.field("nope"), .opening], facts: [.field("nope"), .tags])]
        #expect(catalogue.look(of: TypeID("a"), choices: choices) == TypeLook(date: .edited, secondary: [.opening], facts: [.tags]))
    }

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
        defer { clean(defaults, "servers") }
        store.importLooks(file(["core.note": chosenLook]), into: one)
        #expect(store.look(of: TypeID("core.note"), in: catalogue, library: one) == chosenLook)
        #expect(store.look(of: TypeID("core.note"), in: catalogue, library: two).date == .edited)
        let again = reopen(defaults)
        #expect(again.choices(for: one)[TypeID("core.note")] == TypeLookChoice(chosenLook))
        #expect(again.choices(for: two).isEmpty)
    }

    @Test func aStoreFindsWhatWasChosenAgain() {
        let (store, defaults) = store("persist")
        defer { clean(defaults, "persist") }
        store.importLooks(file(["core.task": TypeLook(date: .created, secondary: [], facts: [.tags])]), into: one)
        #expect(reopen(defaults).look(of: TypeID("aic.ticket.task"), in: catalogue, library: one).facts == [.tags])
    }

    @Test func aTypeNobodyChoseForIsDerivedAndNothingIsStoredForIt() {
        let (store, defaults) = store("derived")
        defer { clean(defaults, "derived") }
        #expect(store.looks(in: catalogue, library: one).count == catalogue.itemTypes.count)
        #expect(defaults.data(forKey: TypeLooks.defaultsKey) == nil)
    }

    // MARK: Unreadable storage

    @Test func aLookThatCannotBeReadIsSetAsideAndTheRestKept() throws {
        let sink = RecordingSink()
        let name = "unreadable"
        let defaults = UserDefaults(suiteName: "TypeLooksTests.\(name)")!
        defaults.removePersistentDomain(forName: "TypeLooksTests.\(name)")
        defer { clean(defaults, name) }
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
        let defaults = UserDefaults(suiteName: "TypeLooksTests.\(name)")!
        defaults.removePersistentDomain(forName: "TypeLooksTests.\(name)")
        defer { clean(defaults, name) }
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
        #"{"format":"mapp-looks","version":1}"#,
        #"{"format":"other","version":1,"looks":{}}"#,
        #"{"format":"mapp-looks","version":2,"looks":{}}"#,
        #"{"format":"mapp-looks","version":1,"looks":{"a":{"date":"tomorrow","secondary":[],"facts":[]}}}"#,
        #"{"format":"mapp-looks","version":1,"looks":{"a":{"date":"none","secondary":["bold"],"facts":[]}}}"#,
        #"{"format":"mapp-looks","version":1,"looks":{"a":{"date":"none","secondary":[]}}}"#,
    ])
    func aFileOfAnotherShapeIsNotRead(text: String) {
        #expect(LooksFile.read(data(text)) == nil)
    }

    @Test func aLooksFileIsReadableText() throws {
        let file = file(["core.task": TypeLook(date: .field("due_at"), secondary: [.site, .field("project")], facts: [.tags])])
        let text = try #require(String(data: file.encoded(), encoding: .utf8))
        #expect(text.contains(#""format" : "mapp-looks""#))
        #expect(text.contains(#""field:due_at""#))
        #expect(text.contains(#""site""#))
        #expect(LooksFile.read(Data(text.utf8)) == file)
        #expect(!text.contains("http"), "the file names no server")
    }

    private func temporaryFile(_ contents: Data? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "looks-\(UUID().uuidString).json")
        if let contents { try contents.write(to: url) }
        return url
    }

    @Test func aFileOfTheWrongShapeIsRefusedAndNothingIsWritten() throws {
        let (store, defaults) = store("refused")
        defer { clean(defaults, "refused") }
        for text in ["not json", #"{"format":"mapp-looks","version":9,"looks":{}}"#] {
            let url = try temporaryFile(Data(text.utf8))
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(throws: LooksFileError.notALooksFile) { try store.importLooks(from: url, into: one) }
        }
        #expect(store.choices(for: one).isEmpty)
        #expect(defaults.data(forKey: TypeLooks.defaultsKey) == nil)
    }

    @Test func aFileThatCannotBeReadIsRefused() throws {
        let (store, defaults) = store("missing")
        defer { clean(defaults, "missing") }
        let missing = try temporaryFile()
        #expect(throws: LooksFileError.unreadable) { try store.importLooks(from: missing, into: one) }
        #expect(defaults.data(forKey: TypeLooks.defaultsKey) == nil)
    }

    @Test func aFileThatCannotBeWrittenIsToldSo() throws {
        let (store, defaults) = store("unwritable")
        defer { clean(defaults, "unwritable") }
        let nowhere = FileManager.default.temporaryDirectory.appending(path: "no-\(UUID().uuidString)/looks.json")
        #expect(throws: LooksFileError.unwritable) { try store.exportLooks(to: nowhere, in: catalogue, library: one) }
    }

    @Test func looksForTypesTheServerLacksAreKeptAndUsedWhenTheTypeAppears() throws {
        let (store, defaults) = store("lacking")
        defer { clean(defaults, "lacking") }
        let url = try temporaryFile(try file(["acme.invoice": chosenLook, "core.note": chosenLook]).encoded())
        defer { try? FileManager.default.removeItem(at: url) }
        try store.importLooks(from: url, into: one)
        #expect(store.choices(for: one)[TypeID("acme.invoice")] == TypeLookChoice(chosenLook))

        // They go out again with the rest, so nothing is lost by moving between servers.
        #expect(store.file(in: catalogue, library: one).looks["acme.invoice"] == chosenLook)
        let later = LookFixture.catalogue(LookFixture.specs + [LookFixture.make("acme.invoice", [LookFixture.field("body")])])
        #expect(store.look(of: TypeID("acme.invoice"), in: later, library: one) == chosenLook)
    }

    @Test func importLeavesTheChoicesOfOtherTypesAlone() {
        let (store, defaults) = store("others")
        defer { clean(defaults, "others") }
        store.importLooks(file(["core.note": chosenLook]), into: one)
        store.importLooks(file(["core.message": chosenLook]), into: one)
        #expect(Set(store.choices(for: one).keys) == [TypeID("core.note"), TypeID("core.message")])
    }

    @Test func exportThenImportGivesTheSameLooks() throws {
        let (first, firstDefaults) = store("exported")
        let (second, secondDefaults) = store("imported")
        defer {
            clean(firstDefaults, "exported")
            clean(secondDefaults, "imported")
        }
        first.importLooks(file(["core.task": chosenLook, "acme.gone": chosenLook]), into: one)
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try first.exportLooks(to: url, in: catalogue, library: one)
        try second.importLooks(from: url, into: two)

        #expect(second.looks(in: catalogue, library: two) == first.looks(in: catalogue, library: one))
        #expect(second.file(in: catalogue, library: two) == first.file(in: catalogue, library: one))
        #expect(second.choices(for: two)[TypeID("acme.gone")] == TypeLookChoice(chosenLook))
        #expect(try Data(contentsOf: url) == first.file(in: catalogue, library: one).encoded(), "an export is the same text each time")
    }

    @Test func anExportHoldsEveryTypeOfTheCatalogue() {
        let (store, defaults) = store("everything")
        defer { clean(defaults, "everything") }
        let looks = store.file(in: catalogue, library: one).looks
        #expect(Set(looks.keys) == Set(catalogue.itemTypes.keys.map(\.rawValue)))
        #expect(looks["core.task"] == catalogue.look(of: TypeID("core.task")))
    }
}
