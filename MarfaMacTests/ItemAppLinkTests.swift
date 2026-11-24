import Foundation
import Testing
@testable import MarfaMac

/// What `marfa://` text opens an item: only the exact form Marfa writes, so a link another app hands over can never
/// name an item, or a Marfa, other than the one it spells.
struct ItemAppLinkTests {
    nonisolated static let instance = "0195f3a2-7c4e-7b21-9a3d-5e6f7a8b9c0d"
    nonisolated static let item = "0195f3a2-8d11-7e42-8b5c-1a2b3c4d5e6f"
    nonisolated static let valid = "marfa://\(instance)/\(item)"

    @Test func readsTheLinkMarfaWrites() throws {
        let link = try #require(ItemAppLink(parsing: Self.valid))
        #expect(link.instanceID == Self.instance)
        #expect(link.item == ItemID(Self.item))
    }

    @Test func aMarfaWhoseIdIsNotAUUIDv7IsStillOne() {
        #expect(ItemAppLink(parsing: "marfa://3f2504e0-4f89-41d3-9a0c-0305e82c3301/\(Self.item)") != nil)
    }

    @Test(arguments: [
        ("empty", ""),
        ("scheme only", "marfa://"),
        ("other scheme", "marfb://\(instance)/\(item)"),
        ("https", "https://\(instance)/\(item)"),
        ("no slashes", "marfa:\(instance)/\(item)"),
        ("uppercase instance", "marfa://\(instance.uppercased())/\(item)"),
        ("uppercase item", "marfa://\(instance)/\(item.uppercased())"),
        ("one uppercase digit", "marfa://\(instance)/\(item.dropLast())F"),
        ("trailing slash", "\(valid)/"),
        ("extra segment", "\(valid)/\(item)"),
        ("missing item", "marfa://\(instance)/"),
        ("missing instance", "marfa:///\(item)"),
        ("query", "\(valid)?open=1"),
        ("empty query", "\(valid)?"),
        ("fragment", "\(valid)#top"),
        ("port", "marfa://\(instance):80/\(item)"),
        ("user", "marfa://me@\(instance)/\(item)"),
        ("user and password", "marfa://me:secret@\(instance)/\(item)"),
        ("percent-encoded item", "marfa://\(instance)/\(item.replacingOccurrences(of: "-", with: "%2D"))"),
        ("percent-encoded slash", "marfa://\(instance)%2F\(item)"),
        ("leading space", " \(valid)"),
        ("trailing space", "\(valid) "),
        ("newline", "\(valid)\n"),
        ("tab inside", "marfa://\(instance)/\t\(item)"),
        ("null byte", "\(valid)\u{0}"),
        ("right-to-left mark", "marfa://\(instance)/\u{200F}\(item)"),
        ("right-to-left override", "marfa://\u{202E}\(instance)/\(item)"),
        ("zero-width space", "marfa://\(instance)/\(item.prefix(8))\u{200B}\(item.dropFirst(8))"),
        ("full-width digit", "marfa://\(instance)/\(item.dropLast())\u{FF10}"),
        ("version 4 item", "marfa://\(instance)/3f2504e0-4f89-41d3-9a0c-0305e82c3301"),
        ("wrong variant", "marfa://\(instance)/0195f3a2-8d11-7e42-cb5c-1a2b3c4d5e6f"),
        ("braced item", "marfa://\(instance)/{\(item)}"),
        ("no hyphens", "marfa://\(instance)/\(item.replacingOccurrences(of: "-", with: ""))"),
        ("dot segment", "marfa://\(instance)/../\(item)"),
        ("over long", valid + String(repeating: "0", count: 4096)),
    ])
    func refuses(_ form: String, _ text: String) {
        #expect(ItemAppLink(parsing: text) == nil, "\(form)")
    }

    @Test func buildsOnlyFromIdsInTheirForm() {
        #expect(ItemAppLink(instanceID: Self.instance.uppercased(), item: ItemID(Self.item)) == nil)
        #expect(ItemAppLink(instanceID: Self.instance, item: ItemID("note-1")) == nil)
        #expect(ItemAppLink(instanceID: "", item: ItemID(Self.item)) == nil)
    }

    @Test func aBuiltLinkReadsBackAsItself() throws {
        for _ in 0..<50 {
            let item = ItemID.mint()
            let instance = UUID().uuidString.lowercased()
            let built = try #require(ItemAppLink(instanceID: instance, item: item))
            #expect(built.url.absoluteString == "marfa://\(instance)/\(item.rawValue)")
            #expect(ItemAppLink(built.url) == built)
        }
    }
}
