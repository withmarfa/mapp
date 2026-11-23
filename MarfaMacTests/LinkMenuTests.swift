import Foundation
import Testing
@testable import MarfaMac

/// The menu of a link in the item's text: what the page asks for, and what the menu then offers.
struct LinkMenuTests {
    private func body(_ link: [String: Any]) -> [String: Any] {
        ["type": "linkMenu", "item": "abc", "generation": 3, "link": link, "point": [40.0, 60.0], "viewportHeight": 700.0]
    }

    private func titles(_ target: LinkMenuTarget, isEditable: Bool = true) -> [String] {
        EditorController.linkMenuEntries(for: target, isEditable: isEditable).map(\.title)
    }

    // MARK: The page's request

    @Test func aWebLinkRequestCarriesItsAddressAndWhetherItOpens() throws {
        let message = try #require(EditorMessage(body: body(["kind": "web", "text": "site", "href": "https://example.com", "openable": true])))
        guard case .linkMenu(let item, let generation, let target, let point, let height) = message else {
            Issue.record("Expected a link menu")
            return
        }
        #expect(item == ItemID("abc") && generation == 3 && height == 700)
        #expect(point == CGPoint(x: 40, y: 60))
        #expect(target == .web(text: "site", href: "https://example.com", openable: true))
    }

    @Test func anItemLinkRequestCarriesTheLinkAsAuthored() throws {
        let link: [String: Any] = ["kind": "wiki", "text": "the plan", "raw": "[[Plan#Goals|the plan]]", "target": "Plan", "heading": "Goals", "alias": "the plan"]
        let message = try #require(EditorMessage(body: body(link)))
        guard case .linkMenu(_, _, .item(let text, let parsed), _, _) = message else {
            Issue.record("Expected an item link")
            return
        }
        #expect(text == "the plan" && parsed.raw == "Plan#Goals|the plan" && parsed.name == "Plan" && parsed.heading == "Goals")
    }

    @Test func aRequestTheAppCannotReadIsDropped() {
        let web: [String: Any] = ["kind": "web", "text": "site", "href": "https://example.com", "openable": true]
        #expect(EditorMessage(body: body(["kind": "web", "text": "site", "href": "https://example.com"])) == nil, "no openable")
        #expect(EditorMessage(body: body(["kind": "other", "text": "x"])) == nil)
        #expect(EditorMessage(body: body(["kind": "wiki", "text": "x", "raw": "not a link"])) == nil)
        var noItem = body(web)
        noItem["item"] = ""
        #expect(EditorMessage(body: noItem) == nil)
        var noPoint = body(web)
        noPoint["point"] = [1.0]
        #expect(EditorMessage(body: noPoint) == nil)
    }

    // MARK: The menu

    @Test func aWebLinkOffersOpenCopyEditAndRemove() {
        let target = LinkMenuTarget.web(text: "site", href: "https://example.com", openable: true)
        let entries = EditorController.linkMenuEntries(for: target, isEditable: true)
        #expect(entries.map(\.choice) == [.open, .copy, .edit, .remove])
        #expect(entries.allSatisfy { $0.isEnabled })
    }

    @Test func anAddressThatMayNotOpenLeavesOpenDimmedAndCopyAvailable() {
        for href in ["javascript:alert(1)", "file:///etc/passwd", ""] {
            let target = LinkMenuTarget.web(text: "x", href: href, openable: false)
            let entries = EditorController.linkMenuEntries(for: target, isEditable: true)
            #expect(entries.first { $0.choice == .open }?.isEnabled == false, "\(href) is not opened")
            #expect(entries.first { $0.choice == .edit }?.isEnabled == true, "it can still be corrected")
        }
        let empty = EditorController.linkMenuEntries(for: .web(text: "x", href: "", openable: false), isEditable: true)
        #expect(empty.first { $0.choice == .copy }?.isEnabled == false, "an empty address has nothing to copy")
    }

    @Test func anItemLinkOffersOpenCopyAndRemoveButNoAddress() throws {
        let link = try #require(ItemLink(linkText: "[[Plan]]"))
        #expect(EditorController.linkMenuEntries(for: .item(text: "Plan", link), isEditable: true).map(\.choice) == [.open, .copy, .remove])
    }

    @Test func aReadOnlyPageOffersOnlyOpenAndCopy() throws {
        let link = try #require(ItemLink(linkText: "[[Plan]]"))
        for target in [LinkMenuTarget.web(text: "x", href: "https://example.com", openable: true), .item(text: "Plan", link)] {
            #expect(EditorController.linkMenuEntries(for: target, isEditable: false).map(\.choice) == [.open, .copy])
        }
    }

    @Test func theMenuNamesEachChoiceInThePersonsWords() throws {
        #expect(titles(.web(text: "x", href: "https://example.com", openable: true)) == ["Open Link", "Copy Link", "Edit Link…", "Remove Link"])
        let link = try #require(ItemLink(linkText: "[[Plan]]"))
        #expect(titles(.item(text: "Plan", link)) == ["Open", "Copy Link", "Remove Link"])
    }
}
