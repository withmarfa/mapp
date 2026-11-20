import SwiftUI

/// The Settings window's sidebar: a search field, then MAPP's pages and the Marfa's in groups split by space, each page
/// a colored tile with a white symbol, its name and an optional badge. A search keeps the pages whose name, or the title
/// of a row they hold, it finds.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPage
    @Binding var search: String
    var badges: (SettingsPage) -> SettingsBadge? = { _ in nil }
    @Environment(\.settingsTextScale) private var scale
    @FocusState private var searchFocused: Bool

    private struct Half: Identifiable {
        let name: LocalizedStringKey
        let groups: [[SettingsPage]]
        var id: String { String(describing: name) }
    }

    /// The halves as they stand once the search has kept what it finds.
    private var halves: [Half] {
        [Half(name: "MAPP", groups: SettingsPage.mappGroups), Half(name: "Marfa", groups: SettingsPage.marfaGroups)].compactMap { half in
            let groups = half.groups.map { $0.filter { $0.matches(search) } }.filter { !$0.isEmpty }
            return groups.isEmpty ? nil : Half(name: half.name, groups: groups)
        }
    }

    /// The pages shown once the search has kept what it finds, in the order the arrow keys move through them.
    private var shownPages: [SettingsPage] { halves.flatMap { $0.groups.flatMap { $0 } } }

    var body: some View {
        let halves = halves
        VStack(spacing: 0) {
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(halves) { half in
                        Text(half.name)
                            .font(SettingsTokens.font(.sidebarHeader, scale: scale))
                            .foregroundStyle(SettingsTokens.secondaryText)
                            .padding(.horizontal, SettingsTokens.Metric.sidebarHeaderInset)
                            .padding(.top, SettingsTokens.Metric.sidebarHeaderTop)
                            .padding(.bottom, SettingsTokens.Metric.sidebarHeaderBottom)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(half.groups.enumerated()), id: \.offset) { index, pages in
                            if index > 0 { Color.clear.frame(height: SettingsTokens.Metric.sidebarGroupGap) }
                            ForEach(pages, id: \.self) { page in row(page) }
                        }
                    }
                    if halves.isEmpty {
                        Text("No Results")
                            .font(SettingsTokens.font(.small, scale: scale))
                            .foregroundStyle(SettingsTokens.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, SettingsTokens.Metric.sidebarEmptyTop)
                            .accessibilityIdentifier("SettingsSearchEmpty")
                    }
                }
                .padding(.horizontal, SettingsTokens.Metric.sidebarInset)
                .padding(.bottom, SettingsTokens.Metric.sidebarBottomInset)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .accessibilityIdentifier("SettingsSidebar")
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let pages = shownPages
        guard let index = pages.firstIndex(of: selection) else {
            if let first = pages.first { selection = first }
            return .handled
        }
        selection = pages[min(pages.count - 1, max(0, index + step))]
        return .handled
    }

    /// A page's row: a colored tile, its name and a badge. The chosen one takes a soft gray, never the accent.
    private func row(_ page: SettingsPage) -> some View {
        let isSelected = page == selection
        return Button { selection = page } label: {
            HStack(spacing: SettingsTokens.Metric.sidebarRowSpacing) {
                SettingsTile(symbol: page.symbol, tone: page.tone, size: SettingsTokens.Metric.sidebarTile)
                Text(page.title).font(SettingsTokens.font(.sidebar, scale: scale))
                Spacer(minLength: SettingsTokens.Metric.badgeLabelSpacing)
                switch badges(page) {
                case .count(let count)?:
                    Text("\(count)")
                        .font(SettingsTokens.font(.count, scale: scale))
                        .foregroundStyle(.white)
                        .padding(.horizontal, SettingsTokens.Metric.badgeInset)
                        .frame(minWidth: SettingsTokens.Metric.badgeSize, minHeight: SettingsTokens.Metric.badgeSize)
                        .background(SettingsTokens.Tone.red.color, in: .capsule)
                case .dot?:
                    Circle().fill(SettingsTokens.Tone.red.color).frame(width: SettingsTokens.Metric.badgeDot, height: SettingsTokens.Metric.badgeDot)
                case nil:
                    EmptyView()
                }
            }
            .padding(.horizontal, SettingsTokens.Metric.sidebarRowInset)
            .frame(height: SettingsTokens.Metric.sidebarRowHeight * scale)
            .background(isSelected ? SettingsTokens.selection : Color.clear, in: .rect(cornerRadius: SettingsTokens.Metric.sidebarRowRadius, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("SettingsPage-\(page.key)")
    }

    private var searchField: some View {
        HStack(spacing: SettingsTokens.Metric.sidebarFieldSpacing) {
            Image(systemName: "magnifyingglass").font(SettingsTokens.font(.small, scale: scale)).foregroundStyle(SettingsTokens.tertiaryText)
            TextField("Search", text: $search)
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(SettingsTokens.font(.title, scale: scale))
                .focused($searchFocused)
                .onExitCommand { search = ""; searchFocused = false }
                .accessibilityIdentifier("SettingsSearch")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(SettingsTokens.font(.small, scale: scale)).foregroundStyle(SettingsTokens.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, SettingsTokens.Metric.sidebarFieldInset)
        .frame(height: SettingsTokens.Metric.sidebarRowHeight * scale)
        .background(SettingsTokens.buttonFill, in: .rect(cornerRadius: SettingsTokens.Metric.sidebarRowRadius, style: .continuous))
        .padding(.horizontal, SettingsTokens.Metric.sidebarFieldMargin)
        .padding(.top, SettingsTokens.Metric.sidebarFieldTop)
        .padding(.bottom, SettingsTokens.Metric.sidebarFieldBottom)
    }
}
