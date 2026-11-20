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
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(half.groups.enumerated()), id: \.offset) { index, pages in
                            if index > 0 { Color.clear.frame(height: 10) }
                            ForEach(pages, id: \.self) { page in row(page) }
                        }
                    }
                    if halves.isEmpty {
                        Text("No Results")
                            .font(SettingsTokens.font(.small, scale: scale))
                            .foregroundStyle(SettingsTokens.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                            .accessibilityIdentifier("SettingsSearchEmpty")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
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
            HStack(spacing: 8) {
                SettingsTile(symbol: page.symbol, tone: page.tone, size: 20)
                Text(page.title).font(SettingsTokens.font(.sidebar, scale: scale))
                Spacer(minLength: 4)
                switch badges(page) {
                case .count(let count)?:
                    Text("\(count)")
                        .font(.system(size: 11 * scale, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(SettingsTokens.Tone.red.color, in: .capsule)
                case .dot?:
                    Circle().fill(SettingsTokens.Tone.red.color).frame(width: 8, height: 8)
                case nil:
                    EmptyView()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28 * scale)
            .background(isSelected ? SettingsTokens.selection : Color.clear, in: .rect(cornerRadius: 8, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("SettingsPage-\(page.key)")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(SettingsTokens.tertiaryText)
            TextField("Search", text: $search)
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(SettingsTokens.font(.title, scale: scale))
                .focused($searchFocused)
                .onExitCommand { search = ""; searchFocused = false }
                .accessibilityIdentifier("SettingsSearch")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(SettingsTokens.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28 * scale)
        .background(SettingsTokens.buttonFill, in: .rect(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
