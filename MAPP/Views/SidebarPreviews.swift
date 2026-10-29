#if DEBUG
import Marfa
import SwiftUI

#Preview("Sample Sidebar") {
    Sidebar(browser: Browser(), order: NoteOrder())
        .environment(\.library, MarfaLibrary(source: SampleLibrary.open(SampleLibrary.connection), notices: Notices()))
        .environment(ItemPreviewFixtures.libraries(named: "MAPP.SidebarPreview"))
        .frame(width: 260, height: 740)
}

#Preview("Sidebar Without Favorites") {
    Sidebar(browser: Browser(), order: NoteOrder())
        .environment(\.library, ItemPreviewFixtures.library)
        .environment(ItemPreviewFixtures.libraries(named: "MAPP.SidebarPreview"))
        .frame(width: 260, height: 740)
}

#Preview("Sidebar: 100 Collections") {
    let date = ItemPreviewFixtures.date
    let rows = (1...100).flatMap { index in
        [
            SampleLibrary.row(
                "collection-\(index)", type: "core.collection",
                properties: ["title": .string("Research collection \(index) with a longer title")], created: date, edited: date),
            SampleLibrary.row(
                "child-\(index)", type: "core.note", properties: ["title": .string("Field note \(index)")], created: date,
                edited: date),
        ]
    }
    let edges = (1...100).map { index in
        Marfa.Edge(
            id: "edge-\(index)", sourceId: "child-\(index)", targetId: "collection-\(index)", edgeType: "in-collection",
            properties: [:], version: 1, createdAt: SampleLibrary.stamp(date), updatedAt: SampleLibrary.stamp(date))
    }
    let library = MarfaLibrary(source: SampleLibrary.open(SampleLibrary.connection, items: rows, edges: edges, now: date), notices: Notices())
    let browser = Browser()
    NavigationSplitView {
        Sidebar(browser: browser, order: NoteOrder())
            .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 340)
    } detail: {
        Color.clear
    }
    .environment(\.library, library)
    .environment(ItemPreviewFixtures.libraries(named: "MAPP.LargeSidebarPreview"))
    .frame(width: 700, height: 740)
}
#endif
