import AppKit
import Foundation
import Testing
@testable import MAPP

/// What a value panel lists, where it opens, and that one is open at a time.
@MainActor
struct ValueEditingTests {
    private static let task = TypeID("core.task")
    private static let words: [StatusWord] = [
        .init(value: "done", group: .completed), .init(value: "doing", group: .inProgress), .init(value: "todo", group: .notStarted),
    ]
    private static let status = ItemTypeInfo.Field(key: "status", label: "Status", kind: .status(words), declaredBy: task)
    private static let priority = ItemTypeInfo.Field(key: "priority", label: "Priority", kind: .choice(["low", "high"]), declaredBy: task)
    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(id: task, label: "Task", fields: [status, priority], titleField: "title", bodyField: "body", parent: nil)
    ])

    private static func item(_ properties: [String: PropertyValue] = [:], id: String = "10000000-0000-0000-0000-000000000001") -> Item {
        Item(
            id: ItemID(id), type: task, title: "Title", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: .now, modified: .now)
    }

    private static func library(_ items: [Item]) -> FakeItemLibrary {
        let library = FakeItemLibrary(items: items)
        library.catalogue = catalogue
        return library
    }

    private static func request(_ kind: ValueEditKind, item: Item, in library: FakeItemLibrary, write: @escaping (PropertyValue?) -> Bool = { _ in false }) -> ValueEditRequest {
        ValueEditRequest(kind: kind, library: library, item: item.id, write: write)
    }

    // MARK: Options

    @Test func statusWordsListUnderTheirGroupsAsTheTypeDeclaresThemWithAnUndeclaredWordUnderOther() {
        let rows = ValueEditOptions.statusRows(field: Self.status, current: "stale")
        let outline = rows.map { $0.role == .header ? "# " + $0.title : $0.role == .separator ? "-" : $0.title }
        let titles = ["# " + StatusBucket.group(.completed).title, "Done", "# " + StatusBucket.group(.inProgress).title, "Doing",
                      "# " + StatusBucket.group(.notStarted).title, "Todo", "# " + StatusBucket.other.title, "Stale", "-", "Not Set"]
        #expect(outline == titles)
        #expect(rows.first { $0.title == "Stale" }?.isCurrent == true)
    }

    @Test func nothingSetMarksNotSetAsCurrent() {
        let rows = ValueEditOptions.statusRows(field: Self.status, current: nil)
        #expect(rows.last?.isCurrent == true)
        #expect(rows.dropLast().allSatisfy { !$0.isCurrent })
    }

    // MARK: Quick dates

    @Test func quickDatesFollowThePersonsCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        calendar.firstWeekday = 2
        // Friday 6 November in UTC is already Saturday 7 November in Auckland.
        let now = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 11, day: 6, hour: 12))!
        let days = QuickDates.entries(now: now, calendar: calendar).map { calendar.dateComponents([.year, .month, .day], from: $0.date) }
        #expect(days.map(\.day) == [7, 8, 9])
        #expect(days.allSatisfy { $0.month == 11 })
    }

    // MARK: Frame

    private static let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func panelOpensBelowTheValueAndEndsWithANarrowValueWithinTheWidthLimits() {
        let narrow = ValuePanelFrame.placement(
            anchor: CGRect(x: 300, y: 500, width: 100, height: 20), visible: Self.screen, contentHeight: 200, floor: 220, ceiling: 320, gap: 4)
        #expect(narrow.frame == CGRect(x: 180, y: 296, width: 220, height: 200))
        #expect(!narrow.isAbove)
        let wide = ValuePanelFrame.placement(
            anchor: CGRect(x: 100, y: 500, width: 600, height: 20), visible: Self.screen, contentHeight: 200, floor: 220, ceiling: 320, gap: 4)
        #expect(wide.frame.width == 320)
        #expect(wide.frame.minX == 100)
    }

    @Test func panelFlipsAboveWhenThereIsNoRoomBelowAndStaysOnScreen() {
        let placement = ValuePanelFrame.placement(
            anchor: CGRect(x: 900, y: 100, width: 80, height: 20), visible: Self.screen, contentHeight: 300, floor: 220, ceiling: 320, gap: 4)
        #expect(placement.isAbove)
        #expect(placement.frame.minY == 124)
        #expect(placement.frame.maxX <= Self.screen.maxX)
    }

    @Test func panelShorterThanItsContentWhereNeitherSideFitsIt() {
        let placement = ValuePanelFrame.placement(
            anchor: CGRect(x: 100, y: 400, width: 200, height: 20), visible: Self.screen, contentHeight: 2000, floor: 220, ceiling: 320, gap: 4)
        #expect(placement.frame.height < 2000)
        #expect(placement.frame.minY >= 0 && placement.frame.maxY <= Self.screen.maxY)
    }

    // MARK: Writing

    @Test func aRefusedWriteKeepsThePanelOpenAndSaysWhy() {
        let item = Self.item()
        let model = ValueEditModel(Self.request(.status(Self.status), item: item, in: Self.library([item])))
        var closed = false
        model.close = { closed = true }
        model.activate(ValueEditOptions.optionID("doing"))
        #expect(!closed)
        #expect(model.notice != nil)
    }

    @Test func aTakenChoiceClosesThePanel() {
        let item = Self.item()
        let model = ValueEditModel(Self.request(.status(Self.status), item: item, in: Self.library([item]), write: { _ in true }))
        var closed = false
        model.close = { closed = true }
        model.activate(ValueEditOptions.optionID("doing"))
        #expect(closed)
        #expect(model.notice == nil)
    }

    // MARK: One at a time

    private final class FakeSession: ValueEditSession {
        let request: ValueEditRequest
        let model: ValueEditModel
        let anchor: NSView
        var window: NSWindow? { nil }
        private(set) var isOpen = false

        init(_ request: ValueEditRequest, anchor: NSView) {
            self.request = request
            self.anchor = anchor
            model = ValueEditModel(request)
        }

        func open() { isOpen = true }
        func close(restoringFocus: Bool) { isOpen = false }
        func anchorMoved() {}
    }

    private func presenter(_ sessions: Box) -> ValueEditPresenter {
        ValueEditPresenter { request, anchor, _, _ in
            let session = FakeSession(request, anchor: anchor)
            sessions.all.append(session)
            return session
        }
    }

    private final class Box { var all: [FakeSession] = [] }

    private func anchor() -> NSView {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        let view = NSView(frame: window.contentLayoutRect)
        window.contentView = view
        return view
    }

    @Test func openingASecondEditorClosesTheFirst() {
        let (one, two) = (Self.item(id: "10000000-0000-0000-0000-000000000001"), Self.item(id: "10000000-0000-0000-0000-000000000002"))
        let library = Self.library([one, two])
        let sessions = Box()
        let presenter = presenter(sessions)
        let view = anchor()
        presenter.present(Self.request(.status(Self.status), item: one, in: library), anchor: view)
        presenter.present(Self.request(.choice(Self.priority), item: two, in: library), anchor: view)
        #expect(sessions.all.count == 2)
        #expect(!sessions.all[0].isOpen && sessions.all[1].isOpen)
        presenter.dismiss()
    }

    @Test func theItemChangingClosesTheEditor() {
        let item = Self.item()
        let sessions = Box()
        let presenter = presenter(sessions)
        presenter.present(Self.request(.status(Self.status), item: item, in: Self.library([item])), anchor: anchor())
        #expect(presenter.isOpen)
        presenter.itemChanged(to: item.id)
        #expect(presenter.isOpen)
        presenter.itemChanged(to: ItemID("10000000-0000-0000-0000-000000000009"))
        #expect(!presenter.isOpen && sessions.all.first?.isOpen == false)
    }

    @Test func openingTheSameValueAgainClosesItsEditor() {
        let item = Self.item()
        let library = Self.library([item])
        let sessions = Box()
        let presenter = presenter(sessions)
        let view = anchor()
        presenter.present(Self.request(.status(Self.status), item: item, in: library), anchor: view)
        presenter.present(Self.request(.status(Self.status), item: item, in: library), anchor: view)
        #expect(!presenter.isOpen)
    }

    // MARK: The page

    @Test func theEditValueMessageCarriesTheRowAndTheValuesRectangle() throws {
        let body: [String: Any] = ["type": "editValue", "item": "10000000-0000-0000-0000-000000000001", "row": "status", "rect": [10, 20, 30, 40], "viewportHeight": 800]
        guard case .editValue(let item, let row, let rect, let height) = try #require(EditorMessage(body: body)) else {
            Issue.record("Not an editValue message")
            return
        }
        #expect(item == ItemID("10000000-0000-0000-0000-000000000001") && row == "status")
        #expect(rect == CGRect(x: 10, y: 20, width: 30, height: 40) && height == 800)
        #expect(EditorMessage(body: ["type": "editValue", "item": "x", "row": "", "rect": [1, 2, 3, 4], "viewportHeight": 1]) == nil)
    }
}
