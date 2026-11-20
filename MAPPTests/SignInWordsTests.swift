import AuthenticationServices
import AppKit
import Foundation
import Marfa
import Testing
@testable import MAPP

/// Every way a sign-in can end is told in MAPP's own words: what happened and what to do, with nothing the package,
/// the system or the server said.
@Suite(.hangLimit)
@MainActor struct SignInWordsTests {
    /// What the package would put in a sentence: an OAuth code, an HTTP status, a system domain.
    private static let raw = ["invalid_grant", "invalid_client", "401", "NSURL", "NSCocoa", "-1009", "errSec", "Domain", "OSStatus", "refused (", "HTTP"]

    private static let cases: [(error: SignInError, outcome: SignInOutcome)] = [
        (.canceled, .canceled),
        (.denied, .denied),
        (.expired, .expired),
        (.stateMismatch, .notVerified),
        (.issuerMismatch, .notVerified),
        (.notSignedIn, .failed),
        (.notAServer, .notMarfa),
        (.otherServer, .failed),
        (.noRedirect, .failed),
        (.refused(code: "invalid_client", message: "Unknown client, HTTP 401"), .refused),
        (.unavailable(message: "The Internet connection appears to be offline. (NSURLErrorDomain -1009)"), .couldNotFinish),
        (.heldElsewhere, .inUse),
        (.unreadable(message: "The server answered 401 with invalid_grant."), .notMarfa),
    ]

    @Test func everySignInErrorCaseHasItsOutcome() {
        for (error, outcome) in Self.cases {
            #expect(SignInOutcome(error) == outcome, "\(error)")
        }
    }

    @Test func noSignInErrorsWordsReachTheNotice() throws {
        for (error, _) in Self.cases {
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

    @Test func aSignInThePersonCanceledIsToldAsNothing() {
        #expect(SignInOutcome(CancellationError()) == .canceled)
        #expect(SignInOutcome(ASWebAuthenticationSessionError(.canceledLogin)) == .canceled)
        #expect(MarfaSettingsModel.notice(for: .signIn(.canceled)) == nil)
    }

    @Test func aBrowserThatHadNoWindowToShowOverIsToldFromTheCatalog() throws {
        #expect(SignInOutcome(ASWebAuthenticationSessionError(.presentationContextNotProvided)) == .noWindow)
        #expect(SignInOutcome(ASWebAuthenticationSessionError(.presentationContextInvalid)) == .noWindow)
        #expect(SignInOutcome(NoSignInWindow()) == .noWindow)
        let notice = try #require(MarfaSettingsModel.notice(for: .signIn(.noWindow)))
        #expect(notice.title == "No Window to Sign In From")
        #expect(notice.message == "MAPP needs a window to show the server’s sign-in page over. Open a MAPP window, then try again, or use a code instead.")
    }

    @Test func aMacWithNoWindowThrowsTheAppsOwnErrorNotText() async throws {
        let signIns = SystemSignIns(bundleIdentifier: "com.withmarfa.mapp.tests", anchor: { nil })
        let connection = try MarfaConnection(address: "https://marfa.test")
        do {
            _ = try await signIns.signInWithBrowser(to: connection)
            Issue.record("a sign-in began with no window")
        } catch {
            #expect(error is NoSignInWindow)
            #expect(SignInOutcome(error) == .noWindow)
        }
    }

    @Test func otherErrorsASignInCanThrowAreToldInTheSameWay() throws {
        #expect(SignInOutcome(URLError(.notConnectedToInternet)) == .unreachable)
        #expect(SignInOutcome(URLError(.timedOut)) == .unreachable)
        struct Odd: Error, LocalizedError { var errorDescription: String? { "WebKitErrorDomain 102 invalid_grant" } }
        #expect(SignInOutcome(Odd()) == .failed)
        #expect(SignInOutcome(Keychain.Failure(status: errSecInteractionNotAllowed)) == .keychain)
        for outcome in [SignInOutcome.failed, .keychain, .unreachable, .couldNotFinish] {
            let notice = try #require(MarfaSettingsModel.notice(for: .signIn(outcome)))
            for word in Self.raw { #expect(!(notice.title + notice.message).contains(word)) }
        }
    }

    @Test func anAddressThatIsNotAMarfaServerSaysSo() throws {
        let notice = try #require(MarfaSettingsModel.notice(for: .signIn(SignInOutcome(SignInError.unreadable(message: "Not JSON.")))))
        #expect(notice.title == "Check the Address")
        #expect(notice.message.contains("isn’t a Marfa server"))
    }

    // MARK: The approval a sign-in replaced

    @Test(arguments: [false, true])
    func aSignInThatLeavesTheReplacedApprovalStandingTellsHowToEndIt(stands: Bool) async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "https://marfa.test", key: "one")
        host.notices.answerAll()
        bench.signIns.script(replacedApprovalStands: stands)
        try await host.connect(address: "https://marfa.test", key: "two")
        let told = host.notices.waiting
        if stands {
            #expect(told.map(\.title) == ["MAPP’s Earlier Approval May Still Stand"])
            let message = try #require(told.first?.message)
            #expect(message.contains("marfa apps list") && message.contains("marfa apps revoke <id>") && message.contains("approval date"))
            #expect(message.contains("https://marfa.test"), "the server is named by its address: \(message)")
            #expect(!message.contains("older MAPP entry"))
            #expect(!message.contains("Connected apps") && !message.contains("You are signed in") && !message.contains("still lists"))
        } else {
            #expect(told.isEmpty)
        }
    }

    @Test func aCodeSignInTellsItToo() async throws {
        let bench = try HostBench()
        let host = bench.host()
        let signIns = bench.signIns
        let address = try MarfaConnection(address: "https://marfa.test").address
        signIns.script(replacedApprovalStands: true)
        signIns.script(code: [.success(CodeSignIn(
            code: "ABCD-1234", address: URL(string: "https://marfa.test/device")!, completeAddress: nil,
            expiresAt: .distantFuture, finish: { signIns.save("approved", for: address); return signIns.signedIn }))])
        try await host.connect(address: "https://marfa.test", via: .code(shown: { _ in }))
        #expect(host.notices.waiting.map(\.title) == ["MAPP’s Earlier Approval May Still Stand"])
    }

    // MARK: The package's credential

    private struct Grant: ReplacedGrant { let replacedGrantStands: Bool }

    /// Both shipping sign-ins hand the package's `Credential` to this one conversion in one line, which is checked by
    /// reading since a `Credential` is made only by a real sign-in; what the person is then told is tested above.
    @Test(arguments: [false, true])
    func theConversionFromTheCredentialsAnswerKeepsWhetherTheReplacedApprovalStands(stands: Bool) {
        #expect(SignedIn(Grant(replacedGrantStands: stands)).replacedApprovalStands == stands)
    }

    // MARK: Two failures that were told wrongly

    /// The package's `.unavailable` is the server not answering or the browser not starting, so the words claim neither.
    @Test func aSignInThatCouldNotFinishDoesNotSayTheServerWasNotReached() throws {
        for message in ["The browser could not open.", "the server could not be reached: offline"] {
            #expect(SignInOutcome(SignInError.unavailable(message: message)) == .couldNotFinish)
        }
        let notice = try #require(MarfaSettingsModel.notice(for: .signIn(.couldNotFinish)))
        #expect(notice.title == "Couldn’t Finish Signing In")
        #expect(notice.message == "MAPP couldn’t finish signing in. Check your connection and try again, or sign in with a code.")
        #expect(!(notice.title + notice.message).localizedCaseInsensitiveContains("reach"))
    }
}
