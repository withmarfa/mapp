import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// A library that answers nothing of its own: the test sets its connection and report, and reads what it was
/// asked to do.
nonisolated final class FakeMarfaSource: MarfaHostedSource {
    let connection: MarfaConnection
    let capabilities: SourceCapabilities = []
    let embeds: any EmbedResolver = FakeEmbeds()
    let state = Latest(MarfaConnectionState.connecting)
    let report = Latest(SyncReport(queueRead: true))
    /// The server it was opened on.
    let server: Server
    private let asked = Mutex<[String]>([])

    init(connection: MarfaConnection, server: Server) {
        self.connection = connection
        self.server = server
    }

    var calls: [String] { asked.withLock { $0 } }

    private func record(_ call: String) {
        asked.withLock { $0.append(call) }
    }

    var connectionState: MarfaConnectionState { state.value }
    func connectionStates() -> AsyncStream<MarfaConnectionState> { state.values() }
    func refresh() { record("refresh") }

    /// The text of the first writes the report counts, as the copy reads it from its queue.
    let unsentTexts = Mutex<[SyncContent]>([])

    /// One write for each the report counts.
    func unsentWrites() async -> UnsentWrites? {
        let report = report.value
        guard report.queueRead else { return nil }
        var unsent = UnsentWrites.fake(report.changesNotSent)
        unsent.texts = unsentTexts.withLock { $0 }.enumerated().map { index, content in
            UnsentWrites.Text(id: "w\(index)", change: .edit, content: content, date: Date(timeIntervalSinceReferenceDate: Double(index)))
        }
        return unsent
    }

    func close(agreeing agreed: UnsentWrites?) async -> CloseOutcome {
        let unsent = await unsentWrites()
        let covered = if let unsent { agreed.map { unsent.ids.isSubset(of: $0.ids) } ?? true } else { agreed == nil }
        guard covered else { return .waiting(unsent) }
        record("close")
        return .closed
    }

    var syncReport: SyncReport { report.value }
    func syncReports() -> AsyncStream<SyncReport> { report.values() }
    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool { false }

    func changes() -> AsyncStream<SourceChange> { AsyncStream { $0.finish() } }
    func submit(_ write: ItemWrite, as id: WriteID) -> Bool { true }
    func body(of item: ItemID) async throws -> ItemBody { throw SourceFailure(kind: .missing, message: "") }
    func fileURL(of item: ItemID) async throws -> URL { throw SourceFailure(kind: .missing, message: "") }
    func bodies(of items: Set<ItemID>) async throws -> [ItemBody] { [] }
    func search(_ text: String, in query: ItemQuery) async throws -> [ItemID] { [] }
    func endEditing(_ item: ItemID) {}
    /// While set, `queueSubmitted` waits, as an engine busy with a long step would.
    let queuing = Mutex(false)
    let queued = Mutex(0)

    func queueSubmitted() async {
        while queuing.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(10)) }
        queued.withLock { $0 += 1 }
    }

    /// While set, closing waits, as a copy finishing its last step does.
    let closesSlowly = Mutex(false)

    func close() async {
        record("close")
        while closesSlowly.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(10)) }
    }
}

nonisolated extension UnsentWrites {
    static func fake(_ count: Int) -> UnsentWrites {
        UnsentWrites(ids: Set((0..<count).map { "w\($0)" }))
    }
}

/// Opens a fake library for each address on the server it is given, making the copy's directory as
/// `MarfaSource.open` does.
nonisolated final class FakeServers: Sendable {
    let failure = Mutex<(any Error & Sendable)?>(nil)
    /// While set, an open waits, as a slow store would.
    let slow = Mutex(false)
    let opening = Mutex(false)
    private let made = Mutex<[FakeMarfaSource]>([])

    var opened: [FakeMarfaSource] { made.withLock { $0 } }
    var last: FakeMarfaSource? { opened.last }

    var opener: MarfaHost.Opener {
        { connection, server, location in
            if let failure = self.failure.withLock({ $0 }) { throw failure }
            self.opening.withLock { $0 = true }
            while self.slow.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(10)) }
            try FileManager.default.createDirectory(at: location.directory(for: connection), withIntermediateDirectories: true)
            let source = FakeMarfaSource(connection: connection, server: server)
            self.made.withLock { $0.append(source) }
            return source
        }
    }
}

/// Sign-ins held in memory, made without a browser: each sign-in is approved and keeps `token` as the server's
/// key, unless `answers` says otherwise. Its sign-out and its keychain read can be made to fail as a keychain's
/// can, and the server can be made to leave a revocation unconfirmed.
nonisolated final class FakeSignIn: MarfaSignIn {
    private let kept = Mutex<[MarfaConnection: String]>([:])
    private let log = Mutex<[String]>([])
    /// What the next sign-ins answer, in order, as the person or the server would; once used up, each is approved.
    let answers = Mutex<[SignInError]>([])
    /// What an approved sign-in keeps as the server's key.
    let token = Mutex("token")
    let failsSignOut = Mutex(false)
    let failsRead = Mutex(false)
    /// Whether the server confirms the revocation of a sign-in that was kept.
    let revokes = Mutex(true)
    /// Run as each sign-out begins.
    let onSignOut = Mutex<(@Sendable () -> Void)?>(nil)

    /// What the host asked, in order: `signIn <address>` and `signOut <address>`.
    var calls: [String] { log.withLock { $0 } }

    @MainActor func signIn(to connection: MarfaConnection, with browser: MarfaBrowser) async throws {
        log.withLock { $0.append("signIn \(connection.address.absoluteString)") }
        if let answer = answers.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) { throw answer }
        let token = token.withLock { $0 }
        kept.withLock { $0[connection] = token }
    }

    func server(for connection: MarfaConnection) throws -> Server? {
        if failsRead.withLock({ $0 }) { throw SourceFailure(kind: .denied, message: "The keychain refused.") }
        return kept.withLock { $0[connection] }.map { Server(url: connection.address, key: $0) }
    }

    func signOut(of connection: MarfaConnection) async throws -> Bool {
        onSignOut.withLock { $0 }?()
        log.withLock { $0.append("signOut \(connection.address.absoluteString)") }
        if failsSignOut.withLock({ $0 }) { throw SourceFailure(kind: .denied, message: "The keychain refused.") }
        let removed = kept.withLock { $0.removeValue(forKey: connection) }
        return removed == nil || revokes.withLock { $0 }
    }

    /// The token kept for `connection`, nil when signed out.
    func token(for connection: MarfaConnection) -> String? {
        kept.withLock { $0[connection] }
    }

    /// A sign-in made by an earlier launch.
    func keep(_ token: String, for connection: MarfaConnection) {
        kept.withLock { $0[connection] = token }
    }
}

/// Stands for the system's web authentication session, which `FakeSignIn` never shows.
let testBrowser: MarfaBrowser = { _ in throw SignInError.canceled }

/// A host on its own defaults, sign-ins and store directory, all removed when the test ends.
@MainActor final class HostBench {
    let root = URL.temporaryDirectory.appending(path: "MarfaHostTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let suite = "MarfaHostTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let signIns = FakeSignIn()
    let location: MarfaStoreLocation
    let servers = FakeServers()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        location = try MarfaStoreLocation(root: root)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    func host(opener: MarfaHost.Opener? = nil) -> MarfaHost {
        MarfaHost(defaults: defaults, signIns: signIns, location: location, opener: opener ?? servers.opener)
    }

    /// A host that opens real copies, as the app does.
    func realHost() -> MarfaHost {
        MarfaHost(defaults: defaults, signIns: signIns, location: location)
    }

    var savedAddress: String? { defaults.string(forKey: "MarfaAddress") }

    func hasCopy(_ connection: MarfaConnection) -> Bool {
        FileManager.default.fileExists(atPath: location.directory(for: connection).path)
    }
}

@MainActor func eventually(_ timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let end = clock.now + timeout
    while clock.now < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@MainActor struct MarfaHostTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    private func expect(_ problem: MarfaHost.Problem, _ work: () async throws(MarfaHost.Problem) -> Void) async {
        do {
            try await work()
            Issue.record("expected \(problem)")
        } catch {
            #expect(error == problem)
        }
    }

    @Test func signingInKeepsTheAddressAndPaintsBeforeTheServer() async throws {
        let bench = try HostBench()
        let host = bench.host()
        bench.signIns.token.withLock { $0 = "approved" }
        try await host.connect(address: " HTTP://First.test:8210/ ", with: testBrowser)
        #expect(host.connection == first)
        #expect(bench.savedAddress == "http://first.test:8210")
        #expect(bench.signIns.calls == ["signIn http://first.test:8210"])
        #expect(bench.signIns.token(for: first) == "approved")
        let source = try #require(bench.servers.last)
        #expect(source.server.url == first.address)
        #expect(source.server.key == "approved")
        #expect(host.source === source)
        #expect(host.state == .connecting)
        #expect(source.calls == ["refresh"])
        source.state.set(.online)
        #expect(await eventually { host.state == .online })
        source.state.set(.offline(reason: "network: refused"))
        #expect(await eventually { host.state == .offline(reason: "network: refused") })
        source.state.set(.stopped(.damaged))
        #expect(await eventually { host.state == .unavailable(.damaged) })
    }

    /// An address that names no server is refused before the browser opens.
    @Test func anUntidyAddressIsReadAndABadOneNeverSignsIn() async throws {
        let bench = try HostBench()
        let host = bench.host()
        for address in ["not a server", "marfa.example", "ftp://first.test", "http://user:pass@first.test", "", "   "] {
            await expect(.notAServer) { () throws(MarfaHost.Problem) in try await host.connect(address: address, with: testBrowser) }
        }
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(bench.savedAddress == nil)
        #expect(bench.signIns.calls.isEmpty)
        #expect(bench.servers.opened.isEmpty)

        try await host.connect(address: "\n  https://Marfa.Example.com:443/// \t", with: testBrowser)
        #expect(host.connection == (try MarfaConnection(address: "https://marfa.example.com:443")))
        #expect(bench.signIns.calls == ["signIn https://marfa.example.com:443"])
    }

    /// Closing the browser, declining, or a server that can't finish the sign-in leaves everything as it was.
    @Test(arguments: [
        (SignInError.canceled, MarfaHost.Problem.signInCanceled),
        (.denied, .notApproved),
        (.unavailable(message: "network: refused"), .signInFailed),
        (.refused(code: "invalid_scope", message: "No such scope."), .signInFailed),
        (.stateMismatch, .signInFailed),
    ])
    func aSignInThatDoesNotFinishChangesNothing(answer: SignInError, problem: MarfaHost.Problem) async throws {
        let bench = try HostBench()
        let host = bench.host()
        bench.signIns.answers.withLock { $0 = [answer] }
        await expect(problem) { () throws(MarfaHost.Problem) in try await host.connect(address: "http://first.test:8210", with: testBrowser) }
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(bench.savedAddress == nil)
        #expect(bench.signIns.token(for: first) == nil)
        #expect(bench.servers.opened.isEmpty)
        #expect(!bench.hasCopy(first))
    }

    @Test func aCopyThatCannotBeOpenedIsAPlainProblemAndSignsOut() async throws {
        let bench = try HostBench()
        let host = bench.host()
        bench.servers.failure.withLock { $0 = CopyFailure.damaged }
        await expect(.unavailable(.damaged)) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://first.test:8210", with: testBrowser)
        }
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(bench.savedAddress == nil)
        #expect(bench.signIns.calls == ["signIn http://first.test:8210", "signOut http://first.test:8210"])
        #expect(bench.signIns.token(for: first) == nil)
    }

    /// The server ended the sign-in: the person signs in again, and the copy opens again on the new sign-in with
    /// everything that waits in it.
    @Test func aSignedOutLibrarySignsInAgainAndKeepsItsCopy() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        source.state.set(.signedOut)
        #expect(await eventually { host.state == .signedOut })

        bench.signIns.token.withLock { $0 = "again" }
        try await host.signInAgain(with: testBrowser)
        #expect(source.calls == ["refresh", "close"])
        #expect(bench.servers.opened.count == 2)
        let reopened = try #require(bench.servers.last)
        #expect(host.source === reopened)
        #expect(reopened.server.key == "again")
        #expect(host.connection == first)
        #expect(host.state == .connecting)
        #expect(bench.hasCopy(first))
        #expect(!bench.signIns.calls.contains { $0.hasPrefix("signOut") })

        // Signing in to the same address again does the same, and never asks about the copy.
        try await host.connect(address: "http://first.test:8210/", with: testBrowser)
        #expect(bench.servers.opened.count == 3)
        #expect(host.source === bench.servers.last)
    }

    @Test func aSignInAgainThatDoesNotFinishLeavesTheLibraryAsItWas() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        let source = try #require(bench.servers.last)
        source.state.set(.signedOut)
        #expect(await eventually { host.state == .signedOut })

        bench.signIns.answers.withLock { $0 = [.canceled] }
        await expect(.signInCanceled) { () throws(MarfaHost.Problem) in try await host.signInAgain(with: testBrowser) }
        #expect(host.source === source)
        #expect(source.calls == ["refresh"])
        #expect(host.state == .signedOut)
        #expect(bench.signIns.token(for: first) == "token")
        #expect(!host.isBusy)
    }

    /// A sign-in gone between reading it and opening the copy is a sign-out, not a damaged copy.
    @Test func aCopyRefusedForWantOfASignInIsSignedOut() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.signIns.keep("k", for: first)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .denied, message: "The app is not signed in to this server.") }
        let host = bench.host()
        await host.launch()
        #expect(host.state == .signedOut)
        #expect(host.connection == first)
    }

    /// A launch the Keychain refuses shows the library as unavailable, in the app's words, and Try Again opens it
    /// once the Keychain gives the sign-in.
    @Test func aSignInTheKeychainWontGiveIsAPlainProblem() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.signIns.keep("k", for: first)
        bench.signIns.failsRead.withLock { $0 = true }
        let host = bench.host()
        await host.launch()
        #expect(host.source == nil)
        #expect(host.state == .unavailable(.keychain))
        #expect(host.connection == first)
        await expect(.keychain) { () throws(MarfaHost.Problem) in
            try await host.signInAgain(with: testBrowser)
        }
        #expect(host.state == .unavailable(.keychain))

        bench.signIns.failsRead.withLock { $0 = false }
        try await host.reopen()
        #expect(host.source === bench.servers.last)
        #expect(host.state == .connecting)
    }

    /// Try Again on a copy whose following stopped asks it to follow the server again, and opens nothing.
    @Test func tryingAgainOnAnOpenCopyFollowsTheServerAgain() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        let source = try #require(bench.servers.last)
        source.state.set(.stopped(.other))
        #expect(await eventually { host.state == .unavailable(.other) })
        try await host.reopen()
        #expect(source.calls == ["refresh", "refresh"])
        #expect(bench.servers.opened.count == 1)
    }

    /// A server that doesn't confirm the revocation leaves MAPP's access standing there, which the person is told.
    @Test func aRevocationTheServerDoesNotConfirmIsReported() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        bench.signIns.revokes.withLock { $0 = false }
        await expect(.notRemoved(signIn: true, copy: false)) { () throws(MarfaHost.Problem) in try await host.disconnect() }
        #expect(host.connection == nil)
        #expect(bench.signIns.token(for: first) == nil, "the Keychain no longer holds it")
        #expect(!bench.hasCopy(first))
    }

    @Test func leavingWithWritesWaitingNeedsAChoice() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })

        await expect(.changesWaiting(.fake(2))) { () throws(MarfaHost.Problem) in try await host.disconnect() }
        #expect(host.connection == first)
        #expect(host.source === source)
        #expect(!source.calls.contains("close"))

        try await host.disconnect(.keepCopy)
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(host.source == nil)
        #expect(host.report == SyncReport())
        #expect(source.calls.last == "close")
        #expect(bench.savedAddress == nil)
        #expect(bench.signIns.token(for: first) == nil)
        #expect(bench.hasCopy(first))

        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        try #require(bench.servers.last).report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })
        try await host.disconnect(.discardCopy(.fake(2)))
        #expect(!bench.hasCopy(first))
    }

    /// Text a page hands over as the copy is left reaches the copy before it reads its queue and closes, so it is
    /// asked about rather than lost.
    @Test func editsHandedOverAsACopyIsLeftAreInItWhenItCloses() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        let source = try #require(bench.servers.last)
        host.handOverEdits = { source.report.set(SyncReport(waiting: 1, queueRead: true)); return true }

        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in try await host.disconnect() }
        #expect(host.source === source)
        #expect(!source.calls.contains("close"))

        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", with: testBrowser)
        }
        #expect(host.connection == first)
        #expect(!source.calls.contains("close"))
    }

    @Test func aRejectedEditorFlushKeepsTheCurrentLibraryOpen() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        let source = try #require(host.source as? FakeMarfaSource)
        host.handOverEdits = { false }
        do { try await host.disconnect(.keepCopy); Issue.record("Leaving was approved after the editor rejected saving") }
        catch { #expect(error == .editing) }
        #expect(host.source === source)
        #expect(!source.calls.contains("close"))
        #expect(!host.isBusy)
    }

    @Test func refusedWritesCountAsWaiting() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        let refused = SyncProblemEntry(
            id: .write("w"), itemID: ItemID("i"), kind: .refused, change: .create, reason: SyncProblem(code: "x"),
            content: SyncContent(title: "Kept"), actions: [.discard])
        try #require(bench.servers.last).report.set(SyncReport(problems: [refused], queueRead: true))
        #expect(await eventually { host.report.problems == [refused] })
        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in try await host.disconnect() }
    }

    @Test func leavingWithNothingWaitingRemovesTheCopy() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        #expect(host.waitingChanges == 0)
        try await host.disconnect()
        #expect(!bench.hasCopy(first))
        #expect(bench.signIns.token(for: first) == nil)
    }

    /// Until the copy's queue is read, nothing is known of what waits in it.
    @Test func aCopyNotYetReadNeedsAChoice() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        try #require(bench.servers.last).report.set(SyncReport())
        #expect(await eventually { host.waitingChanges == nil })
        await expect(.changesWaiting(nil)) { () throws(MarfaHost.Problem) in try await host.disconnect() }
    }

    @Test func anotherAddressWarnsAndKeepsTheFirstUntilTheSecondOpens() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        let old = try #require(bench.servers.last)
        old.report.set(SyncReport(waiting: 1, queueRead: true))
        #expect(await eventually { host.waitingChanges == 1 })

        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", with: testBrowser)
        }
        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://second.test:8210", with: testBrowser)
        }
        bench.servers.failure.withLock { $0 = CopyFailure.storageFull }
        await expect(.unavailable(.storageFull)) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", with: testBrowser, choice: .keepCopy)
        }
        #expect(host.connection == first)
        #expect(host.source === old)
        #expect(bench.signIns.token(for: first) != nil)
        #expect(bench.signIns.token(for: second) == nil)

        bench.servers.failure.withLock { $0 = nil }
        try await host.changeAddress(to: "http://second.test:8210", with: testBrowser, choice: .keepCopy)
        #expect(host.connection == second)
        #expect(host.source === bench.servers.last)
        #expect(bench.savedAddress == "http://second.test:8210")
        #expect(bench.signIns.token(for: first) == nil)
        #expect(bench.signIns.token(for: second) != nil)
        #expect(old.calls.last == "close")
        #expect(bench.hasCopy(first))
    }

    @Test func aLaunchReconnectsFromTheCopyWithoutWaitingOnTheServer() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.signIns.keep("k", for: first)
        let host = bench.host()
        await host.launch()
        let source = try #require(bench.servers.last)
        #expect(host.source === source)
        #expect(host.connection == first)
        // The fake never answers, so a launch that waited on the server would not have returned.
        #expect(host.state == .connecting)
        #expect(source.calls == ["refresh"])
        await host.launch()
        #expect(bench.servers.opened.count == 1)
    }

    @Test func aLaunchWithoutASignInAsksForOne() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        let host = bench.host()
        await host.launch()
        #expect(host.state == .signedOut)
        #expect(host.connection == first)
        #expect(host.source == nil)
        try await host.signInAgain(with: testBrowser)
        #expect(host.source === bench.servers.last)
        #expect(host.state == .connecting)
    }

    @Test func aLaunchWithNothingSavedDoesNothing() async throws {
        let bench = try HostBench()
        let host = bench.host()
        await host.launch()
        #expect(host.state == .disconnected)
        #expect(bench.servers.opened.isEmpty)
        await expect(.notConnected) { () throws(MarfaHost.Problem) in try await host.signInAgain(with: testBrowser) }
    }
}

/// Findings from review, each first seen failing on the code before its fix.
@MainActor struct MarfaHostReviewTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    /// Writes made while the new address's copy opens, slowly, are not discarded with the old copy.
    @Test func writesMadeWhileAnotherAddressOpensKeepTheOldCopy() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        let old = try #require(bench.servers.last)
        bench.servers.opening.withLock { $0 = false }
        bench.servers.slow.withLock { $0 = true }
        let change = Task { try await host.changeAddress(to: "http://second.test:8210", with: testBrowser) }
        #expect(await eventually { bench.servers.opening.withLock { $0 } })
        old.report.set(SyncReport(waiting: 1, queueRead: true))
        try await Task.sleep(for: .milliseconds(100))
        bench.servers.slow.withLock { $0 = false }
        let result = await change.result
        guard case .failure(let error) = result else {
            Issue.record("left the old copy with a write waiting")
            return
        }
        #expect(error as? MarfaHost.Problem == .changesWaiting(.fake(1)))
        #expect(host.connection == first)
        #expect(host.source === old)
        #expect(bench.hasCopy(first))
        #expect(bench.signIns.token(for: first) != nil)
        #expect(bench.signIns.token(for: second) == nil)
        #expect(!old.calls.contains("close"))
        #expect(bench.servers.opened.count == 2)
        #expect(bench.servers.last?.calls.last == "close")
    }

    @Test func aSignInThatCannotBeRemovedIsReported() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        bench.signIns.failsSignOut.withLock { $0 = true }
        do {
            try await host.disconnect(.keepCopy)
            Issue.record("said the sign-in was removed")
        } catch {}
        #expect(bench.signIns.token(for: first) == "token")
    }

    /// A copy the person chose to discard, which could not be removed, is never opened again as it was.
    @Test func aCopyThatCannotBeRemovedIsReportedAndNotResumed() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bench.root.path)
        do {
            try await host.disconnect(.discardCopy(nil))
            Issue.record("said the copy was removed")
        } catch {}
        #expect(bench.hasCopy(first))
        do {
            try await host.connect(address: "http://first.test:8210", with: testBrowser)
            Issue.record("opened a copy the person discarded")
        } catch {}
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bench.root.path)
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        #expect(host.source != nil)
        #expect(bench.servers.opened.count == 2)
    }
}

/// The second review's findings, each first seen failing on the code before its fix.
@MainActor struct MarfaHostSecondReviewTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")

    /// The copy is marked discarded before anything is removed, so a launch after a crash part way never sends
    /// what the person chose to discard.
    @Test func aCopyIsMarkedDiscardedBeforeItIsRemoved() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        let suite = bench.suite
        let seen = Mutex<[String]?>(nil)
        bench.signIns.onSignOut.withLock {
            $0 = { seen.withLock { $0 = UserDefaults(suiteName: suite)?.stringArray(forKey: "MarfaDiscardedCopies") ?? [] } }
        }
        try await host.disconnect()
        #expect(seen.withLock { $0 } == ["http://first.test:8210"])
        #expect(bench.defaults.stringArray(forKey: "MarfaDiscardedCopies") ?? [] == [])
        #expect(!bench.hasCopy(first))
    }

    @Test func aSignInAndACopyThatCannotBeRemovedAreBothReported() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        bench.signIns.failsSignOut.withLock { $0 = true }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bench.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bench.root.path) }
        do {
            try await host.disconnect()
            Issue.record("said the sign-in and the copy were removed")
        } catch {
            #expect(error == .notRemoved(signIn: true, copy: true))
        }
    }
}

/// The host over a real copy whose server refuses every connection.
@MainActor @Suite(.serialized)
struct MarfaHostOfflineTests {
    private let address = "http://127.0.0.1:9"

    /// The choice the person makes after being shown `problem`.
    private static func discard(after problem: MarfaHost.Problem?) -> MarfaHost.DisconnectChoice {
        if case .changesWaiting(let shown) = problem { .discardCopy(shown ?? UnsentWrites(ids: [])) } else { .discardCopy(UnsentWrites(ids: [])) }
    }

    private static func count(_ problem: MarfaHost.Problem) -> Int? {
        if case .changesWaiting(let unsent) = problem { unsent?.count } else { nil }
    }

    @Test(.timeLimit(.minutes(1)))
    func aKeptCopyGoesOnWhereItWasLeft() async throws {
        let bench = try HostBench()
        let host = bench.realHost()
        let connection = try MarfaConnection(address: address)
        try await host.connect(address: address, with: testBrowser)
        #expect(await eventually { host.report.queueRead })
        let source = try #require(host.source)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST kept", body: "Waiting")), as: WriteID())
        #expect(await eventually { host.report.waiting == 1 })
        #expect(host.report.oldestWaiting != nil)

        do {
            try await host.disconnect()
            Issue.record("left a copy with a write waiting")
        } catch {
            #expect(Self.count(error) == 1, "\(error)")
        }
        try await host.disconnect(.keepCopy)
        #expect(bench.hasCopy(connection))

        try await host.connect(address: address, with: testBrowser)
        #expect(await eventually { host.report.waiting == 1 })
        let log = ChangeLog(try #require(host.source as? MarfaSource))
        #expect(await log.wait { $0.item(titled: "MAPPTEST kept")?.sync == .waiting(writes: 1) } != nil)

        try await host.disconnect(.discardCopy(nil))
        #expect(!bench.hasCopy(connection))
    }

    /// A sign-in the server ends expires the copy; it waits for the person to sign in again rather than hydrating
    /// again at once.
    @Test(.timeLimit(.minutes(1)))
    func anEndedSignInWaitsForTheNextOne() async throws {
        let bench = try HostBench()
        let host = bench.realHost()
        try await host.connect(address: address, with: testBrowser)
        let source = try #require(host.source as? MarfaSource)
        #expect(await eventually { if case .offline = host.state { true } else { false } })
        let ended = MarfaError.copyExpired(reason: "credential_ended", message: "the sign-in ended")
        source.events.yield(.change(Change(origin: .stopped(ended), itemId: nil, edgeId: nil)))
        #expect(await eventually { host.state == .signedOut })
        try await Task.sleep(for: .seconds(1))
        #expect(host.state == .signedOut)

        try await host.signInAgain(with: testBrowser)
        let reopened = try #require(host.source as? MarfaSource)
        #expect(reopened !== source)
        // Hydrating again against a closed port fails at once, which shows the new sign-in was used.
        #expect(await eventually { if case .offline = host.state { true } else { false } }, "\(host.state)")
        try await host.disconnect(.discardCopy(nil))
    }

    /// The count comes from the copy once the write is queued, not from a report not yet passed on.
    @Test(.timeLimit(.minutes(1)))
    func aWriteMadeJustBeforeLeavingIsNotLost() async throws {
        let bench = try HostBench()
        let host = bench.realHost()
        let connection = try MarfaConnection(address: address)
        try await host.connect(address: address, with: testBrowser)
        #expect(await eventually { host.report.queueRead })
        let source = try #require(host.source)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST last", body: "Just typed")), as: WriteID())
        do {
            try await host.disconnect()
            Issue.record("left a copy with a write waiting")
        } catch {
            #expect(Self.count(error) == 1, "\(error)")
        }
        #expect(bench.hasCopy(connection))
        #expect(host.source != nil)
        try await host.disconnect(.discardCopy(nil))
    }

    /// A write that lands while the person is being asked, such as an editor's late save, is not discarded with
    /// what they were shown.
    @Test(.timeLimit(.minutes(1)))
    func aWriteMadeAfterThePersonWasAskedIsNotDiscarded() async throws {
        let bench = try HostBench()
        let host = bench.realHost()
        let connection = try MarfaConnection(address: address)
        try await host.connect(address: address, with: testBrowser)
        #expect(await eventually { host.report.queueRead })
        let source = try #require(host.source)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST shown", body: "One")), as: WriteID())
        var shown: MarfaHost.Problem?
        do {
            try await host.disconnect()
        } catch {
            shown = error
        }
        #expect(shown != nil)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST late", body: "Two")), as: WriteID())
        do {
            try await host.disconnect(Self.discard(after: shown))
            Issue.record("discarded a write made after the person was asked")
        } catch {
            #expect(Self.count(error) == 2, "\(error)")
        }
        #expect(bench.hasCopy(connection))
        #expect(host.source != nil)
        try await host.disconnect(.keepCopy)
    }

    @Test(.timeLimit(.minutes(1)))
    func aWriteMadeWhileMovingAddressAfterThePersonWasAskedIsNotDiscarded() async throws {
        let bench = try HostBench()
        let host = bench.realHost()
        let connection = try MarfaConnection(address: address)
        let other = "http://127.0.0.1:10"
        try await host.connect(address: address, with: testBrowser)
        #expect(await eventually { host.report.queueRead })
        let source = try #require(host.source)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST shown", body: "One")), as: WriteID())
        var shown: MarfaHost.Problem?
        do {
            try await host.changeAddress(to: other, with: testBrowser)
        } catch {
            shown = error
        }
        #expect(shown != nil)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST late", body: "Two")), as: WriteID())
        do {
            try await host.changeAddress(to: other, with: testBrowser, choice: Self.discard(after: shown))
            Issue.record("discarded a write made after the person was asked")
        } catch {
            #expect(Self.count(error) == 2, "\(error)")
        }
        #expect(host.connection == connection)
        #expect(bench.hasCopy(connection))
        #expect(!bench.hasCopy(try MarfaConnection(address: other)))
        try await host.disconnect(.keepCopy)
    }

    @Test(.timeLimit(.minutes(1)))
    func aDamagedCopyIsAPlainProblem() async throws {
        let bench = try HostBench()
        let host = bench.realHost()
        let connection = try MarfaConnection(address: address)
        try FileManager.default.createDirectory(at: bench.location.directory(for: connection), withIntermediateDirectories: true)
        try Data("not a store".utf8).write(to: bench.location.store(for: connection))
        do {
            try await host.connect(address: address, with: testBrowser)
            Issue.record("opened a damaged copy")
        } catch {
            #expect(error == .unavailable(.damaged))
        }
        #expect(host.state == .disconnected)
        #expect(host.source == nil)
    }
}

extension LiveMarfaTests {
    /// Runs against the test instance only when it is configured, as `MarfaSourceLiveTests` does, each on a copy of
    /// its own that it removes.
    @MainActor @Suite(.serialized, .enabled(if: LiveMarfa.isConfigured))
    struct MarfaHostLiveTests {
        /// The test instance's key stands in for the sign-in, which no test makes through a browser.
        private func host(_ bench: HostBench) -> MarfaHost {
            bench.signIns.token.withLock { $0 = LiveMarfa.key ?? "" }
            return bench.realHost()
        }

        @Test(.timeLimit(.minutes(2)))
        func aRefusedCreateIsAProblemThePersonCanCopyAndDiscard() async throws {
            let bench = try HostBench()
            let host = host(bench)
            let made = LiveMarfa.Made()
            do {
                try await refuseAndDiscard(host, made)
            } catch {
                await LiveMarfa.purge(made.ids)
                throw error
            }
            await LiveMarfa.purge(made.ids)
            try await host.disconnect(.discardCopy(nil))
        }

        private func refuseAndDiscard(_ host: MarfaHost, _ made: LiveMarfa.Made) async throws {
            try await host.connect(address: try #require(LiveMarfa.address), with: testBrowser)
            #expect(await eventually(.seconds(30)) { host.state == .online && host.report.queueRead })

            let title = "MAPPTEST refused \(UUID().uuidString.prefix(8))"
            let id = made.mint()
            // The server makes no items of its own reserved types, so this is refused and nothing is made.
            try #require(host.source).submit(.create(id: id, ItemDraft(type: TypeID("system.folder"), title: title)), as: WriteID())
            #expect(await eventually(.seconds(30)) { !host.report.problems.isEmpty })
            let entry = try #require(host.report.problems.first { $0.itemID == id })
            #expect(entry.kind == .refused)
            #expect(entry.change == .create)
            #expect(entry.reason?.code == "type_not_permitted")
            #expect(entry.reason?.message?.isEmpty == false)
            #expect(entry.copyText == title)
            #expect(entry.actions == [.discard])
            #expect(host.waitingChanges == 1)

            let source = try #require(host.source)
            #expect(try await source.resolve(entry.id, by: .tryAgain) == false)
            #expect(try await source.resolve(entry.id, by: .discard))
            #expect(await eventually { host.report.problems.isEmpty })
            let marfa = try #require(source as? MarfaSource)
            #expect(try await marfa.copy.queue.all().allSatisfy { $0.itemId != id.rawValue })
            #expect(host.waitingChanges == 0)
        }

        /// What the person typed after a create the server refused is shown, and copied, with it.
        @Test(.timeLimit(.minutes(2)))
        func anEditBehindARefusedCreateIsPartOfItsProblem() async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaHostTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            let made = LiveMarfa.Made()
            let connection = try MarfaConnection(address: try #require(LiveMarfa.address))
            let source = try await MarfaSource.open(
                connection, server: Server(url: connection.address, key: try #require(LiveMarfa.key)),
                location: try MarfaStoreLocation(root: root))
            do {
                let log = ChangeLog(source)
                _ = try #require(await log.wait { $0.snapshot != nil })
                // Queued before the copy is first hydrated, so neither goes until both are queued.
                let id = made.mint()
                source.submit(.create(id: id, ItemDraft(type: TypeID("system.folder"), title: "MAPPTEST first words")), as: WriteID())
                let created = try #require(await log.wait { $0.snapshot?.items.contains { $0.id == id } == true })
                let version = try #require(created.snapshot?.items.first { $0.id == id }?.version)
                source.submit(
                    .editProperties(id, ["title": .string("MAPPTEST first words, then everything typed after")], base: version, undoing: nil),
                    as: WriteID())
                #expect(await eventually { source.syncReport.waiting == 2 })
                source.refresh()
                #expect(await eventually(.seconds(30)) { source.syncReport.problems.contains { $0.itemID == id } })
                let entry = try #require(source.syncReport.problems.first { $0.itemID == id })
                #expect(entry.copyText == "MAPPTEST first words, then everything typed after")
                #expect(entry.dependents.count == 1)
                #expect(try await source.resolve(entry.id, by: .discard))
                #expect(await eventually { source.syncReport.problems.isEmpty })
                #expect(try await source.copy.queue.all().allSatisfy { $0.itemId != id.rawValue })
            } catch {
                await source.close()
                await LiveMarfa.purge(made.ids)
                throw error
            }
            await source.close()
            await LiveMarfa.purge(made.ids)
        }

        /// A sign-in the server refuses waits for the next, on a throwaway copy, so the real key is never revoked.
        @Test(.timeLimit(.minutes(2)))
        func aRefusedSignInWaitsUntilThePersonSignsInAgain() async throws {
            let bench = try HostBench()
            let host = host(bench)
            let key = try #require(LiveMarfa.key)
            bench.signIns.token.withLock { $0 = "mapptest-not-a-key-\(UUID().uuidString)" }
            try await host.connect(address: try #require(LiveMarfa.address), with: testBrowser)
            #expect(await eventually(.seconds(30)) { host.state == .signedOut }, "\(host.state)")
            bench.signIns.token.withLock { $0 = key }
            try await host.signInAgain(with: testBrowser)
            #expect(await eventually(.seconds(30)) { host.state == .online }, "\(host.state)")
            try await host.disconnect(.discardCopy(nil))
        }
    }
}

/// The modes a window would read while a step runs: sampled whenever the step waits, which is when a window can
/// draw.
@MainActor final class ModeWatch {
    private(set) var seen: [Libraries.Mode] = []
    private var watching: Task<Void, Never>?

    init(_ libraries: Libraries) {
        watching = Task { [weak self] in
            while !Task.isCancelled {
                self?.seen.append(libraries.mode)
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    func stop() {
        watching?.cancel()
    }
}

/// The connect review's findings for the host, each failing on the code before its fix.
@MainActor struct MarfaHostConnectReviewTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    private func libraries(_ bench: HostBench) throws -> Libraries {
        let defaults = try #require(UserDefaults(suiteName: "MarfaHostConnectReviewTests-\(UUID().uuidString)"))
        return Libraries(folder: NotesFolder(defaults: defaults), host: bench.host())
    }

    /// A quit while the sign-in and the copy are removed must not leave the address behind, or the next launch
    /// opens the server just left, signed out.
    @Test(arguments: [MarfaHost.DisconnectChoice.keepCopy, .discardCopy(nil)])
    func leavingAServerForgetsItsAddressBeforeRemovingAnything(choice: MarfaHost.DisconnectChoice) async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", with: testBrowser)
        let suite = bench.suite
        let seen = Mutex<String?>("not asked")
        bench.signIns.onSignOut.withLock {
            $0 = { seen.withLock { $0 = UserDefaults(suiteName: suite)?.string(forKey: "MarfaAddress") } }
        }
        try await host.disconnect(choice)
        #expect(seen.withLock { $0 } == nil, "the address was still saved when the sign-in went")
        #expect(bench.signIns.token(for: first) == nil)
        #expect(bench.hasCopy(first) == (choice == .keepCopy), "a kept copy stays, a discarded one goes")

        let next = bench.host()
        await next.launch()
        #expect(next.configuredConnection == nil)
        #expect(next.source == nil)
    }

    /// The windows go from one server's library to the other's, never through the notes folder, while the old
    /// sign-in and copy are removed.
    @Test func switchingServersNeverShowsTheFolderBetween() async throws {
        let bench = try HostBench()
        let libraries = try libraries(bench)
        try await libraries.host.connect(address: "http://first.test:8210", with: testBrowser)
        bench.signIns.onSignOut.withLock { $0 = { Thread.sleep(forTimeInterval: 0.2) } }

        let watch = ModeWatch(libraries)
        try await libraries.host.changeAddress(to: "http://second.test:8210", with: testBrowser)
        watch.stop()
        #expect(!watch.seen.contains(.files), "\(watch.seen)")
        #expect(watch.seen.allSatisfy { $0 == .marfa }, "\(watch.seen)")
        #expect(libraries.host.connection == second)
    }

    /// A copy that closes as the person signs in again is waited for while it opens again, not shown as the notes
    /// folder.
    @Test func aCopyOpenedAgainAfterSigningInIsWaitedForNotShownAsTheFolder() async throws {
        let bench = try HostBench()
        let libraries = try libraries(bench)
        try await libraries.host.connect(address: "http://first.test:8210", with: testBrowser)
        let source = try #require(bench.servers.last)
        source.state.set(.signedOut)
        source.closesSlowly.withLock { $0 = true }

        let watch = ModeWatch(libraries)
        let replacing = Task { try await libraries.host.signInAgain(with: testBrowser) }
        #expect(await eventually { source.calls.contains("close") })
        try await Task.sleep(for: .milliseconds(50))
        source.closesSlowly.withLock { $0 = false }
        _ = await replacing.result
        watch.stop()
        #expect(!watch.seen.contains(.files), "\(watch.seen)")
        #expect(watch.seen.contains(.opening), "\(watch.seen)")
        #expect(libraries.mode == .marfa)
    }

    /// Quitting waits until the copy has queued every write, but only so long, so a copy that cannot answer
    /// never keeps the app from quitting.
    @Test func quittingWaitsForTheCopyToQueueButOnlySoLong() async throws {
        let bench = try HostBench()
        let libraries = try libraries(bench)
        try await libraries.host.connect(address: "http://first.test:8210", with: testBrowser)
        _ = try #require(libraries.current as? MarfaLibrary)
        let source = try #require(bench.servers.last)

        #expect(await libraries.flushEditors(within: .seconds(10)))
        #expect(source.queued.withLock { $0 } == 1)

        source.queuing.withLock { $0 = true }
        let clock = ContinuousClock()
        let start = clock.now
        #expect(await libraries.flushEditors(within: .milliseconds(200)) == false)
        #expect(clock.now - start < .seconds(5))
        source.queuing.withLock { $0 = false }
    }
}
