import SwiftUI

/// The Settings window's sidebar, the system's: a search field, then the app's pages and the Marfa's in sections, each page a
/// colored tile, its name and an optional count. A search keeps the pages whose name, or the title of a row they hold, it
/// finds. Each half has a heading and two groups of pages.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPage
    @Binding var search: String
    var hasMarfa = true
    /// The count a page's row shows at its trailing edge, if it has one.
    var badges: (SettingsPage) -> Int? = { _ in nil }

    private struct Group: Identifiable {
        let name: LocalizedStringKey?
        let pages: [SettingsPage]
        let id: Int
    }

    /// The groups as they stand once the search has kept what it finds.
    private var groups: [Group] {
        let matches = SettingsPage.sidebarMatches(search)
        var result: [Group] = []
        for (name, source) in [(LocalizedStringKey("App"), SettingsPage.appGroups), (LocalizedStringKey("Marfa"), SettingsPage.marfaGroups)] {
            let kept = source.map { $0.filter { matches.contains($0) } }.filter { !$0.isEmpty }
            for (index, pages) in kept.enumerated() {
                result.append(Group(name: index == 0 ? name : nil, pages: pages, id: result.count))
            }
        }
        return result
    }

    var body: some View {
        let groups = groups
        VStack(spacing: 0) {
            sidebarList(groups)
            docsLink
        }
        .font(nil)
        .searchable(text: $search, placement: .sidebar, prompt: Text("Search"))
        .accessibilityIdentifier("SettingsSidebar")
    }

    private func sidebarList(_ groups: [Group]) -> some View {
        List(selection: Binding<SettingsPage?> { selection.sidebarEntry } set: {
            if let page = $0, canSelect(page) { selection = page }
        }) {
            ForEach(groups) { group in
                Section {
                    rows(group.pages)
                } header: {
                    if let name = group.name { Text(name) }
                }
            }
        }
        .listStyle(.sidebar)
        .softSelection(rows: groups.map(\.pages), selection: { selection.sidebarEntry })
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView.search(text: search).accessibilityIdentifier("SettingsSearchEmpty")
            }
        }
    }

    private func rows(_ pages: [SettingsPage]) -> some View {
        ForEach(pages, id: \.self) { page in
            let isSelected = selection.sidebarEntry == page
            let isEnabled = canSelect(page)
            HStack(spacing: SettingsTokens.Metric.buttonGap) {
                SettingsTile(symbol: page.symbol, tone: page.tone, size: SettingsTokens.Metric.sidebarTile, isSidebar: true)

                Text(page.title)
                    .fontWeight(.regular)
                    .foregroundStyle(isSelected ? SettingsTokens.sidebarSelectedText : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let badge = badges(page), badge > 0 { problemBadge(badge) }
            }
            .padding(.leading, SettingsTokens.Metric.sidebarRowLeading)
            .accessibilityElement(children: .combine)
            .listRowSeparator(.hidden)
            .opacity(isEnabled ? 1 : SettingsTokens.Metric.lockedTileOpacity)
            .selectionDisabled(!isEnabled)
            .disabled(!isEnabled)
            .simultaneousGesture(TapGesture().onEnded {
                if isEnabled, selection != page, selection.sidebarEntry == page { selection = page }
            })
            .tag(page)
            .accessibilityIdentifier("SettingsPage-\(page.key)")
        }
    }

    private func canSelect(_ page: SettingsPage) -> Bool {
        if case .marfa = page { return hasMarfa }
        return true
    }

    private func problemBadge(_ count: Int) -> some View {
        Text(count, format: .number)
            .settingsFont(.sidebarBadge)
            .monospacedDigit()
            .foregroundStyle(SettingsTokens.tileForeground)
            .padding(.horizontal, SettingsTokens.Metric.sidebarBadgePadding)
            .frame(minWidth: SettingsTokens.Metric.sidebarBadgeSize, minHeight: SettingsTokens.Metric.sidebarBadgeSize)
            .background(SettingsTokens.Tone.red.color, in: .capsule)
            .accessibilityLabel(Text("Problems: \(count)"))
    }

    private var docsLink: some View {
        Link(destination: AppLinks.marfaDocumentation) {
            HStack(spacing: SettingsTokens.Metric.sidebarFooterGap) {
                Text("Docs")
                Image(systemName: "arrow.up.right").imageScale(.small).accessibilityHidden(true)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsTokens.Metric.sidebarFooterInset)
        .padding(.top, SettingsTokens.Metric.sidebarFooterPadding)
        .padding(.bottom, SettingsTokens.Metric.sidebarFooterBottom)
    }
}
