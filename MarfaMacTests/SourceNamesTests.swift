import Foundation
import Marfa
@testable import MarfaMac
import Synchronization
import Testing

/// A server's answers about sources, which a test sets and reads back.
nonisolated final class FakeSourceNames: SourceNameSource {
    struct State {
        var infos: [SourceInfo] = []
        var counts: [String: Int] = [:]
        var failure: SourceEditFailure?
        var changes: [(code: String, name: SourceFieldChange?, mark: SourceFieldChange?)] = []
        var asks = 0
    }

    let state = Mutex(State())

    init(_ infos: [SourceInfo] = [], counts: [String: Int] = [:]) {
        state.withLock { $0.infos = infos; $0.counts = counts }
    }

    func sources() async throws(SourceEditFailure) -> [SourceInfo] {
        let (failure, infos) = state.withLock { state -> (SourceEditFailure?, [SourceInfo]) in
            state.asks += 1
            return (state.failure, state.infos)
        }
        if let failure { throw failure }
        return infos
    }

    func counts() async throws(SourceEditFailure) -> [String: Int] {
        let (failure, counts) = state.withLock { ($0.failure, $0.counts) }
        if let failure { throw failure }
        return counts
    }

    func connectors() async throws(SourceEditFailure) -> ConnectorKeepers { ConnectorKeepers() }

    func update(_ code: String, name: SourceFieldChange?, mark: SourceFieldChange?) async throws(SourceEditFailure) -> SourceInfo {
        if let failure = state.withLock({ $0.failure }) { throw failure }
        return state.withLock { state in
            state.changes.append((code, name, mark))
            let old = state.infos.first { $0.code == code } ?? .unnamed(code)
            let renamed: (String, Marfa.ItemSource.NameOrigin) = switch name {
            case .set(let text)?: (text, .set)
            case .clear?: (code, .code)
            case nil: (old.name, old.nameOrigin)
            }
            let marked: String? = switch mark {
            case .set(let id)?: id
            case .clear?: nil
            case nil: old.mark
            }
            let changed = SourceInfo(code: code, name: renamed.0, mark: marked, nameOrigin: renamed.1)
            state.infos = state.infos.filter { $0.code != code } + [changed]
            return changed
        }
    }
}

private let readwise = SourceInfo(code: "readwise", name: "Readwise", mark: "simple-icons:readwise", nameOrigin: .set)
private let github = SourceInfo(code: "gh", name: "GitHub", mark: nil, nameOrigin: .key)

@MainActor
@Suite(.hangLimit) struct SourceNamesTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func open(_ names: FakeSourceNames?, items: [MarfaMac.Item]? = nil) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices(), sourceNames: names)
        var held = items ?? []
        if items == nil {
            for (code, count) in [("readwise", 2), ("gh", 1)] {
                for index in 0..<count {
                    var item = FakeItemLibrary.note("\(code) \(index)", modified: date)
                    item.source = code
                    held.append(item)
                }
            }
        }
        source.send(.loaded(SourceSnapshot(items: held, catalogue: FakeItemLibrary.testCatalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    @Test func aRenameIsShownAtOnceAndSendsOnlyTheName() async throws {
        let names = FakeSourceNames([readwise])
        let (library, _) = try await open(names)
        #expect(await library.updateSource("readwise", name: .set("Readwise Reader"), mark: nil) == nil)
        #expect(library.name(of: .source("readwise")) == "Readwise Reader")
        let change = try #require(names.state.withLock { $0.changes.first })
        #expect(change.code == "readwise")
        #expect(change.name == .set("Readwise Reader"))
        #expect(change.mark == nil)
        // The mark the source had is kept.
        #expect(library.sources.info("readwise").mark == "simple-icons:readwise")
    }

    @Test func clearingAMarkLeavesTheName() async throws {
        let names = FakeSourceNames([readwise])
        let (library, _) = try await open(names)
        #expect(await library.updateSource("readwise", name: nil, mark: .clear) == nil)
        #expect(library.sources.info("readwise").mark == nil)
        #expect(library.name(of: .source("readwise")) == "Readwise")
    }

    @Test(arguments: [
        SourceEditFailure.refused("The name must not be empty."), .notPermitted, .unreachable, .keyRefused,
    ])
    func aRefusedChangeIsToldAndChangesNothing(_ failure: SourceEditFailure) async throws {
        let names = FakeSourceNames([readwise])
        let (library, _) = try await open(names)
        try #require(await eventually { library.sources.infos["readwise"] != nil })
        names.state.withLock { $0.failure = failure }
        #expect(await library.updateSource("readwise", name: .set("x"), mark: nil) == failure)
        #expect(!failure.message.isEmpty)
        #expect(library.name(of: .source("readwise")) == "Readwise")
    }

    @Test func aLibraryWithNoServerRefusesTheChange() async throws {
        let (library, _) = try await open(nil)
        #expect(await library.updateSource("readwise", name: .set("x"), mark: nil) == .unsupported)
    }
}

@MainActor
@Suite(.hangLimit) struct SourceEditModelTests {
    private func model(_ mode: SourceEditModel.Mode, reaches: Bool = true) -> (SourceEditModel, FakeItemLibrary) {
        let library = FakeItemLibrary()
        library.sources = SourceDirectory(infos: ["readwise": readwise, "gh": github])
        library.reachesServer = reaches
        return (SourceEditModel(code: "readwise", mode: mode, library: library, ids: [.lucide: ["lucide:bug", "lucide:book"], .simpleIcons: ["simple-icons:readwise"]]), library)
    }

    @Test func theNameStartsAsTheNameShownAndRenamesOnlyWhenItChanges() async {
        let (model, library) = model(.name)
        #expect(model.name == "Readwise")
        #expect(!model.canRename)
        model.name = "  "
        #expect(!model.canRename)
        model.name = "  Reader  "
        #expect(model.canRename)
        #expect(await model.rename())
        #expect(library.sourceChanges.map(\.name) == [.set("Reader")])
        #expect(library.sourceChanges.map(\.mark) == [nil])
    }

    @Test func useDefaultNameIsOfferedOnlyForANameThatWasSet() async {
        let (named, library) = model(.name)
        #expect(named.canUseDefaultName)
        #expect(await named.useDefaultName())
        #expect(library.sourceChanges.map(\.name) == [.clear])
        let other = SourceEditModel(code: "gh", mode: .name, library: library)
        #expect(!other.canUseDefaultName)
    }

    @Test func theServersRefusalIsKeptForTheSheetAndTheSheetStaysOpen() async {
        let (model, library) = model(.name)
        library.sourceFailure = .refused("The name must be 1 to 200 characters.")
        model.name = "x"
        #expect(await model.rename() == false)
        #expect(model.failure == .refused("The name must be 1 to 200 characters."))
        library.sourceFailure = nil
        #expect(await model.rename())
        #expect(model.failure == nil)
    }

    @Test func nothingChangesWhileTheServerCannotBeReached() async {
        let (model, library) = model(.name, reaches: false)
        model.name = "Other"
        #expect(!model.canRename)
        #expect(await model.rename() == false)
        #expect(library.sourceChanges.isEmpty)
    }

    @Test func aMarkIsChosenAsAFullIDAndRemovedWithClear() async {
        let (model, library) = model(.mark)
        #expect(model.set == .simpleIcons)
        #expect(model.canRemoveMark)
        #expect(await model.chooseMark("lucide:bug"))
        #expect(library.sources.info("readwise").mark == "lucide:bug")
        #expect(await model.chooseMark(nil))
        #expect(library.sourceChanges.map(\.mark) == [.set("lucide:bug"), .clear])
        #expect(library.sourceChanges.allSatisfy { $0.name == nil })
        #expect(!model.canRemoveMark)
    }
}

struct SourceServerMappingTests {
    @Test func aChangeIsASetOrAClear() {
        #expect(MarfaServerCalls.change(.set("x")) == .set("x"))
        #expect(MarfaServerCalls.change(.clear) == .clear)
    }
}
