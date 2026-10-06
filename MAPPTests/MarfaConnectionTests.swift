import Foundation
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
        let location = try MarfaStoreLocation(root: root)
        let one = try MarfaConnection(address: "http://one.example")
        let two = try MarfaConnection(address: "http://two.example")
        #expect(location.directory(for: one) == location.directory(for: try MarfaConnection(address: "HTTP://ONE.example/")))
        #expect(location.directory(for: one) != location.directory(for: two))
        #expect(location.store(for: one).deletingLastPathComponent() == location.directory(for: one))
        #expect(location.directory(for: one).deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
        #expect(MarfaStoreLocation.applicationSupport.path.hasPrefix(URL.applicationSupportDirectory.path))
    }

    @Test func aCopyIsNeverPutInsideTheNotesFolder() {
        let notes = URL.temporaryDirectory.appending(path: "Notes", directoryHint: .isDirectory)
        #expect(throws: MarfaStoreLocation.Problem.insideNotesFolder) {
            try MarfaStoreLocation(root: notes.appending(path: ".marfa-copy"), notesFolder: notes)
        }
        #expect(throws: MarfaStoreLocation.Problem.insideNotesFolder) {
            try MarfaStoreLocation(root: notes, notesFolder: notes)
        }
        #expect(throws: Never.self) {
            try MarfaStoreLocation(root: URL.temporaryDirectory.appending(path: "Elsewhere"), notesFolder: notes)
        }
    }

    @Test func aKeyIsKeptForItsServerAlone() throws {
        let one = try MarfaConnection(address: "http://one.example")
        let two = try MarfaConnection(address: "http://two.example")
        let keys = MemoryKeyStore()
        keys.save("first", for: one)
        #expect(keys.key(for: one) == "first")
        #expect(keys.key(for: two) == nil)
        keys.delete(for: one)
        #expect(keys.key(for: one) == nil)
        #expect(KeychainKeyStore.account(for: one) == "http://one.example")
    }
}
