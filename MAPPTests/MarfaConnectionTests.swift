import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MAPP

struct MarfaConnectionTests {
    @Test func anAddressIsOneServerHoweverItIsTyped() throws {
        let typed = try MarfaConnection(address: " HTTP://Marfa.Example:8210/ ")
        #expect(typed.address.absoluteString == "http://marfa.example:8210")
        #expect(typed == (try MarfaConnection(address: "http://marfa.example:8210")))
        #expect(try MarfaConnection(address: "https://marfa.example/api/").address.absoluteString == "https://marfa.example/api")
    }

    @Test(arguments: ["ftp://marfa.example", "marfa.example", "http://", "https://user:secret@marfa.example", "https://marfa.example/?key=1", ""])
    func anAddressThatNamesNoServerIsRefused(_ text: String) {
        #expect(throws: MarfaConnection.Problem.notAServer) { try MarfaConnection(address: text) }
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
        let signIns = MemorySignIns()
        signIns.hold("first", for: one)
        #expect(try signIns.key(for: one.address) == "first")
        #expect(try signIns.key(for: two.address) == nil)
    }

    /// Building the real sign-in touches neither the Keychain nor a window; Debug and Release differ by their
    /// bundle identifier, so they never share a sign-in or a return address.
    @Test func theRealSignInKeepsItsOwnServiceAndReturnsToTheApp() throws {
        let debug = SystemSignIns(bundleIdentifier: "com.withmarfa.mapp.debug", anchor: { nil })
        let release = SystemSignIns(bundleIdentifier: "com.withmarfa.mapp", anchor: { nil })
        #expect(debug.service == "com.withmarfa.mapp.debug.marfa-sign-in")
        #expect(release.service == "com.withmarfa.mapp.marfa-sign-in")
        #expect(debug.service != release.service)
        #expect(debug.scheme == "com.withmarfa.mapp.debug")
        #expect(SystemSignIns.scopes == ["*:read", "*:write", "edge.*:read", "edge.*:write", "items.purge", "config.manage", "schema.write"])
    }

    @Test func theAppClaimsTheSchemeTheBrowserReturnsTo() throws {
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(SystemSignIns().scheme), "\(schemes)")
    }
}
