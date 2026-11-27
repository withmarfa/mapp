import SwiftUI

/// The Settings window's sidebar, the system's: a search field, then the app's pages and the Marfa's in sections, each page a
/// colored tile, its name and an optional count. A search keeps the pages whose name, or the title of a row they hold, it
/// finds. Each half has a heading and two groups of pages.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPage
    @Binding var search: String
    /// The count a page's row shows at its trailing edge, if it has one.
    var badges: (SettingsPage) -> Int? = { _ in nil }
    @Environment(\.settingsTextScale) private var scale

    private struct Group: Identifiable {
        let name: LocalizedStringKey?
        let pages: [SettingsPage]
        let gap: CGFloat
        let id: Int
    }

    /// The groups as they stand once the search has kept what it finds.
    private var groups: [Group] {
        let matches = SettingsPage.sidebarMatches(search)
        var result: [Group] = []
        for (name, source) in [(LocalizedStringKey("App"), SettingsPage.appGroups), (LocalizedStringKey("Marfa"), SettingsPage.marfaGroups)] {
            let kept = source.map { $0.filter { matches.contains($0) } }.filter { !$0.isEmpty }
            for (index, pages) in kept.enumerated() {
                let gap = index == 0 && !result.isEmpty ? SettingsTokens.Metric.sidebarHalfGap : 0
                result.append(Group(name: index == 0 ? name : nil, pages: pages, gap: gap, id: result.count))
            }
        }
        return result
    }

    var body: some View {
        let groups = groups
        List(selection: Binding<SettingsPage?> { selection.sidebarEntry } set: { if let page = $0 { selection = page } }) {
            ForEach(groups) { group in
                if let name = group.name {
                    groupHeading(name, gap: group.gap)
                    rows(group.pages)
                } else {
                    Section { rows(group.pages) }
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.sidebarRowSize, .small)
        .environment(\.defaultMinListRowHeight, 0)
        .softSelection(rows: groups.map(\.pages), selection: { selection.sidebarEntry })
        .searchable(text: $search, placement: .sidebar, prompt: Text("Search"))
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView.search(text: search).accessibilityIdentifier("SettingsSearchEmpty")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { docsLink }
        .accessibilityIdentifier("SettingsSidebar")
    }

    private func groupHeading(_ name: LocalizedStringKey, gap: CGFloat) -> some View {
        Text(name)
            .settingsFont(.sidebarHeading)
            .foregroundStyle(SettingsTokens.secondaryText)
            .padding(.top, gap)
            .padding(.bottom, SettingsTokens.Metric.sidebarHeadingBottom)
            .accessibilityAddTraits(.isHeader)
            .listRowInsets(.vertical, 0)
            .listRowSeparator(.hidden)
            .selectionDisabled()
    }

    private func rows(_ pages: [SettingsPage]) -> some View {
        ForEach(pages, id: \.self) { page in
            let isSelected = selection.sidebarEntry == page
            HStack(spacing: SettingsTokens.Metric.buttonGap) {
                SettingsTile(symbol: page.symbol, tone: page.tone, size: SettingsTokens.Metric.sidebarTile, rich: true)

                // The system bolds a chosen row's label; the boards and System Settings keep it regular.
                Text(page.title)
                    .settingsFont(.sidebar)
                    .fontWeight(.regular)
                    .foregroundStyle(isSelected ? SettingsTokens.sidebarSelectedText : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let badge = badges(page), badge > 0 { problemBadge(badge) }
            }
            .padding(.leading, SettingsTokens.Metric.sidebarRowLeading)
            .frame(minHeight: SettingsTokens.Metric.sidebarRow * max(1, scale))
            .accessibilityElement(children: .combine)
            .listRowInsets(.vertical, 0)
            .listRowSeparator(.hidden)
            .simultaneousGesture(TapGesture().onEnded {
                if selection != page, selection.sidebarEntry == page { selection = page }
            })
            .tag(page)
            .accessibilityIdentifier("SettingsPage-\(page.key)")
        }
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
                Text("Docs").settingsFont(.title)
                Image(systemName: "arrow.up.right").settingsFont(.linkGlyph).accessibilityHidden(true)
            }
            .foregroundStyle(SettingsTokens.secondaryText)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsTokens.Metric.sidebarFooterInset)
        .padding(.top, SettingsTokens.Metric.sidebarFooterPadding)
        .padding(.bottom, SettingsTokens.Metric.sidebarFooterBottom)
    }
}
