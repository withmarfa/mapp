import SwiftUI

/// The Settings window's sidebar, the system's: a search field, then MAPP's pages and the Marfa's in sections, each page a
/// colored tile, its name and an optional count. A search keeps the pages whose name, or the title of a row they hold, it
/// finds. The first group of each half carries the half's name as its header; the later groups are split by the space the
/// system puts between sections.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPage
    @Binding var search: String
    /// The count a page's row shows at its trailing edge, if it has one.
    var badges: (SettingsPage) -> Int? = { _ in nil }
    @Environment(\.settingsTextScale) private var scale

    private struct Group: Identifiable {
        let name: LocalizedStringKey?
        let pages: [SettingsPage]
        let id: Int
    }

    /// The groups as they stand once the search has kept what it finds.
    private var groups: [Group] {
        var result: [Group] = []
        for (name, source) in [(LocalizedStringKey("MAPP"), SettingsPage.mappGroups), (LocalizedStringKey("Marfa"), SettingsPage.marfaGroups)] {
            let kept = source.map { $0.filter { $0.matches(search) } }.filter { !$0.isEmpty }
            for (index, pages) in kept.enumerated() { result.append(Group(name: index == 0 ? name : nil, pages: pages, id: result.count)) }
        }
        return result
    }

    var body: some View {
        let groups = groups
        List(selection: Binding<SettingsPage?> { selection } set: { if let page = $0 { selection = page } }) {
            ForEach(groups) { group in
                if let name = group.name {
                    Section(name) { rows(group.pages) }
                } else {
                    Section { rows(group.pages) }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, placement: .sidebar, prompt: Text("Search"))
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView.search(text: search).accessibilityIdentifier("SettingsSearchEmpty")
            }
        }
        .accessibilityIdentifier("SettingsSidebar")
    }

    private func rows(_ pages: [SettingsPage]) -> some View {
        ForEach(pages, id: \.self) { page in
            Label {
                Text(page.title).font(SettingsTokens.font(.sidebar, scale: scale))
            } icon: {
                SettingsTile(symbol: page.symbol, tone: page.tone, size: SettingsTokens.Metric.sidebarTile)
            }
            .badge(badges(page) ?? 0)
            .badgeProminence(.increased)
            .tag(page)
            .accessibilityIdentifier("SettingsPage-\(page.key)")
        }
    }
}
