#if DEBUG
import Marfa
import MarfaTesting
import SwiftUI

/// Fixed values and a library held in memory by the sample's fake working copy, so canvas edits reach no server.
enum ItemPreviewFixtures {
    static let projectID = ItemID("10000000-0000-0000-0000-000000000001")
    static let ticketID = ItemID("10000000-0000-0000-0000-000000000002")
    static let noteID = ItemID("10000000-0000-0000-0000-000000000003")
    static let unfamiliarID = ItemID("10000000-0000-0000-0000-000000000004")
    static let date = Date(timeIntervalSince1970: 1_791_000_000)

    /// The libraries a main window reads, on defaults and a store of their own that each call empties, with no
    /// server set.
    @MainActor static func libraries(named name: String = "MarfaMac.ItemPreview") -> Libraries {
        let throwaway = TestHost.isRequested ? ThrowawayDefaults.make(name) : nil
        let suite = throwaway?.suite ?? "\(AppPaths.bundleIdentifier).\(name)"
        let defaults = throwaway ?? UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return Libraries(
            host: MarfaHost(
                defaults: defaults, signIns: ScriptedSignIns(),
                location: MarfaStoreLocation(root: AppPaths.temporary(name))),
            defaults: defaults)
    }

    /// A project with a task and an item filed under it, and a task with a status its type does not declare.
    /// The library reads its copy as it opens, so a preview shows the items a moment after it starts.
    @MainActor static var library: MarfaLibrary {
        MarfaLibrary(source: SampleLibrary.open(SampleLibrary.connection, items: rows, edges: edges, now: date), notices: Notices())
    }

    private static var rows: [Marfa.Item] {
        [
            SampleLibrary.row(
                projectID.rawValue, type: SampleLibrary.projectType,
                properties: ["title": .string("Field Research"), "body": .string("A project with connected work.")],
                created: date, edited: date),
            SampleLibrary.row(
                ticketID.rawValue, type: "core.task",
                properties: [
                    "title": .string("Review the findings"), "status": .string("in_progress"), "priority": .string("high"),
                    "body": .string("Read [[Field notes]] before writing the review."),
                ],
                created: date, edited: date),
            SampleLibrary.row(
                noteID.rawValue, type: "core.note",
                properties: ["title": .string("Field notes"), "body": .string("Start with what we observed.")],
                created: date, edited: date),
            SampleLibrary.row(
                unfamiliarID.rawValue, type: "core.task",
                properties: [
                    "title": .string("Check the archive"), "status": .string("unfamiliar_status"),
                    "custom_property": .string("preserved"), "body": .string("Notes"),
                ],
                created: date, edited: date),
        ]
    }

    private static var edges: [Marfa.Edge] {
        [ticketID, noteID].map { child in
            Marfa.Edge(
                id: "edge-\(child.rawValue)", fromId: projectID.rawValue, toId: child.rawValue, edgeType: "parent-of",
                properties: [:], version: 1, createdAt: SampleLibrary.stamp(date), updatedAt: SampleLibrary.stamp(date))
        }
    }

    static var browser: Browser {
        let browser = Browser()
        // The Library is an index with no page of its own; the Feed's list has the selected item's page beside it.
        browser.showing = .feed
        browser.selection = [ticketID]
        return browser
    }

    static var details: DetailsPresentation {
        let details = DetailsPresentation()
        details.isPresented = true
        return details
    }
}

/// Shows its content once the library has read its copy, since a preview's library opens as it starts.
private struct WhenLoaded<Content: View>: View {
    let library: MarfaLibrary
    @ViewBuilder let content: (MarfaLibrary) -> Content

    var body: some View {
        if library.isLoaded { content(library) } else { ProgressView() }
    }
}

#Preview("Ticket Details") {
    let library = ItemPreviewFixtures.library
    ItemInspectorHost(itemID: ItemPreviewFixtures.ticketID)
        .environment(\.library, library)
        .interfaceTextStyle()
        .frame(width: 330, height: 750)
}

#Preview("Project and Related Work") {
    ItemInspectorHost(itemID: ItemPreviewFixtures.projectID)
        .environment(\.library, ItemPreviewFixtures.library)
        .interfaceTextStyle()
        .frame(width: 330, height: 600)
}

#Preview("Complete Item Window") {
    let library = ItemPreviewFixtures.library
    MainView(browser: ItemPreviewFixtures.browser, details: ItemPreviewFixtures.details, restoresWindow: false)
        .environment(\.library, library)
        .environment(ItemPreviewFixtures.libraries())
        .frame(width: 1280, height: 800)
}

#Preview("Unsaved Property Input") {
    ItemPropertyRow(definition: .init(key: "description", label: "Description", kind: .text, declaredBy: TypeID(SampleLibrary.projectType)),
                    value: .string("Edit this value and press Return to see the save error."),
                    isEditable: true, onChange: { _ in false })
        .padding(16)
        .interfaceTextStyle()
        .frame(width: 330, height: 220)
}
#endif
