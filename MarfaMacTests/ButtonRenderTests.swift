import AppKit
import Foundation
import Marfa
import SwiftUI
import Testing
@testable import MarfaMac

/// Every kind of button the main window draws, as the 22 November button rule gives it, for a pull request's pictures,
/// each in the light and the dark appearance. Drawn offscreen (`SettingsRender`), so nothing shows and nothing takes the
/// keyboard. Skipped unless `MARFA_MAC_SETTINGS_RENDERS` names a folder.
@Suite(.enabled(if: SettingsRender.isRequested), .serialized, .hangLimit)
@MainActor struct ButtonRenderTests {
    private static let schemes: [(scheme: ColorScheme, name: String)] = [(.light, "light"), (.dark, "dark")]

    /// Draws what `content` builds once for each appearance, on the window's own ground.
    private func draw(
        _ name: String, size: CGSize, settle: Duration = .milliseconds(600), @ViewBuilder _ content: () -> some View
    ) async throws {
        for (scheme, label) in Self.schemes {
            try await SettingsRender.png(
                content().background(Color(nsColor: .windowBackgroundColor)).interfaceTextStyle(),
                size: size, named: "\(name), \(label)", appearance: scheme, settle: settle)
        }
    }

    private func sampleLibrary() async throws -> MarfaLibrary {
        let library = MarfaLibrary(source: SampleLibrary.open(SampleLibrary.connection), notices: Notices())
        #expect(await eventually { library.isLoaded })
        return library
    }

    // MARK: Every style

    @Test func gallery() async throws {
        try await draw("Buttons, every role and size", size: CGSize(width: 760, height: 560)) { ButtonGallery() }
    }

    // MARK: First run

    @Test func firstRun() async throws {
        let libraries = ItemPreviewFixtures.libraries(named: "MarfaMac.ButtonRender")
        try await draw("First run", size: CGSize(width: 640, height: 420)) {
            WelcomeView(browser: Browser()).environment(libraries)
        }
    }

    @Test func cannotOpen() async throws {
        let libraries = ItemPreviewFixtures.libraries(named: "MarfaMac.ButtonRender")
        try await draw("Cannot open", size: CGSize(width: 640, height: 420)) {
            LibraryUnavailableView(browser: Browser()).environment(libraries)
        }
    }

    // MARK: An index page

    private func indexRows() -> [IndexRow] {
        let now = Date()
        func row(_ title: String, count: Int, minutesAgo: Double) -> IndexRow {
            IndexRow(
                place: .collection(ItemID(UUID().uuidString)), title: title, icon: .symbol("rectangle.stack"), types: "Notes, Tasks",
                count: count, latest: now.addingTimeInterval(-minutesAgo * 60), breakdown: [])
        }
        return [
            row("Field Research", count: 24, minutesAgo: 3), row("Kitchen quotes", count: 8, minutesAgo: 95),
            row("Reading list", count: 112, minutesAgo: 60 * 30), row("Archive", count: 3, minutesAgo: 60 * 24 * 40),
        ]
    }

    private struct IndexHost: View {
        let browser: Browser
        let rows: [IndexRow]
        @FocusState private var pane: Browser.Pane?

        var body: some View {
            IndexPage(
                place: .collections, title: "Collections", browser: browser, pane: $pane, rows: rows,
                tabs: [(.all, rows.count), (.yours, 3), (.fromApps, 1)], tab: .constant(.yours), choice: IndexChoice(), open: { _ in },
                newCollection: {}, emptyTab: EmptyState("Nothing Here"))
        }
    }

    private func indexPage(searching: Bool) -> some View {
        let browser = Browser()
        browser.sidebarItem = .collections
        browser.isSearchExpanded = searching
        return IndexHost(browser: browser, rows: indexRows())
    }

    @Test func indexPageWithSearch() async throws {
        let libraries = ItemPreviewFixtures.libraries(named: "MarfaMac.ButtonRender")
        let library = try await sampleLibrary()
        try await draw("Index page, search open", size: CGSize(width: 820, height: 380)) {
            indexPage(searching: true).environment(\.library, library).environment(libraries)
        }
    }

    @Test func indexPageAtRest() async throws {
        let libraries = ItemPreviewFixtures.libraries(named: "MarfaMac.ButtonRender")
        let library = try await sampleLibrary()
        try await draw("Index page, at rest", size: CGSize(width: 820, height: 380)) {
            indexPage(searching: false).environment(\.library, library).environment(libraries)
        }
    }

    // MARK: The link picker

    @Test func linkPicker() async throws {
        let library = try await sampleLibrary()
        let editor = EditorController(library: FakeItemLibrary())
        try await draw("Link picker", size: CGSize(width: 480, height: 500), settle: .seconds(1)) {
            ItemLinkPicker(editor: editor, itemID: ItemID("00000000-0000-0000-0000-000000000000")).environment(\.library, library)
        }
    }

    // MARK: Banners and the toast

    @Test func banners() async throws {
        let toast = ToastPresenter()
        try await draw("Banners and the toast", size: CGSize(width: 760, height: 300)) {
            VStack(alignment: .leading, spacing: 16) {
                SavedAsCopyBanner(copy: ItemID("10000000-0000-0000-0000-000000000009"))
                PicturesWaitingCallout(count: 2, load: {}, close: {}).padding(.horizontal, 16)
                ToastView(
                    toast: .init(message: "Moved “Kitchen quotes” to Recently Deleted", symbol: "trash", undo: {}), presenter: toast)
                    .padding(.horizontal, 16)
                Spacer()
            }
            .padding(.top, 16)
        }
    }

    // MARK: Quick add

    @Test func quickAdd() async throws {
        let libraries = ItemPreviewFixtures.libraries(named: "MarfaMac.ButtonRender")
        let library = try await sampleLibrary()
        let browser = Browser()
        browser.openQuickAdd(typeID: "core.note", in: library)
        let editor = EditorController(library: FakeItemLibrary())
        try await draw("Quick add", size: CGSize(width: 720, height: 420)) {
            QuickAddPanel(browser: browser, quickAdd: browser.quickAdd, editor: editor)
                .environment(\.library, library).environment(libraries).padding(24)
        }
    }

    // MARK: A sheet on an item page

    @Test func webLinkSheet() async throws {
        let editor = EditorController(library: FakeItemLibrary())
        let request = EditorController.WebLinkRequest(
            itemID: ItemID("10000000-0000-0000-0000-000000000003"), generation: 0, removable: true,
            address: "https://example.com/field-notes")
        try await draw("Item page sheet, Edit Link", size: CGSize(width: 480, height: 200)) {
            WebLinkSheet(editor: editor, request: request)
        }
    }
}

/// Every role at every size, a symbol alone, both menu kinds, a disabled button and the focus ring on each shape.
private struct ButtonGallery: View {
    private static let sizes: [(AppButtonSize, String)] = [(.small, "Small, 24"), (.regular, "Regular, 28"), (.large, "Large, 36")]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Self.sizes, id: \.1) { size, name in
                VStack(alignment: .leading, spacing: 8) {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Cancel") {}.appButton(.secondary, size: size)
                        Button("Save") {}.appButton(.primary, size: size)
                        Button("Delete…") {}.appButton(.destructive, size: size)
                        Button("Show") {}.appButton(.plain, size: size)
                        Button("Disabled") {}.appButton(.secondary, size: size).disabled(true)
                        Button { } label: { Label("New Item", systemImage: "plus") }.appButton(.secondary, size: size)
                        Button("More", systemImage: "ellipsis") {}.labelStyle(.iconOnly).appButton(.secondary, size: size, icon: true)
                        Button("Add", systemImage: "plus") {}.labelStyle(.iconOnly).appButton(.plain, size: size, icon: true)
                        Button("Close", systemImage: "xmark") {}.labelStyle(.iconOnly).appButton(.plain, size: size, icon: true)
                    }
                    HStack(spacing: 10) {
                        menu(.value, "Yellow", size: size)
                        menu(.commands, "Actions", size: size)
                        Button("Focused") {}.appButton(.secondary, size: size)
                            .overlay { AppButtonStyle.focusRing(AppButtonStyle.shape(size: size, isIcon: false)) }
                        Button("Focused", systemImage: "plus") {}.labelStyle(.iconOnly).appButton(.secondary, size: size, icon: true)
                            .overlay { AppButtonStyle.focusRing(AppButtonStyle.shape(size: size, isIcon: true)) }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func menu(_ kind: AppMenuKind, _ title: LocalizedStringKey, size: AppButtonSize) -> some View {
        Menu {
            Button("One") {}
            Button("Two") {}
        } label: {
            Text(title)
        }
        .appMenu(kind, size: size)
    }
}
