import AuthenticationServices
import AppKit
import Darwin
import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// Every way a sign-in can end is told in the app's own words: what happened and what to do, with nothing the package,
/// the system or the server said.
@Suite(.hangLimit)
@MainActor struct SignInWordsTests {
    /// What the package would put in a sentence: an OAuth code, an HTTP status, a system domain.
    private static let raw = ["invalid_grant", "invalid_client", "401", "NSURL", "NSCocoa", "-1009", "errSec", "Domain", "OSStatus", "refused (", "HTTP"]

    private static let cases: [SignInError] = [
        .canceled, .denied, .expired, .stateMismatch, .issuerMismatch, .notSignedIn, .notAServer, .otherServer, .noRedirect,
        .refused(code: "invalid_client", message: "Unknown client, HTTP 401"),
        .unavailable(message: "The Internet connection appears to be offline. (NSURLErrorDomain -1009)"),
        .heldElsewhere, .keptSignInChanged,
        .unreadable(message: "The server answered 401 with invalid_grant."),
    ]

    @Test func noSignInErrorsWordsReachTheNotice() throws {
        for error in Self.cases {
            guard let notice = MarfaSettingsModel.notice(for: .signIn(SignInOutcome(error))) else {
                #expect(error == .canceled, "\(error) is told as nothing")
                continue
            }
            let told = notice.title + " " + notice.message
            #expect(!told.contains(error.description), "“\(told)” repeats the package's “\(error.description)”")
            for word in Self.raw { #expect(!told.contains(word), "“\(told)” shows “\(word)” for \(error)") }
            #expect(notice.message.hasSuffix("."))
            #expect(!notice.title.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func discoveryFailuresReachTheNotice(usingCode: Bool) async throws {
        // Reserve a loopback port without listening so no other test can take it.
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        try #require(socket >= 0)
        defer { close(socket) }
        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        try withUnsafeMutablePointer(to: &local) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                try #require(bind(socket, address, length) == 0)
                try #require(getsockname(socket, address, &length) == 0)
            }
        }
        let anchor = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        let signIns = SystemSignIns(bundleIdentifier: "com.withmarfa.marfa.tests", anchor: { anchor })
        let bench = HostBench()
        let host = MarfaHost(
            defaults: bench.defaults, signIns: signIns, location: bench.location, opener: bench.servers.opener,
            describer: bench.servers.describer, cleaner: { _ in })
        let model = MarfaSettingsModel(host: host)
        for (address, title) in [
            ("https://marfa.invalid", "Can’t Find the Server"),
            ("http://127.0.0.1:\(UInt16(bigEndian: local.sin_port))", "Can’t Connect to the Server"),
        ] {
            model.address = address
            await model.connect(usingCode: usingCode)
            #expect(model.notice?.title == title)
            #expect(!model.isConnected)
            #expect(model.address == address)
            #expect(!anchor.isVisible)
        }
    }

    @Test(arguments: [false, true])
    func certificateTrustAndOtherSignInEndingsReachTheNotice(usingCode: Bool) async throws {
        let bench = HostBench()
        let model = MarfaSettingsModel(host: bench.host())
        let endings: [(SignInError, String?)] = [
            (.discoveryTransport(reason: .untrustedCertificate), "Can’t Verify the Server’s Certificate"),
            (.unavailable(message: "NSURLErrorDomain -1200"), "Couldn’t Finish Signing In"),
            (.refused(code: "invalid_client", message: "Unknown client"), "The Server Refused the Sign-In"),
            (.canceled, nil),
        ]
        for (error, title) in endings {
            if usingCode {
                bench.signIns.script(code: [.failure(error)])
            } else {
                bench.signIns.script(browser: [.failure(error)])
            }
            model.address = "https://marfa.test"
            await model.connect(usingCode: usingCode)
            #expect(model.notice?.title == title)
            if case .discoveryTransport = error {
                #expect(model.notice?.message.contains("ask whoever manages the server") == true)
            }
            #expect(!model.isConnected)
        }
    }

    @Test func aMacWithNoWindowThrowsTheAppsOwnErrorNotText() async throws {
        let signIns = SystemSignIns(bundleIdentifier: "com.withmarfa.marfa.tests", anchor: { nil })
        let connection = try MarfaConnection(address: "https://marfa.test")
        do {
            _ = try await signIns.signInWithBrowser(to: connection)
            Issue.record("a sign-in began with no window")
        } catch {
            #expect(error is NoSignInWindow)
            #expect(SignInOutcome(error) == .noWindow)
        }
    }

    // MARK: The approval a sign-in replaced

    @Test(arguments: [false, true])
    func aSignInThatLeavesTheReplacedApprovalStandingTellsHowToEndIt(stands: Bool) async throws {
        let bench = HostBench()
        let host = bench.host()
        try await host.connect(address: "https://marfa.test", key: "one")
        host.notices.answerAll()
        bench.signIns.script(replacedApprovalStands: stands)
        try await host.connect(address: "https://marfa.test", key: "two")
        let told = host.notices.waiting
        if stands {
            #expect(told.map(\.title) == ["This App’s Earlier Approval May Still Stand"])
            let message = try #require(told.first?.message)
            #expect(message.contains("marfa apps list") && message.contains("marfa apps revoke <id>") && message.contains("approval date"))
            #expect(message.contains("https://marfa.test"), "the server is named by its address: \(message)")
            #expect(!message.contains("older app entry"))
            #expect(!message.contains("Connected apps") && !message.contains("You are signed in") && !message.contains("still lists"))
        } else {
            #expect(told.isEmpty)
        }
    }

    @Test func aCodeSignInTellsItToo() async throws {
        let bench = HostBench()
        let host = bench.host()
        let signIns = bench.signIns
        let address = try MarfaConnection(address: "https://marfa.test").address
        signIns.script(replacedApprovalStands: true)
        signIns.script(code: [.success(CodeSignIn(
            code: "ABCD-1234", address: URL(string: "https://marfa.test/device")!, completeAddress: nil,
            expiresAt: .distantFuture, finish: { signIns.save("approved", for: address); return signIns.signedIn }))])
        try await host.connect(address: "https://marfa.test", via: .code(shown: { _ in }))
        #expect(host.notices.waiting.map(\.title) == ["This App’s Earlier Approval May Still Stand"])
    }

    // MARK: The package's credential

    private struct Grant: ReplacedGrant { let replacedGrantStands: Bool }

    /// Both shipping sign-ins hand the package's `Credential` to this one conversion in one line, which is checked by
    /// reading since a `Credential` is made only by a real sign-in; what the person is then told is tested above.
    @Test(arguments: [false, true])
    func theConversionFromTheCredentialsAnswerKeepsWhetherTheReplacedApprovalStands(stands: Bool) {
        #expect(SignedIn(Grant(replacedGrantStands: stands)).replacedApprovalStands == stands)
    }
}
