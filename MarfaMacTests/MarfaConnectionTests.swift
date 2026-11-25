import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MarfaMac

struct MarfaConnectionTests {
    @Test func anAddressIsOneServerHoweverItIsTyped() throws {
        let typed = try MarfaConnection(address: " HTTP://Marfa.Example:8210/ ")
        #expect(typed.address.absoluteString == "http://marfa.example:8210")
        #expect(typed == (try MarfaConnection(address: "http://marfa.example:8210")))
    }

    @Test(arguments: [
        ("https://marfa.example", "https://marfa.example"), ("https://marfa.example/", "https://marfa.example"),
        ("https://marfa.example:8443", "https://marfa.example:8443"), ("http://localhost:3000", "http://localhost:3000"),
    ])
    func aServerAddressWithNothingAfterItIsAccepted(_ text: String, _ kept: String) throws {
        #expect(try MarfaConnection(address: text).address.absoluteString == kept)
    }

    @Test(arguments: [
        ("marfa-demo.cyzr.me", "https://marfa-demo.cyzr.me"),
        (" MARFA.Example:443/a?x=1#f ", "https://marfa.example:443"),
        ("https://marfa.example/%2F?x=1#f", "https://marfa.example"),
        ("http://marfa.example:80//", "http://marfa.example:80"),
        ("localhost:8210/path", "http://localhost:8210"),
        ("notes.LOCALHOST?x=1", "http://notes.localhost"),
        ("127.12.0.1#f", "http://127.12.0.1"),
        ("[::1]:8210", "http://[::1]:8210"),
        ("https://localhost:443/path", "https://localhost:443"),
    ])
    func aTypedAddressIsCompletedToItsOrigin(_ text: String, _ origin: String) throws {
        let typed = try MarfaConnection(address: text)
        let explicit = try MarfaConnection(address: origin)
        #expect(typed.address.absoluteString == origin)
        #expect(typed == explicit)
        let stores = MarfaStoreLocation(root: URL.temporaryDirectory)
        #expect(stores.store(for: typed) == stores.store(for: explicit))
    }

    /// An address names its copy and its discard marks as it was entered, so a port the scheme already means is kept.
    @Test func anAddressKeepsAPortTheSchemeAlreadyMeansAndSoItsOwnCopy() throws {
        let withPort = try MarfaConnection(address: "HTTPS://Marfa.Example:443/")
        let without = try MarfaConnection(address: "https://marfa.example")
        #expect(withPort.address.absoluteString == "https://marfa.example:443")
        #expect(withPort != without)
        let location = MarfaStoreLocation(root: URL.temporaryDirectory.appending(path: "Stores", directoryHint: .isDirectory))
        #expect(location.directory(for: withPort) != location.directory(for: without))
        #expect(location.directory(for: withPort) == location.directory(for: try MarfaConnection(address: "https://marfa.example:443/")))
    }

    @Test(arguments: [
        ("https://marfa.example:443", "https://marfa.example", true), ("https://marfa.example", "https://marfa.example:443", true),
        ("http://marfa.example:80", "http://marfa.example/", true), ("https://marfa.example:8443", "https://marfa.example", false),
        ("https://marfa.example", "https://other.example", false), ("https://marfa.example:80", "https://marfa.example", false),
    ])
    func twoAddressesAreOneServerByTheirOriginNotTheirText(_ one: String, _ other: String, _ same: Bool) throws {
        #expect(try MarfaConnection(address: one).sameServer(as: MarfaConnection(address: other)) == same)
    }

    @Test(arguments: [
        "ftp://marfa.example", "http://", "https:/marfa.example", "https//marfa.example", "http/marfa.example", "https:443", "//marfa.example",
        "/marfa.example", ".", "-marfa.example", "127.1", "2130706433", "0177.0.0.1", "marfa.example:", "marfa.example:65536", "marfa.example:99999999999999999999", "::1", "marfa example",
        "user:secret@marfa.example", "https://user:secret@marfa.example", "https://marfa.example\\other", "",
    ])
    func anAddressThatNamesNoServerIsRefused(_ text: String) {
        #expect(throws: MarfaConnection.Problem.notAServer) { try MarfaConnection(address: text) }
    }

    @Test(arguments: ["https://user@marfa.example", "https://user:secret@marfa.example", "http://:secret@marfa.example:8210/api"])
    @MainActor func anAddressWithAUserOrPasswordIsRefusedInPlainWordsBeforeAnyServerIsMade(_ text: String) throws {
        #expect(throws: MarfaConnection.Problem.notAServer) { try MarfaConnection(address: text) }
        let notice = try #require(MarfaSettingsModel.notice(for: .notAServer))
        #expect(!(notice.title + notice.message).localizedCaseInsensitiveContains("userinfo"))
        #expect(notice.message == "Enter a Marfa server address, such as marfa.example.")
    }

    @Test func eachServerKeepsItsOwnCopyInTheAppsStorage() throws {
        let root = URL.temporaryDirectory.appending(path: "Stores", directoryHint: .isDirectory)
        let location = MarfaStoreLocation(root: root)
        let one = try MarfaConnection(address: "http://one.example")
        let two = try MarfaConnection(address: "http://two.example")
        #expect(location.directory(for: one) == location.directory(for: try MarfaConnection(address: "HTTP://ONE.example/")))
        #expect(location.directory(for: one) != location.directory(for: two))
        #expect(location.store(for: one).deletingLastPathComponent() == location.directory(for: one))
        #expect(location.directory(for: one).deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
        #expect(MarfaStoreLocation.applicationSupport.path.hasPrefix(URL.applicationSupportDirectory.path))
    }

    @Test func aSignInIsKeptForItsServerAlone() throws {
        let one = try MarfaConnection(address: "http://one.example")
        let two = try MarfaConnection(address: "http://two.example")
        let signIns = ScriptedSignIns()
        signIns.hold("first", for: one)
        #expect(try signIns.key(for: one.address) == "first")
        #expect(try signIns.key(for: two.address) == nil)
    }

    /// Building the real sign-in touches neither the Keychain nor a window; Debug and Release differ by their
    /// bundle identifier, so they never share a sign-in or a return address.
    @Test func theRealSignInKeepsItsOwnServiceAndReturnsToTheApp() throws {
        let debug = SystemSignIns(bundleIdentifier: "com.withmarfa.marfa.debug", anchor: { nil })
        let release = SystemSignIns(bundleIdentifier: "com.withmarfa.marfa", anchor: { nil })
        #expect(debug.service == "com.withmarfa.marfa.debug.marfa-sign-in")
        #expect(release.service == "com.withmarfa.marfa.marfa-sign-in")
        #expect(debug.service != release.service)
        #expect(debug.scheme == "com.withmarfa.marfa.debug")
    }

    @Test func theAppClaimsTheSchemeTheBrowserReturnsTo() throws {
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(SystemSignIns().scheme), "\(schemes)")
    }
}
