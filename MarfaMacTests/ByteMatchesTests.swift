import Foundation
import Marfa
import MarfaTesting
import Synchronization
import Testing
@testable import MarfaMac

/// How the package's byte lookup becomes the app's answers: one result per file, and no answer wherever the lookup
/// cannot say. Nothing here reaches a server or the Keychain.
@MainActor
@Suite(.hangLimit)
struct ByteMatchesTests {
    let disk = TestFiles()

    private struct Opened {
        let fake: FakeCopy
        let source: MarfaSource
    }

    private func opened(calls: MarfaServerCalls? = nil) -> Opened {
        let fake = WorkingCopy.fake()
        return Opened(fake: fake, source: MarfaSource(copy: fake.copy, connection: SampleLibrary.connection, calls: calls))
    }

    /// Closes the source. `fake` is kept until here so its copy outlives the source's engine.
    private func close(_ opened: Opened) async {
        await opened.source.close()
        withExtendedLifetime(opened.fake) {}
    }

    private func held(_ items: [(id: String, title: String?)], more: Bool = false) -> Marfa.FileMatch {
        .held(
            hash: "sha256:" + String(repeating: "a", count: 64),
            items: items.map { Marfa.FileHolder(id: $0.id, type: "core.note", title: $0.title) },
            more: more)
    }

    private func item(_ id: String, _ title: String) -> MarfaMac.FileMatch {
        MarfaMac.FileMatch(id: ItemID(id), title: title)
    }

    @Test func aThrownLookupIsNoAnswerForTheWholeBatch() async {
        let opened = opened()
        let called = Mutex(false)
        opened.source.hooks.holdingBytes.set { _ in
            called.withLock { $0 = true }
            throw MarfaError.canceled(message: "the lookup failed")
        }
        let first = disk.url("a.png")
        let second = disk.url("b.png")
        let answers = await opened.source.itemsWithSameBytes(as: [first, second])
        #expect(called.withLock { $0 })
        #expect(answers[0] == .noAnswer)
        #expect(answers[1] == .noAnswer)
        await close(opened)
    }

    @Test func anUnreadableFileBesideAMatchAnswersOnlyForTheMatch() async {
        let opened = opened()
        let unreadable = disk.url("broken.png")
        let found = disk.url("photo.png")
        let match = held([("beach", "Beach Day")])
        opened.source.hooks.holdingBytes.set { _ in [.unreadable, match] }
        let answers = await opened.source.itemsWithSameBytes(as: [unreadable, found])
        #expect(answers[0] == .noAnswer)
        #expect(answers[1] == .answered([item("beach", "Beach Day")], more: false))
        await close(opened)
    }

    @Test func anEmptyHolderListIsNoMatch() async {
        let opened = opened()
        let file = disk.url("new.png")
        let match = held([])
        opened.source.hooks.holdingBytes.set { _ in [match] }
        let answers = await opened.source.itemsWithSameBytes(as: [file])
        #expect(answers[0] == .answered([], more: false))
        await close(opened)
    }

    @Test func aFileThatIsNotAFileIsNoAnswerAndMoreFollowsTheFileItBelongsTo() async {
        let opened = opened()
        let folder = disk.url("folder")
        let photo = disk.url("photo.png")
        let extra = held([("one", "One"), ("two", nil)], more: true)
        opened.source.hooks.holdingBytes.set { _ in [.notAFile, extra] }
        let answers = await opened.source.itemsWithSameBytes(as: [folder, photo])
        #expect(answers[0] == .noAnswer)
        #expect(answers[1] == .answered([item("one", "One"), item("two", "")], more: true))
        await close(opened)
    }

    @Test func aListThatDoesNotLineUpIsNoAnswerForEveryFile() async {
        let opened = opened()
        let first = disk.url("a.png")
        let second = disk.url("b.png")
        let match = held([("only", "Only")])
        opened.source.hooks.holdingBytes.set { _ in [match] }
        let answers = await opened.source.itemsWithSameBytes(as: [first, second])
        #expect(answers[0] == .noAnswer)
        #expect(answers[1] == .noAnswer)
        await close(opened)
    }

    @Test func theSamePathTwiceKeepsEachAnswer() async {
        let opened = opened()
        let file = disk.url("a.png")
        let match = held([("one", "One")])
        opened.source.hooks.holdingBytes.set { _ in [match, .unreadable] }
        let answers = await opened.source.itemsWithSameBytes(as: [file, file])
        #expect(answers[0] == .answered([item("one", "One")], more: false))
        #expect(answers[1] == .noAnswer)
        await close(opened)
    }

    @Test func theLookupIsGivenTheFileAnAddWouldUpload() async throws {
        let opened = opened()
        let real = disk.url("photo.png", "pixels")
        let link = disk.directory.appending(path: "alias.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let seen = Mutex<[URL]>([])
        let match = held([("photo", "Photo")])
        opened.source.hooks.holdingBytes.set { urls in
            seen.withLock { $0 = urls }
            return [match]
        }
        let answers = await opened.source.itemsWithSameBytes(as: [link])
        // The caller resolves a link once. This lookup is given that URL and does not resolve it again.
        #expect(seen.withLock { $0 }.map(\.path) == [link.path])
        #expect(answers[0] == .answered([item("photo", "Photo")], more: false))
        await close(opened)
    }

    @Test(arguments: [
        MarfaConnectionState.connecting,
        .offline(reason: "away"),
        .keyRefused,
    ])
    func anUnreachableMarfaAnswersAtOnce(_ state: MarfaConnectionState) async {
        let opened = opened()
        opened.source.hub.set(state)
        let file = disk.url("a.txt")
        // Well under the 10 seconds the check waits: this path must not start a lookup.
        let started = ContinuousClock.now
        let answers = await opened.source.itemsWithSameBytes(as: [file])
        #expect(started.duration(to: .now) < .seconds(2))
        #expect(answers[0] == .noAnswer)
        await close(opened)
    }

    @Test func aSignedOutMarfaAnswersAtOnce() async {
        let calls = MarfaServerCalls(connection: SampleLibrary.connection, signIns: ScriptedSignIns())
        let opened = opened(calls: calls)
        opened.source.hub.set(.online)
        let file = disk.url("a.txt")
        // Online, but the sign-in is missing, so the lookup must not wait out its request.
        let started = ContinuousClock.now
        let answers = await opened.source.itemsWithSameBytes(as: [file])
        #expect(started.duration(to: .now) < .seconds(2))
        #expect(answers[0] == .noAnswer)
        await close(opened)
    }

    @Test func theLibraryDoesNotAskWhileItCannotReachTheServer() async {
        let opened = opened()
        let asked = Mutex(false)
        opened.source.hooks.holdingBytes.set { _ in
            asked.withLock { $0 = true }
            try await Task.sleep(for: .seconds(5))
            return []
        }
        let library = MarfaLibrary(source: opened.source, notices: Notices())
        let file = disk.url("a.txt")
        let started = ContinuousClock.now
        let answers = await library.itemsWithSameBytes(as: [file])
        #expect(started.duration(to: .now) < .seconds(2))
        #expect(asked.withLock { $0 } == false)
        #expect(answers[0] == .noAnswer)
        await close(opened)
    }
}
